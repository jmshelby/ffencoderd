#!/usr/bin/perl -w
#
#   ___    ___                                 __                   __     
# /'___\ /'___\                               /\ \                 /\ \    
#/\ \__//\ \__/   __    ___     ___    ___    \_\ \     __   _ __  \_\ \   
#\ \ ,__\ \ ,__\/'__`\/' _ `\  /'___\ / __`\  /'_` \  /'__`\/\`'__\/'_` \  
# \ \ \_/\ \ \_/\  __//\ \/\ \/\ \__//\ \L\ \/\ \L\ \/\  __/\ \ \//\ \L\ \ 
#  \ \_\  \ \_\\ \____\ \_\ \_\ \____\ \____/\ \___,_\ \____\\ \_\\ \___,_\
#   \/_/   \/_/ \/____/\/_/\/_/\/____/\/___/  \/__,_ /\/____/ \/_/ \/__,_ /
# ffencoderd $Revision: 1.8 $
# Copyright (C) 2008  Iago Tomas
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# @version $Id: ffencoderd.pl,v 1.8 2008/05/13 02:28:12 makoki Exp $
# @author $Author: makoki $
#
##

## @file
# ffencoderd is a daemon that wraps the usage of ffmpeg providing a simple
# SOAP API to control video encoding jobs. ffencoderd is focused on any video
# conversion to flash video format although any format accepted by ffmpeg can be 
# used.
# ffencoderd is divided into two main parts an http server which provides methods
# to add/retrieve files and request the SOAP api. And a second part the encoder daemon
# which converts the video. Each part is runned in background as a daemon process.


package ffencoderd;

use constant START_TIME => time;
use POSIX;
use FindBin ();
use File::Basename ();
use File::Spec::Functions;
use Config;
require Config::General
  or die
  "Config::General is required and was not found on your system.";
use Config::General;

# make the daemon cross-platform, so exec always calls the script
# itself with the right path, no matter how the script was invoked.
my $script = File::Basename::basename($0);
my $SELF = catfile $FindBin::Bin, $script;
use lib File::Basename::dirname($0);
our $BASEDIR = File::Basename::dirname($SELF);
print $BASEDIR."\n";
use ffencoderd::Encoder;
use ffencoderd::Queue;
use ffencoderd::PREFORK;


$|=1;
$0 = "ffencoderd";


# App Data
our $PROGRAM = "ffencoderd";
our $VERSION = "0.4-beta";
our $AUTHOR = "Iago Tomas";



# Globals
our $SHOW_NEWS		= 1;#default show.news
our $LOG			= 0;#default log
our $XML_FILE        = "$BASEDIR/ffencoderd.xml"; #default output.file

#private
my $DELAY			= 0;
my $PROCESS_DIR     = "$BASEDIR/data/process"; # default process dirname
my $FFMPEG_OUTPUT   = "/dev/null"; # default ffmpeg output
my $CONFIG_FILE     = "$BASEDIR/ffencoderd.conf"; # default config file
my $LOGGING = 0;                     # logging off default
my $START_HTTP		= 1; # default start http

# Input validation bits
if ( @ARGV >= 13 ) {
	print "syntax error\n";
	usage();
	exit 1;
}
for ( my $i = 0 ; $i < @ARGV ; $i++ ) {
	if ( $ARGV[$i] =~ /^-version|-V|-v$/ ) {
		print "$PROGRAM $VERSION Copyright (C) 2008  $AUTHOR\n";
		print "This program comes with ABSOLUTELY NO WARRANTY; for details type '$PROGRAM -h'.\n";
		print "This is free software, and you are welcome to redistribute it\n";
		print "under certain conditions; type '$PROGRAM -v' for details.\n";
		exit 1;
	}
	elsif ( $ARGV[$i] =~ /^-usage|-h|-help$/ ) {
		usage();
		exit 0;
	}
	elsif ( $ARGV[$i] eq '-p' ) {
		$PROCESS_DIR = $ARGV[ ++$i ];
	}
	elsif ( $ARGV[$i] eq '-m' ) {
		$XML_FILE = $ARGV[ ++$i ];
	}
	elsif ( $ARGV[$i] eq '-l' ) {
		$LOG = $ARGV[ ++$i ];
	}
	elsif ( $ARGV[$i] eq '-d' ) {
		$DELAY = $ARGV[ ++$i ];
	}
	elsif ( $ARGV[$i] eq '-c' ) {
		$CONFIG_FILE = $ARGV[ ++$i ];
	}
	elsif ( $ARGV[$i] =~ /^-fo|--ffmpeg-output$/  ) {
		$FFMPEG_OUTPUT = $ARGV[ ++$i ];
	}
}

