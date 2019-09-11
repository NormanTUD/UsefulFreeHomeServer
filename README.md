# UsefulFreeHomeServer

This installs a bunch of software on Debian-systems that makes it a useful server for at home

## Requirements

Please run the following commands before executing this script:

> sudo cpan -i IO::Prompt

> sudo cpan -i Linux::Distribution

> sudo cpan -i Term::ANSIColor

## Run the installer

> sudo perl install.pl

Or, if you'd like to know more of what happens,

> sudo perl install.pl --debug

## More details

Specificially, this set up a Samba-Server on which there is an OCR-folder that, whatever you put
into it (JPG, PNG, PDF, ...), OCR's it and creates a searchable PDF.

## Operating Systems

This script was only tested to the latest Debian version, and may also work in Ubuntu. But I haven't 
tested that. Also, this is tested in OpenSuse Leap 15.1.

## Future

More features to come! Though I have not a single clue which ones...
