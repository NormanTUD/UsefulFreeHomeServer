#!/usr/bin/perl

our $VERSION = 3;

use strict;
use warnings;
use IO::Socket::INET;
use File::Copy;
use Memoize;
use LWP::Simple;
use IO::Prompt;
use Term::ANSIColor;
use Data::Dumper;

my $pckmgr = '';
my $list_installed_packages = '';
my $distname = '';
if(distribution_name() =~ m#debian|ubuntu#i) {
	$distname = 'debian';
	$pckmgr = "apt-get";
	$list_installed_packages = 'dpkg --list';
} elsif (distribution_name() =~ m#suse#i) {
	$distname = 'suse';
	$pckmgr = "zypper";
	$list_installed_packages = 'zypper packages --installed-only';
} else {
	die "Unknown distribution!";
}

sub error (@);
sub debug (@);

sub distribution_name {
	debug "distribution_name()";
	my $release_string= qx(cat /etc/*-release);
	return $release_string;
}

if(!_is_root()) {
	die "Run this script as root, with `".color("red")."sudo perl install.pl".color("reset").".`\n";
}

my %options = (
	debug => 0
);

memoize 'get_all_installed_packages';

analyze_args(@ARGV);
@ARGV = ();

main();

sub _is_root {
	my $login = (getpwuid $>);
	if($login eq 'root') {
		return 1;
	} else {
		return 0;
	}
}

sub _help {
	my $exit_code = shift;
	print <<EOF;
UsefulFreeHomeServer installer script. Usage:
	sudo perl install.pl <PARAMETERS>

OPTIONAL PARAMETERS:
	--debug			Enables debug-output
EOF
	exit($exit_code);
}

sub analyze_args {
	my @opts = @_;
	for (@opts) {
		if(m#^--debug$#) {
			$options{debug} = 1;
		} elsif (m#^--help$#) {
			_help(0)
		} else {
			warn "Unknown parameter option `$_`\n";
			_help(1);
		}
	}
}

sub update {
	my $latest_version = get("https://raw.githubusercontent.com/NormanTUD/UsefulFreeHomeServer/master/install.pl");

	if($latest_version =~ m!\$VERSION\s*=\s*(\d+);!) {
		my $found_version = $1;
		if($found_version > $VERSION) {
			write_file($0, $latest_version);
			debug "UPDATED VERSION. Old Version: $VERSION, new Version: $found_version";
			debug_qx("perl $0");
			exit();
		}
	} else {
		debug "File could not be retrieved.";
	}
}

sub read_file {
	my $file = shift;
	debug "read_file($file)";

	my $contents = '';

	open my $fh, '<', $file;
	while (<$fh>) {
		$contents .= $_;
	}
	close $fh;

	return $contents;
}

sub write_file {
	my ($file, $contents) = @_;
	debug "write_file($file, ...)";

	open my $fh, '>', $file or die $!;
	print $fh $contents;
	close $fh;
}

sub debug_system {
	my $command = shift;

	debug $command;
	return system($command);
}

sub debug_qx_exit_code {
	my $command = shift;
	debug $command;

	my $output = qx($command 2>&1);
	my $rc = $?;
	$rc = $rc << 8;

	return ($output, $rc);
}

sub debug_qx {
	my $command = shift;

	debug $command;
	if(wantarray()) {
		my @output = qx($command);
		return @output;
	} else {
		my $output = qx($command);
		return $output;
	}
}

sub main {
	update();
	debug "main()";

	debug "Linux-Distro: $distname";

	my $share = '/sambashare/';

	my ($smbpasswd, $smbpasswd2) = (undef, undef);

	while (!defined $smbpasswd) {
		print "Please enter the password for the Samba share (".color("red")."double quotes will be removed!".color("reset").")\n";
		$smbpasswd = prompt('Password:', -e => '*');
		$smbpasswd =~ s#(?:\\)?"##;

		print "Please enter it again to be sure there are no typos.\n";
		$smbpasswd2 = prompt('Password:', -e => '*');

		if($smbpasswd2 ne $smbpasswd) {
			print color("red")."The passwords do not match. Please enter them again.".color("reset");
			if($smbpasswd2 =~ m#"#) {
				print color("red").q#DO NOT USE `"` IN YOUR PASSWORD PLEASE!!!#.color("reset");
			}
			($smbpasswd, $smbpasswd2) = (undef, undef);
		}
	}

	mkdir $share unless -d $share;
	mkdir "$share/ocr" unless -d "$share/ocr";

	my @software = (
		'java',
		'autoconf',
		'automake',
		'libtool',
		'pkg-config',
		'ca-certificates',
		'vim',
		'asciidoc',
		'zsh',
		'git',
		'make',
		'pkg-config',
		'make',
		'git',
		'wget',
		'ghostscript',# bis hierhin ok
		{
			debian => '',
			suse => 'yum'
		},
		'libtool',
		{
			debian => 'imagemagick',
			suse => 'ImageMagick'
		},
		'keyutils',
		'samba',
		#'samba-common',
		{
			debian => 'libpng-dev',
			suse => 'libpng-devel'
		},
		{
			debian => 'g++', 
			suse => 'gcc'
		},
		{
			debian => 'libleptonica-dev',
			suse => 'liblept5'
		},
		{
			debian => 'libpango1.0-dev',
			suse => 'pango-devel'
		},

		{
			debian => 'pdftk',
			suse => { 
				url => "http://download.opensuse.org/repositories/home:/alois/openSUSE_Leap_15.1/noarch/pdftk-3.0.1-lp151.1.1.noarch.rpm"
			}
		},
		{
			debian => 'autotools-dev',
			suse => {
				url => "http://ftp5.gwdg.de/pub/opensuse/repositories/home:/jblunck:/dsc2spec/openSUSE_13.2/noarch/autotools-dev-20140911.1-1.1.noarch.rpm"
			}
		},
		{
			debian => 'zlib1g-dev',
			suse => {
				url => "https://rpmfind.net/linux/opensuse/distribution/leap/15.1/repo/oss/x86_64/zlib-devel-1.2.11-lp151.4.1.x86_64.rpm"
			}
		},
		{
			debian => '',
			suse => 'liblzma5'
		},
		{
			debian => '',
			suse => 'libjbig2'
		},
		{
			debian => '',
			suse => 'libopenjpeg1'
		},
		{
			debian => '',
			suse => 'libjpeg62'
		},
		{
			debian => 'libtiff5-dev',
			suse => {
				url => "https://ftp5.gwdg.de/pub/opensuse/discontinued/update/12.3/x86_64/libtiff5-32bit-4.0.3-2.8.1.x86_64.rpm"
			}
		},
		{# Geht nicht
			debian => 'poppler-utils', 
			suse => {
				url => 'http://download.opensuse.org/repositories/home:/matthewdva:/build:/RedHat:/RHEL-7/complete/x86_64/poppler-utils-0.22.5-6.el7.x86_64.rpm'	
			}
		}
	);

	install_programs(@software);
exit(1);

	install_cpan_module("CPAN");
	install_cpan_module("Digest::MD5");
	install_cpan_module("Carp");
	install_cpan_module("List::Util");
	install_cpan_module("Time::HiRes");
	install_cpan_module("File::Basename");
	install_cpan_module("File::Copy");

	install_tesseract();
	install_tesseract_languages();

	configure_samba($share, $smbpasswd);
	install_auto_ocr($share);
}

sub install_tesseract_languages {
	debug "install_tesseract_languages()";
	foreach my $lang (qw/eng deu deu_frak/) {
		my $to = "/usr/local/share/tessdata/$lang.traineddata";
		my $to2 = "/usr/share/tesseract-ocr/$lang.traineddata";
		if(!-e $to || !-e $to2) {
			debug "Installing $lang...\n\t$to\n\t$to2";
			debug_system("wget https://github.com/tesseract-ocr/tessdata_best/raw/master/$lang.traineddata -O $to");
			copy($to, $to2);
		}
	}
}

sub install_auto_ocr {
	my $share = shift;
	debug "install_auto_ocr($share)";

	my $program_name = "autoocr.pl";
	my $program_path = "/bin/$program_name";

	my $program = '';
	while (<DATA>) {
		s!###SHAREPATH###!"$share/ocr/"!g;
		$program .= $_;
	}
	
	write_file($program_path, $program);

	debug_qx("chmod +x '$program_path'");

	my $crontab = read_file('/etc/crontab');
	if($crontab !~ /\Qautoocr.pl\E/) {
		open my $fh, '>>', '/etc/crontab';
		print $fh "* *	* * *	root    perl $program_path\n";
		close $fh;
	}
}

sub install_tesseract {
	debug "install_tesseract()";
	return if program_installed("tesseract");

	my @commands = (
		'mkdir ~/.tesseractsource',
		'cd ~/.tesseractsource; git clone --depth 1 https://github.com/tesseract-ocr/tesseract.git',
		'cd ~/.tesseractsource/tesseract; ./autogen.sh; autoreconf -i; ./configure; make; make install; ldconfig'
	);

	foreach (@commands) {
		debug_system($_);
	}
}

sub configure_samba {
	my $share = shift;
	my $smbpasswd = shift;
	debug "configure_samba($share, $smbpasswd)";
	my $smb_config_file = '/etc/samba/smb.conf';
	rename $smb_config_file, "$smb_config_file.original";

	my $config = <<EOF;
[global]
workgroup = smb
security = user
map to guest = Bad Password
allow insecure wide links = yes
unix extensions = no

[homes]
comment = Home Directories
browsable = no
read only = no
create mode = 0777

[global]

[ocr]
path = $share
read only = no
public = yes
writable = yes
comment = ocr
printable = no
guest ok = yes
available = yes
create mask = 0777
follow symlinks = yes
wide links = yes

EOF

	open my $fh, '>', $smb_config_file or die $!;
	print $fh $config;
	close $fh;

	debug_system("chmod -R 777 $share");
	debug_system("chown -R ocr:ocr $share");

	debug_system(qq#useradd -p \$(openssl passwd -1 "$smbpasswd") ocr#);
	debug_system("smbpasswd -x ocr");
	debug_system(qq#printf "$smbpasswd\\n$smbpasswd\\n" | smbpasswd -a "ocr"#);

	if(distribution_name() =~ m#debian|ubuntu#) {
		debug_system("service samba restart");
	} else {
		debug_system("systemctl restart smbd.service");
	}

	my $local_ip = get_local_ip_address();

	print <<EOF;
Run These commands on the machines to be connected:

	sudo $pckmgr install cifs-utils
	mkdir ~/nas
	sudo chown -R \$USER:\$USER ~/nas
	sudo mount -t cifs //$local_ip/ocr ~/nas -o user=ocr,password=ocr,uid=\$(id -u),gid=\$(id -g)
EOF
}

sub install_cpan_module {
	my $name = shift;
	debug "install_cpan_module($name)";
	my $ret_code = debug_system(qq#perl -e "use $name"#);
	if($ret_code != 0) {
		my $ret_code_2 = debug_system qq#cpan -i "$name"#;
		if($ret_code_2 != 0) {
			error "CPAN-Module `$name` could not be installed!";
		}
	}
}

sub program_installed {
	my $program = shift;
	debug "program_installed($program)";
	my $ret = qx(whereis $program | sed -e 's/^$program: //');
	chomp $ret;
	my @paths = split(/\s*/, $ret);
	my $exists = 0;
	PATHS: foreach (@paths) {
		if(-e $_) {
			$exists = 1;
			last PATHS;
		}
	}

	if($exists) {
		debug "$program already installed";
	} else {
		warn "$program does not seem to be installed. Please install it!";
	}

	return $exists;
}