##
# Load config file
##
if(!-e $CONFIG_FILE){
	die "Couldn't find config file ($CONFIG_FILE).\n";
}
my $conf = new Config::General(
	-ConfigFile => $CONFIG_FILE    # fichero de configuracion
);
## @var config
# Config hash
our %config = $conf->getall();
$LOG = ($LOG eq 0)?"$config{'log.dir'}/$config{'log.file'}":"$LOG";
$DELAY = ($DELAY eq 0)?$config{'delay'}:$DELAY;
$XML_FILE = ($XML_FILE eq "$BASEDIR/ffencoderd.xml")?$config{'output.file'}:$XML_FILE;
$PROCESS_DIR = ($PROCESS_DIR eq "$BASEDIR/data/process")?$config{'process.dir'}:$PROCESS_DIR;
if ( $config{'log'} =~ /true/ ) {
	$LOGGING = 1;
}
if ( $config{'http'} =~ /false/ ) {
	$START_HTTP = 0;
}
if ( $config{'show.news'} =~ /false/ ) {
	$SHOW_NEWS = 0;
}
## @var queue
# ffencoderd::Queue instance
our $queue = new ffencoderd::Queue(("queueDir"=>$PROCESS_DIR,"xmlFile"=>$XML_FILE,"dtd"=>$config{'dtd'}));
## @var encoder
# ffencoderd::Encoder instance
our $encoder = new ffencoderd::Encoder((
		"videoDir"=>$config{'video.input.dir'}, 
		"outputDir"=>$config{'video.output.dir'},
		"ffmpeg"=>$config{'ffmpeg'}, 
		"maxProcesses"=>3,
		"ffmpegOutput"=>$FFMPEG_OUTPUT,
		"profilesFile"=>$BASEDIR."/data/profiles.xml"));

my $sigset = POSIX::SigSet->new();
my $action = POSIX::SigAction->new('sigHUP_handler',
                                     $sigset,
                                     &POSIX::SA_NODEFER);
		POSIX::sigaction(&POSIX::SIGHUP, $action);
