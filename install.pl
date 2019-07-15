#!/usr/bin/perl

our $VERSION = 2;

use strict;
use warnings;
use IO::Socket::INET;
use File::Copy;
use Memoize;
use LWP::Simple;

sub error (@);
sub debug (@);

memoize 'get_dpkg_list';

main();

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
	if(!is_root()) {
		error "Run program with sudo!";
	}

	update();

	my $share = '/sambashare/';

	mkdir $share unless -d $share;
	mkdir "$share/ocr" unless -d "$share/ocr";

	my @software = (
		'g++',
		'autoconf',
		'automake',
		'libtool',
		'pkg-config',
		'libpng-dev',
		'libtiff5-dev',
		'zlib1g-dev',
		'ca-certificates',
		'g++',
		'pdftk',
		'vim',
		'zsh',
		'git',
		'libtool',
		'libleptonica-dev',
		'make',
		'pkg-config',
		'asciidoc',
		'libpango1.0-dev',
		'git',
		'autotools-dev',
		'make',
		'ghostscript',
		'imagemagick',
		'poppler-utils',
		'keyutils',
		'samba',
		'samba-common',
		'wget'
	);
	install_program(@software);

	install_cpan_module("CPAN");
	install_cpan_module("Digest::MD5");
	install_cpan_module("Carp");
	install_cpan_module("List::Util");
	install_cpan_module("Time::HiRes");
	install_cpan_module("File::Basename");
	install_cpan_module("File::Copy");

	install_tesseract();
	install_tesseract_languages();

	configure_samba($share);
	install_auto_ocr($share);
}

sub install_tesseract_languages {
	foreach my $lang (qw/eng deu deu_frak/) {
		my $to = "/usr/local/share/tessdata/$lang.traineddata";
		my $to2 = "/usr/share/tesseract-ocr/$lang.traineddata";
		if(!-e $to || !-e $to2) {
			debug_system("wget https://github.com/tesseract-ocr/tessdata_best/raw/master/$lang.traineddata -O $to");
			copy($to, $to2);
		}
	}
}

sub install_auto_ocr {
	my $share = shift;

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
	if($crontab !~ /autoocr\.pl/) {
		open my $fh, '>>', '/etc/crontab';
		print $fh "* *	* * *	root    perl $program_path\n";
		close $fh;
	}
}

sub install_tesseract {
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

	debug_system("useradd -p \$(openssl passwd -1 ocr) ocr");
	debug_system("smbpasswd -x ocr");
	debug_system(qq#printf "ocr\\nocr\\n" | smbpasswd -a ocr#);

	debug_system("systemctl restart smbd.service");

	my $local_ip = get_local_ip_address();

	print <<EOF;
Run These commands on the machines to be connected:

	sudo apt-get install cifs-utils
	mkdir ~/nas
	sudo chown -R \$USER:\$USER ~/nas
	sudo mount -t cifs //$local_ip/ocr ~/nas -o user=ocr,password=ocr,uid=\$(id -u),gid=\$(id -g)
EOF
}

sub is_root {
	my $login = (getpwuid $>);
	return 0 if $login ne 'root';
	return 1;
}

sub install_cpan_module {
	my $name = shift;
	debug_system qq#cpan -i "$name"#;
}

sub program_installed {
	my $program = shift;
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

sub install_program {
	foreach my $name (@_) {
		if(!is_installed_dpkg($name)) {
			debug_system "apt-get install -y $name";
		}
	}
}

sub get_dpkg_list {
	return debug_qx("dpkg --list");
}

sub is_installed_dpkg {
	my $name = shift;
	my $dpkg = get_dpkg_list();

	if($dpkg =~ m#\b$name\b#) {
		return 1;
	}
	return 0;
}

sub get_local_ip_address {
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
		warn "---> ERROR: $_\n";
	}
	exit(1);
}

sub debug (@) {
	foreach (@_) {
		warn "DEBUG: $_\n";
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