sub install_programs {
	debug "install_programs(".join(", ", map { ref $_ ? Dumper $_ : $_ } @_).")";
	foreach my $name (@_) {
		my $program = $name;
		my $installed = 0;
		if(ref $program) {
			$program = $program->{$distname};
			if(ref $program) {
				my $url = $program->{url};
				my $filename = $url;
				$filename =~ s#.*/##g;
				if(!-e $filename) {
					debug_system("wget $url");
				}
				if(-e $filename) {
					my ($stdout, $ret_code) = debug_qx_exit_code("rpm -i $filename");
					if($ret_code != 0 && $stdout !~ m#already installed#) {
						error "Got error while installing rpm -i $filename";
					} else {
						$installed = 1;
					}
				} else {
					error "$filename not found";
				}
			}
		}
		if(!$installed && !is_installed_dpkg($program) && $program ne '') {
			my $ret_code = debug_system "$pckmgr install -y $program";
			if($ret_code != 0) {
				error "Program `$program` could not be installed!";
			}
		}
	}
}

sub get_all_installed_packages {
	debug "get_all_installed_packages()";
	return debug_qx($list_installed_packages);
}

sub is_installed_dpkg {
	my $name = shift;
	debug "is_installed_dpkg($name)";
	my $dpkg = get_all_installed_packages();

	if($dpkg =~ m#\b$name\b#) {
		return 1;
	}
	return 0;
}