## @fn void usage()
# show usage dialog
sub usage {
	print "$PROGRAM Copyright (C) 2008  $AUTHOR\n";
	print "This program comes with ABSOLUTELY NO WARRANTY; for details type '$PROGRAM -v'.\n";
	print "This is free software, and you are welcome to redistribute it\n";
	print "under certain conditions; type `$PROGRAM -h' for details.\n";
	print "Usage : $PROGRAM [options]...\n";
	print "Options:\n";
	print "\t-c <config>\t\tPath to configuration file ($BASEDIR/ffencoderd.conf)\n";
	print "\t-d <delay>\t\tDelay between process scans\n";
	print "\t-m <xmlfile>\t\tPath to output file ($BASEDIR/ffencoderd.xml)\n";
	print "\t-p <dirname>\t\tPath to process dir ($BASEDIR/data/process)\n";
	print "\t-l <logfile>\t\tLog to file ($BASEDIR/logs/ffwic.log)\n";
	print "\t--ffmpeg-output|-fo <file>\t\tffmpeg output to file\n";
	print "\t-version|-V|v \t\tShows version number\n";
	print "\t-usage|-help|-h \tShows this message\n";
	print "ex: $PROGRAM -d 20\n";
}
## @fn void sigHUP_handler()
# Safe reload
sub sigHUP_handler {
	appendfile($LOG,"Reloading config...");
      exec($SELF, @ARGV) or die "Couldn't restart: $!\n";
}
## @fn string insert0($date)
# Insert 0: Fix up date strings
# @params int $date 
# @return int with suffix 0 if <10
##
sub insert0 {
	my ($date) = shift;

	if ( $date < 10 ) {
		return "0$date";
	}

	return $date;
}
## @fn String longfmt($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$iddst)
# Long format: Custom datestring for the logfile
# @return String local date string
##
sub longfmt {
	my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $iddst ) =
	  localtime(time);
	my $datestring;

	$year += 1900;
	$mon++;
	$mon        = insert0($mon);
	$mday       = insert0($mday);
	$min        = insert0($min);
	$sec        = insert0($sec);
	$datestring = "$year-$mon-$mday $hour:$min:$sec";

	return ($datestring);
}
## @fn void appendfile($fp,$msg)
# Append file: Append a string to a file.
# @param string $fp File name
# @param string $msg Message to log 
sub appendfile {
	if ( $LOGGING eq 1 ) {
		my ( $fp, $msg ) = @_;
		my $date = longfmt();
		if(! -e "$fp"){
			if ( open( FILE, ">","$fp") ){
				print FILE ("$date : $msg\n");
				close FILE;
			}
			else{
				warn "Couldn't create file $fp";
			}
		}
		elsif ( open( FILE, ">>", "$fp") ) {
			print FILE ("$date : $msg\n");
			close FILE;
		}
		else{
			warn "Problems writing to file $fp";
		}
	}
}

## @fn void createpidfile($pid)
# Create pid file: Crea el archivo con el pid del proceso padre
# @param int $pid Pid number
sub createpidfile {
	my ( $data ) = @_;
	if ( open( FILE, ">", "$config{'pid.dir'}$PROGRAM.pid" ) ) {
		print FILE $data;
		close FILE;
	}
}


## @fn void interrupt()
# Interrupt: Simple interrupt handler
sub interrupt {

	wait;
	appendfile( $LOG, "caught @_ exiting" );
	print "caught @_ exiting\n";

	exit;
}
## @fn void REAPER()
# REAPER - a reaper of dead children/zombies with exit codes to spare
sub REAPER {                            
	my $stiff;
	while (($stiff = waitpid(-1, &POSIX::WNOHANG)) > 0) {
		#warn ("child $stiff terminated -- status $?");
	}
	$SIG{CHLD} = \&REAPER;
}
##
# verificamos si se esta ejecutando en otro proceso
##
if ( -e "$config{'pid.dir'}$PROGRAM.pid") {
	die "A pidfile already exists at $config{'pid.dir'}$PROGRAM.pid, if you're sure ffencoderd isn't running just delete this file.\n";
	
}
if( !-e "$config{'process.dir'}"){
	die "Couldn't init $PROGRAM, $config{'process.dir'} doesn't exist.\n"
}

eval{
	chdir '/';
	close (STDOUT);												# Close file handles to detach from any terminals
	close (STDIN);
	close (STDERR);
	$SIG{CHLD} = \&REAPER;
	main();
};
appendfile( $LOG,$@) if $@;
## @fn void main()
# Init app processes, http server and encoder daemon
sub main{
	if($START_HTTP){
		my $httppid = fork();
		unless ( defined $httppid && $httppid !=0 ) {
			ffencoderd::HTTP::PREFORK::init($config{'host'},$config{'http.port'},$config{'http.spawn.children'},$config{'http.children.lifetime'},$config{'video.output.dir'},$config{'video.input.dir'}) or die "Problem starting http server $!";
			
		}
	}
	##
	# MAIN: Fork and setsid().
	##
	unless ( my $pid = fork() ) {
		my $proc_id = "$$";
	
		if ( open( PIDFILE, ">", "$config{'pid.dir'}$PROGRAM.pid" ) ) {
			print PIDFILE $proc_id;
			close PIDFILE;
		}
		exit if $pid;
		setsid;
		umask 0022;
	
		#close (STDOUT);												# Close file handles to detach from any terminals
		#close (STDIN);
		#close (STDERR);
		my $date = longfmt();
		appendfile( $LOG,"Starting $PROGRAM v$VERSION" );
		while (1) {
			my @processes_files = $queue->update();
			foreach my $process_file (@processes_files){
				if( -e "$PROCESS_DIR/$process_file"){
					my @processes_array = $queue->readProcessFile("$process_file");
					if(@processes_array != 0){
						foreach my $process_data (@processes_array){
							$encoder->encode_video($process_data);
						}
					}
					unlink("$PROCESS_DIR/$process_file") or appendfile($LOG,"Couldn't remove process file ($process_file)");
				}
			}
			sleep $DELAY;
		}
	}
}
exit;
__END__