sub get_local_ip_address {
	debug "get_local_ip_address()";
	my $socket = IO::Socket::INET->new(
		Proto       => 'udp',
		PeerAddr    => '198.41.0.4', # a.root-servers.net
		PeerPort    => '53', # DNS
	);

	my $local_ip_address = $socket->sockhost;

	return $local_ip_address;
}

sub error (@) {
	foreach (@_) {
		warn color("red")."---> ERROR: $_".color("reset")."\n";
	}
	exit(1);
}

sub debug (@) {
	if($options{debug}) {
		foreach (@_) {
			warn color("blue")."DEBUG: $_".color("reset")."\n";
		}
	}
}

__DATA__
#!/usr/bin/perl

use strict;
use warnings;
use Data::Dumper;
use Digest::MD5 qw/md5_hex/;
use Carp qw/cluck/;
use List::Util qw(sum);
use Time::HiRes qw/gettimeofday/;
use File::Basename;
use File::Copy;

sub debug (@) {
	foreach (@_) {
		warn "\t$_\n";
	}
}

main();

sub main {
	my $dir = ###SHAREPATH###;
	my $running = "$dir/.running";
	if(-e $running) {
		warn "ALREADY RUNNING!";
		exit(1);
	}
	write_file($running, "");

	my @files_that_need_ocr = get_files_that_need_ocr($dir);

	my $i = 0;
	print Dumper @files_that_need_ocr;
	foreach my $file (sort { rand() <=> rand() } @files_that_need_ocr) {
		$i++;
		print "$i of ".scalar(@files_that_need_ocr)."\n";
		if($file =~ m#\.(?:jpe?g|png)$#) {
			ocr_imagefile($file);
		} else {
			ocr_pdf($file);
		}
	}
	unlink($running);
}