=pod
	
=head1 DESCRIPTION

ffencoderd is a daemon that wraps the usage of ffmpeg providing a simple
SOAP API to control video encoding jobs. ffencoderd is focused on any video
conversion to flash video format although any format accepted by ffmpeg can be 
used.
ffencoderd is divided into two main parts an http server which provides methods
to add/retrieve files and request the SOAP api. And a second part the encoder daemon
which converts the video. Each part is runned in background as a daemon process.

=head1 INSTALL

Install should be quite straight forward, just by unpackaging and executing the main program file ffencoderd should run. Just be sure to meet all L</REQUIREMENTS> found below.
There are some scripts in the B<doc> folder of the package which should help in the deployment.

Download latest version,

C<mv ffencoderd-varsion.tar.gz /path/to/install/;cd /path/to/install/>

C<tar -xzvf ffencoderd-version.tar.gz> or C<unzip ffencoderd-version.zip>

Edit ffencoderd.conf to meet your system or alternatively create a new config file with needed parameters and pass it with '-c' argument
to ffencoderd

Set permissions to defined paths/files in the config file (B<output.file,video.input.dir,process.dir,video.output.dir,thumbnail.output.dir, log.dir, pid.dir>) set to any you want as long as the user executing ffencoderd has read/write privileges.

C<chmod 644 /path/to/output/dir /video/input/dir /process/dir /video/output/dir /thumbnail/output/dir /log/dir /pid/dir>

ffencoderd runs under the same user and group that executed it. So beware to not run it with root. 

C</path/to/install/ffencoderd.pl -c /path/to/config/file.conf> 

Or run the main program file ffencoderd.pl, it will look for a config file name B<ffencoderd.conf> in the same folder.

C</path/to/install/ffencoderd.pl>
	
Just type '-h' to get possible arguments that can be setted.
Optionally you can use the init script provided in the B<doc> folder, before you'll
need to setup the I<FFENCODERD> and I<PIDFILE> environment variables or put ffencoderd in the
default paths that the scripts looks for.
Be carfeul I<PIDFILE> must point to the location of the pidfile which is setted in the conf file.

For more information about the configuraion file see the L</Configuration File> section.

Once installed and running ( if B<http> config parameter is set to true ) should be possible to access a main page at the address and
port defined in the config file, with your web browser. Example http://localhost:8080/ 
This will show the main page letting you know ffencoderd is succesfully running and gives you some information about it. 
See the L</HTTP Server> section.

Otherwise if you don't want to run ffencoderd HTTP server just set the B<http> config parameter to false, then you may just save your processes in
XML in the B<process.dir> directory defined through the config file. This XML processes definition must validate against the DTD definition of ffencoderd.
The DTD schema may be found in the B<./doc> directory or in the main site.

A typical XML process will look like 

B<E<lt>ffencoderdE<gt>>
B<E<lt>process id="0"E<gt>>
B<E<lt>fileE<gt>filenameE<lt>/fileE<gt>>
B<E<lt>profileE<gt>SomeExistentProfileE<lt>/profileE<gt>>
B<E<lt>parameter name="someName"E<gt>someValueE<lt>/parameterE<gt>>
B<E<lt>parameter name="someName2"E<gt>someValue2E<lt>/parameterE<gt>>
B<E<lt>/processE<gt>>
B<E<lt>/ffencoderdE<gt>>