sub get_dirs_and_files {
	my $dir = shift;
	my %files_and_folders = (
		files => [],
		folders => []
	);
	opendir(my $HOMEDIR, $dir) || die ("Unable to open directory $dir: $!"); 
	while (my $filename = readdir($HOMEDIR)) { 
		next if $filename =~ m#^\.#;
		chomp $filename;
		if(-d $filename) {
			push @{$files_and_folders{folders}}, "$dir/$filename";
		} else {
			my $path = "$dir/$filename";
			if(-e $dir) {
				if($filename =~ m#\.(pdf|png|jpe?g)$#) {
					push @{$files_and_folders{files}}, "$filename";
				}
			} else {
				die "ERROR: `$dir` could not be found!";
			}
		}
	} 
	closedir($HOMEDIR); 
	
	return %files_and_folders;
}

sub mean {
	my $ret = 0;
	eval {
		$ret = sum(@_) / @_;
	};

	if($@) {
		cluck("Error: $@");
	}
	return $ret;
}

sub get_files_that_need_ocr {
	my $dir = shift;
	debug "get_files_that_need_ocr($dir)";
	my %files = get_dirs_and_files($dir);

	my @files_in_need_for_ocr = ();

	foreach my $file (sort { -s $a <=> -s $b } @{$files{files}}) {
		if($file =~ m#(?:jpe?g|png)#) {
			push @files_in_need_for_ocr, "$dir/$file";
		} elsif (!file_is_ocred("$dir/$file")) {
			debug qq#push \@files_in_need_for_ocr, "$dir/$file"#;
			push @files_in_need_for_ocr, "$dir/$file";
		}
	}

	foreach my $folder (sort { $a cmp $b } @{$files{folders}}) {
		debug "$folder";
		push @files_in_need_for_ocr, get_files_that_need_ocr("$dir/$folder");
	}

	return @files_in_need_for_ocr;
}

sub debug_qx {
	my $command = shift;

	debug $command;
	if(wantarray()) {
		my @output = qx($command);
		return @output;
	} else {
		my $output = qx($command);
		return $output;
	}
}

sub read_file {
	my $file = shift;

	my $contents = '';

	open my $fh, '<', $file;
	while (<$fh>) {
		$contents .= $_;
	}
	close $fh;

	return $contents;
}

sub write_file {
	my ($file, $contents) = @_;
	debug "write_file($file, ...)";

	open my $fh, '>', $file or die $!;
	print $fh $contents;
	close $fh;
}

sub get_random_tmp_file {
	my $extension = shift // '';
	my $rand = rand();
	$rand =~ s#0\.##g;

	while (-e '/tmp/'.$rand.$extension) {
		$rand = rand();
		$rand =~ s#0\.##g;
	}

	return "/tmp/$rand$extension";
}

sub get_text_from_pdf {
	my $file = shift;
	my $cache = shift // 1;

	my $tmp = '/tmp';
	mkdir $tmp unless -d $tmp;

	my $file_md5 = md5_hex($file);
	my $filepath_md5 = "$tmp/$file_md5";
	
	if($cache && -e $filepath_md5) {
		debug "OK!!! Got text for $file in $filepath_md5!!!";
		return read_file($filepath_md5);
	} else {
		my $pdftotext = debug_qx(qq#pdftotext "$file" - | egrep -v "^\\s*\$"#);
		if(length($pdftotext) >= 10) {
			write_file($filepath_md5, $pdftotext);
			return $pdftotext;
		}

		my $textfile = get_random_tmp_file('.txt');

		debug_qx(qq#gs -sDEVICE=txtwrite -o "$textfile" "$file"#);

		if(!-e $textfile) {
			return '';
		} else {
			my $c = read_file($textfile);
			if(length($textfile) >= 10) {
				write_file($filepath_md5, $c);
			}
			return $c;
		}
	}
}


sub file_is_ocred {
	my $file = shift;
	my $cache = shift // 1;

	my $pdftext = get_text_from_pdf($file, $cache);
	print substr($pdftext, 0, 50)."...\n";
	if(length($pdftext) >= 10) {
		return 1;
	} else {
		return 0;
	}
}

sub get_tmp_folder {
	my $file = shift;

	my $tmp = "/tmp/";
	my $md5 = md5_hex($file);
	my $md5tmp = "$tmp/data_$md5";
	mkdir $tmp unless -d $tmp;
	mkdir $md5tmp unless -d $md5tmp;

	return $md5tmp;
}

sub get_dpi {
	my $file = shift;

	my @sizes = ();
	foreach my $line (debug_qx(qq#pdfimages -list "$file" | awk '{print \$13 " " \$14}' | tail -n +2#)) {
		chomp $line;
		warn ">>>>>>>>>>>>>>>>>> $line <<<<<<<<<<<<<<<<";
		#					      | awk '{print $13 " " $14}' | tail -n +2
		if($line =~ /(\d+)\s+(\d+)/) {
			push @sizes, $1;
			push @sizes, $2;
		}
	}

	my $ret = sprintf("%d", mean(@sizes));

	return $ret;
}

sub ocr_imagefile {
	my $file = shift;

	my $basename = remove_jpg($file);

	debug_qx(qq#convert "$file" "$basename.pdf"; rm -f $file#);
	
	ocr_pdf("$basename.pdf");

	unlink($file);
}

sub ocr_pdf {
	my $file = shift;

	return if file_is_ocred($file, 0);

	my $rand_path = get_tmp_folder($file); #get_random_tmp_folder();

	my $dpi = get_dpi($file);

	debug_qx(qq#pdfseparate "$file" $rand_path/%d.pdf#);

	opendir my $DIR, $rand_path or die "Can't open $rand_path: $!";
	my @pdfs = grep { /\.(?:pdf)$/i } readdir $DIR;
	closedir $DIR;

	foreach my $pdf (@pdfs) {
		next if $pdf =~ m#^0+#;
		my $number = remove_pdf($pdf);
		$number = add_leading_zeroes($number);
		debug_qx(qq#cd $rand_path; gs -dNOPAUSE -dBATCH -sDEVICE=jpeg -r$dpi -sOutputFile=$number.jpg "$pdf"; rm -f $pdf#);
	}

	opendir $DIR, $rand_path or die "Can't open $rand_path: $!";
	my @images = grep { /\.(?:jpg)$/i } readdir $DIR;
	closedir $DIR;

	my $language = guess_language($file);

	my @times = ();
	my $i = 0;
	foreach my $jpegpath (@images) {
		my $starttime = gettimeofday();
		next if -e remove_jpg($jpegpath).".pdf";
		$i++;
		printf("%d of %d, %.2f percent\n", $i, scalar(@images), (($i / scalar(@images)) * 100));
		if(@times) {
			my $avg_time = mean(@times);
			my $resttime = $avg_time * ((scalar(@images) - $i) + 1);
			
			printf("Avg. time: %s, rest time: %s\n", 
				humanreadabletime($avg_time), 
				humanreadabletime($resttime));
		}
		my $border_command = qq#cd $rand_path; convert $jpegpath -bordercolor White -border 10x10 $jpegpath#;
		debug_system($border_command);
		my $ocr_command = "cd $rand_path; tesseract -l ".$language.' '.$jpegpath.' '.remove_jpg($jpegpath)." pdf; rm -f $jpegpath";
		debug_system($ocr_command);

		my $endtime = gettimeofday();
		push @times, $endtime - $starttime;
	}

	sleep 5;

	opendir $DIR, $rand_path or die "Can't open $rand_path: $!";
	@pdfs = grep { /\.(?:pdf)$/i } readdir $DIR;
	closedir $DIR;

	#debug_qx(qq#cd $rand_path; pdfunite "#.join('" "', sort @pdfs).qq#" "#.get_filename_from_path($file).qq#"#);
	debug_qx(qq#cd $rand_path; pdftk "#.join('" "', sort @pdfs).qq#" cat output "#.get_filename_from_path($file).qq#"#);

	my $pdf_file = "$rand_path/".get_filename_from_path($file);

	if(-e $pdf_file) {
		debug_qx(qq#gs -sDEVICE=pdfwrite -dCompatibilityLevel=1.4 -dPDFSETTINGS=/ebook -dNOPAUSE -dQUIET -dBATCH -sOutputFile=$pdf_file.small $pdf_file#);
		debug "Copying $pdf_file to $file";
		copy("$pdf_file.small", $file) or die $!;
	}
}

sub remove_pdf {
	my $filename = shift;
	$filename =~ s#\.pdf$##g;
	return $filename;
}



sub remove_jpg {
	my $filename = shift;
	$filename =~ s#\.jpe?g$##g;
	return $filename;
}

sub add_leading_zeroes {
	my $number = shift;
	return $number if length($number) >= 5;
	while (length($number) != 5) {
		$number = "0$number";
	}
	return $number;
}

sub guess_language {
	my $file = shift;

	return 'deu+eng';

	my $text = get_text_from_pdf($file);
	my $language = langof($text);
	
	if($language =~ /^de$/i) {
		$language = "deu";
	} elsif ($language =~ /^en$/) {
		$language = "eng";
	} else {
		$language = "eng";
	}

	return $language;
	#### TODO!!!
}

sub get_filename_from_path {
	my $filepath = shift;

	my ($name, $path, $suffix) = fileparse($filepath);

	return $name;
}

sub debug_system {
	my $command = shift;

	debug $command;
	return system($command);
}

sub humanreadabletime {
	my $hourz = int($_[0] / 3600);
	my $leftover = $_[0] % 3600;
	my $minz = int($leftover / 60);
	my $secz = int($leftover % 60);

	return sprintf ("%02d:%02d:%02d", $hourz,$minz,$secz)
}


sub already_running {
	my $command = 'ps auxf | grep "autoocr.pl" | grep -v grep | wc -l';
	
	my $number = debug_qx($command);
	chomp $number;
	if($number > 1) {
		debug "ALREADY RUNNING!";
		return 1;
	} else {
		debug "*NOT* ALREADY RUNNING!";
		return 0;
	}
}