Just create a file and save it in the B<process.dir>, call it somthing.xml. ffencoderd will parse the file and convert I<filename> with default ffmpeg parameters saving the converted file in
the B<video.output.dir> directory.
ffencoderd SOAP service gots methods to create this files programatically through SOAP, refer to L</SOAP> section. 

=head2 Environment variables

Thesea are the environment variables used by the init script provided in the B<./doc> folder.

=head3 FFENCODERD

The location of the main file program

=head3 PIDFILE

The location of the pidfile created by the ffencoderd daemon, this must be the same as defined in the config file.

=head3 OPTIONS

This variable is optional, you may set any arguments you wish to pass to the start program at init. See L<Command Line Arguments> section for more detail.

=head2 Supported OS

Currently only *UNIX like systems are supported. ffencoderd was developed using an Fedora Core 6 kernel 2.6.18-1.2798.fc6
and perl, v5.8.8 built for i386-linux-thread-multi. Please report on succesful builds on other systems.

=head1 REQUIREMENTS

=over

=item ffmpeg

Tested with FFmpeg version SVN-r8876, Copyright (c) 2000-2007 Fabrice Bellard, et al.

=item perl

Tested with perl, v5.8.8 built for i386-linux-thread-multi.

=back

=head2 Perl DEPENDENCIES

ffencoderd depends on a few cpan perl libraries and ffmpeg.
Please refer to ffmpeg official site for howto install ffmpeg in your system.

=over 

=item IPC::ShareLite

=item Config::General

=item SOAP::Lite (Soap::Transport::HTTP)

=item XML::DOM

=item XML::Simple

=item Pod::WSDL

=item Pod::Xhtml

=item HTML::Template

=back

These are libraries that can all be found at CPAN, so just install them the way you want. Here is an example of how to install them

C<cpan IPC::ShareLite Config::General SOAP::Lite XML::DOM XML::Simple Pod::WSDL Pod::Xhtml HTML::Template>

Beware that you may need root privileges to install them this way. Look at cpan site to install them locally without need to have superprivileges.

=head1 Configuration File

The default configuration filename is ffencoderd.conf which should be located at the same folder of the main program
file. This is just a plain text field with some key value pairs to define config values. Any changes in the file will need ffencoderd restart. Next is some explanation about.

=over

=item B<http>

Start an http server with different services, otherwise only encoding daemon will be started.
Possible values are B<true> or B<false>

=item B<host>

The host address for the http server, this is an IP or hostname that should resolve to the machine in which ffencoderd is 
running.

=item B<http.port>

The port which the http should listen to for incoming connections. This is any port you like, even though normally we will use
an http standard port such as 80 if no other web server are running on the same machine. If not take any port you like.

=item B<http.spawn.children>

The number of children the http server should create at start to listen for incoming connections, this number should depend on your
system. Don't put a too high number here as it could collapse your system.
Example : 10

=item B<http.childeren.lifetime>

This is the number of requests each child will attend before dying and respawning. Leave it in a high number as 100 or modify if you know what
you are doing.

=item B<ffmpeg>

The location of ffmpeg in your filesystem. Example : /usr/bin/ffmpeg

=item B<output.file>

This is the file where ffencoderd puts the information about the encoded files, in xml format. It must be a full path with filename, you may 
put it wherever you want as long as the the ffencoderd has write/read access.

=item B<process.dir>

This is the path to the folder where ffencoderd looks for new file processes, is just a writable folder where ffencoderd will look and/or put some xml files to configure video conversion processes.
ffencoderd will scan this directory every B<delay> seconds for *.xml process definitions, these are XML files that validate the DTD schema given with ffencoderd and that you may found at ffencoderd main's site.
If the http server is not activated or if you prefer to interact directly with the daemon you may save any xml file with process definitions in this directory. The daemon will parse and delete them after finishing defined processes. 

=item B<video.output.dir>

This is the path to a writeable folder where ffencoderd will output converted videos.

=item B<video.input.dir>

This is the path to a writeable folder where ffencoderd will look for videos to encode.

=item B<show.news>

Set this option to show recent news from the project in the main page of the server, possible values are B<true> or B<false>. The news are fetched from http://sourceforge.net/export/rss2_projnews.php?group_id=218142 .

=item B<log>

This parameter defines if internal log messages should be logged, possible values are B<true> or B<false>.

=item B<log.file>

This is the filename for the log file. Example ffencoderd.log

=item B<log.dir>

This is the path to a writeable folder where the logs will be putted in. Example /path/to/install/logs

=item B<pid.dir>

This is the path to a writeable folder where the pidfile will be saved to. Example /var/run/
Remark that last slash is needed.

=item B<dtd>

This is the url of the DTD file that will be added to all output.file control files created by ffencoderd.
Normally this shouldn't be needed to be modified. There's always an updated DTD version at ffencoderd site

=back

Some more explanations may be found in the example config file found in the B<doc> folder.

=head1 Profiles file

The profiles are the way to set up how the ffmpeg command will be made up, these are defined in a file found in the B<data> directory named profiles.xml.
A profile definition has the following elements

=over

=item B<name>

The profile's name, used to reference it.

=item B<ext>

The extension used by this profile as is produced by the conersion command.

=item B<mount>

The mount point where the resources converted with this profile will be accessible.

=item B<type>

Media type to be used in this mount point.

=back

There are also some elements that define the parameters that can be defined through the SOAP API, these parameters are divided into two types, the parameters that define 
the resource to be converted and the parameters that define the converted resource, infile and outfile parameters. Each can have multiple parameter definition and both types are optional, although only infile
can really be optional as if there aren't any outfile parameters defined the conversion command won't do anything at all.
The parameters are defined with next elements : 

=over

=item B<arg>

The argument used for the ffmpeg command, ex: -f

=item B<name>

The name for this parameter, this will be the name to use to define it through the SOAP api, this name has to be unique over infile and outfile parameters.

=item B<default>

The default value for this parameter, this element is optional, if it isn't defined the parameter will only be defined if the user defines it through the SOAP API.

=back

To see some examples, see the profiles file in the B<data> directory. 

=head1 Command Line Arguments

There are several arguments that may be defined when calling ffencoderd. These are

=over 

=item -h|help|usage

Shows a help message with all the possible arguments.

=item -v|V|version

Shows version number and copyright information.

=item -c <configfile>

Sets the config file to be used. Use an absolute path to config file. Example /path/to/config/file.conf

=item -d <delay>

Sets the delay in seconds to scan for processes. Example 40

=item -m <xmlfile>

Sets the path where the output file will be putted in. Example /path/to/output/file.xml

=item -p <dirname>

Sets the path where to look for processes definitions.  Example /path/to/processes/dir

=item -l <logfile>

Sets the path to the file where to write log messages. Example /path/to/log/file.log

=item --ffmpeg-output|-fo <ffmpegoutputfile>

Sets the path to the file where to write ffmpeg encoding output, mainly for debugging purposes. Example /path/to/file.log

=back

=head1 HTTP Server

The HTTP Server of ffencoderd has some paths that may be accesed to interact with ffencoderd, next are the explanations for
all of them.

=over

=item Root path B</>

This path will serve the main information screen of ffencoderd with some information about the program. You got this documentation, a SOAP API reference and 
a monitor to surveil the ffencoderd server.

=item Soap proxy B</soap>

This path is the L<SOAP proxy|/SOAP> access. Is where clients should point to if not using the WSDL functionality.

=item Static path B</static/>

This is the path where static files are served from, it won't output a file index it will only serve existing files from within the ./data/www folder
inside the installed path.

=item Files path B</E<lt>sourceE<gt>/*>

Any encoded resource is referenced through the source parameter returned by the B<getProcess> method from the L<SOAP API |/SOAP>.
To see accessible paths see the profiles section and the profiles files to see which mount points are setted in your server.

=item Upload path B</upload>

This path has a double function, it will output an html form example if accessed via GET method and will save to the video.input.dir parameter folder any
multipart file posted to this path via POST method. After posting a file the server will output an xml with the filename used to save the file, be careful it's not
always the same filename with which you posted yours a random one may be generated if there's already a file with the same name, the extension will be always preserved. And the size of the saved file in bytes.

=item Stats xml file B</stats.xml>

This file is generated each time this is called it outputs an xml file with some statistics of the server. It's mainly used for the monitor in the main
information screen found at B</>.

=item News xml file B</news.xml>

This file is the news file used to show news on the main page, if you don't want to show news on the main page just use the B<show.news> parameter on the config file.

=item Processes xml file B</processes.xml>

This is the same file that output.file from config, this access is for easiness and for monitoring purposes.
 
=back 

=head1 SOAP

The soap proxy may be accessed through the /soap as specified before, even though it can be really 
accessed via any path that is not resolvable to any of listed above.

An WSDL file definition is accesible through any uri at the server just appending B<?wsdl>, so /soap?wsdl will return the spec file. 

ffencoderd SOAP functionality is based on SOAP-Lite so please refer to the module documentation for further information on how the SOAP part works. 

You may post any request to the SOAP server conforming the SOAP 1.1 specification. 

See the API documentation for more information about accesible methods on the server.
	
=head2 API

Constants that are returned by the SOAP API

=over

=item B<FFENCODERD_FAIL> 

Context :  ffencoderd service status functions

value : B<100>

=item B<FFENCODERD_OK>

Context : ffencoderd service status functions

value : B<101>

=item B<FFENCODERD_UNKNOWN> 

Context : ffencoderd encoding processes functions 

value : B<200>

=item B<FFENCODERD_PROCESSING> 

Context : ffencoderd encoding processes functions 

value : B<201>

=item B<FFENCODERD_SUCCESS> 

Context : ffencoderd encoding processes functions 

value : B<202>

=item B<FFENCODERD_PROBLEM> 

Context : ffencoderd encoding processes functions 

value : B<203>

=back

The method returns the status of the ffencoderd process. It returns an integer value corresponding 
to an ffencoderd SOAP API constant

=over 1

=item B<status>

=over 2
 
=item B<Return>

integer : Constant with the status of the server FFENCODERD_OK|FFENCODERD_FAIL. If FFENCODERD_FAIL there is some problem with the server

=back

=back

The method returns an xml with some metadata about the process which has been codified

=over 1

=item B<getProcess>

=over 2

=item B<Parameters>

processId : Identifier for the process, this corresponds to the process identifier returned in getList()
 
=item B<Return>

string : An xml string with some information about the process, mainly its characteristics or FFENCODERD_FAIL if didn't find it

=back

=back

Returns an xml formatted response with a list with uid of ended encoding processes 

=over 1

=item B<getList>

=over 2
 
=item B<Return>

string : An xml string with a list of processes listed by uid

=back

=back

Add a resource to encode

=over 1

=item B<addProcess>

=over 2

=item B<Parameters>

process : The process definition as a complex SOAP structure
 
=item B<Return>

string : Returns a string with a constant indicating if the creation of the process was succesful

=back

=back

Returns the API version

=over 1

=item B<version>

=over 2
 
=item B<Return>

string : A string with the API's version

=back

=back

=head2 Examples

Next is an example of using SOAP-Lite as client to request version number to ffencoderd running in localhost.

	use SOAP::Lite;
	my $soap = SOAP::Lite
       ->proxy('http://localhost:8080/soap')
       ->uri('Service');
	my $invoca = $soap->version();
	my $version = $invoca->result();
	print "ffencoderd v$version";
	
Or the same in PHP would be something like this.

	<?php
		$client = new SoapClient("http://localhost:8080/soap?wsdl",array('uri'=>'Service'));
		echo "ffencoderd v".$client->version()."";
	?>

=head1 See Also

You may also find the developers documentation at ffencoderd's website. 
L<http://ffencoderd.sourceforge.net>

=head1 COPYRIGHT

	Copyright 2008, Iago Tomas
	
This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.

=head1 AVAILABILITY

The latest version of this program should be accessible through the main ffencoderd site

http://ffencoderd.sourceforge.net

=cut
