## @file
# Implementation of the encoder functions, wraps the ffmpeg cli call.


#
#   ___    ___                                 __                   __     
# /'___\ /'___\                               /\ \                 /\ \    
#/\ \__//\ \__/   __    ___     ___    ___    \_\ \     __   _ __  \_\ \   
#\ \ ,__\ \ ,__\/'__`\/' _ `\  /'___\ / __`\  /'_` \  /'__`\/\`'__\/'_` \  
# \ \ \_/\ \ \_/\  __//\ \/\ \/\ \__//\ \L\ \/\ \L\ \/\  __/\ \ \//\ \L\ \ 
#  \ \_\  \ \_\\ \____\ \_\ \_\ \____\ \____/\ \___,_\ \____\\ \_\\ \___,_\
#   \/_/   \/_/ \/____/\/_/\/_/\/____/\/___/  \/__,_ /\/____/ \/_/ \/__,_ /
# ffencoderd $Revision: 1.6 $
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
# @version $Id: Encoder.pm,v 1.6 2008/05/13 02:28:13 makoki Exp $
# @author $Author: makoki $
## 


## @class
#This class wraps the usage of ffencoderd, uses Profiles class and the user defined parameters to
# generate a command line with ffmpeg and execute it.
package ffencoderd::Encoder;


use POSIX;
use XML::DOM;
use Data::Dumper;
require IPC::ShareLite or die "Can't locate IPC::ShareLite";
use IPC::ShareLite;
use ffencoderd::Profiles;

@ISA = ("ffencoderd");

## @cmethod ffencoderd::Encoder new(%params)  
# Create Encoder instance, defines settings used by all encoding sessions
# @param hash $params A hash with the following keys
# - videoDir Path to folder where videos are
# - outputDir Path to folder where to save encoded files
# - maxProcesses Max. number of concurrent encoding sessions
# - profilesFile Absolute path to the xml profiles file
# - ffmpeg Path to ffmpeg binary (default /bin/ffmpeg)
# - ffmpegOutput Path to file where to save ffmpeg output (default /dev/null)
sub new{
	my ($class) = shift;
	my (%params) = @_;
	my $self = {};
	$self->{VIDEODIR} = $params{"videoDir"}; # Path where to look for resources to encode
	$self->{OUTPUTDIR} = $params{"outputDir"}; # Path where to output converted resources
	$self->{MAX} = $params{"maxProcesses"}; # Max number of concurrent encoding sessions
	$self->{FFMPEG} = $params{"ffmpeg"} || "/bin/ffmpeg"; # path to ffmpeg binary or try with /bin/ffmpeg
	$self->{FFMPEG_OUTPUT} = $params{"ffmpegOutput"} || "/dev/null"; # On windows "/dev/null" = "nul" ??
	$self->{PROFILES_FILE} = $params{"profilesFile"};
	$self->{PROFILES} = new ffencoderd::Profiles(("profiles"=>$params{"profilesFile"}));
	$self->{PROFILES}->getProfiles();
	$self->{SHARED} = IPC::ShareLite->new(
        -key     => 1456,
        -create  => 'yes',
        -destroy => 'yes',
        -size	 => '1024'
    ) or die "Problem with IPC::ShareLite $!";
	$self->{SHARED}->store( "0;0;0" );#Initialize statistics (running procs;overall procs;total processing time)
	
	bless $self,$class;
	return $self;
}

## @method string getStats()
# Get shared mem stats
# @return string encoder usage statistics in a string with semicolon to separate the three values given (running procs;overall procs;total processing time)
sub getStats{
	my $self = shift;
	my $stats = $self->{SHARED}->fetch() || return undef;
	return $stats;
}
## @method int getNumberOfProcesses()
# Get the number of running encoding sessions
# @return int Number of running encoding processes
sub getNumberOfProcesses{
	my $self = shift;
	my $stats = $self->{SHARED}->fetch() || return undef;
	my ($count,$overall,$processingtime) = split(";",$stats);
	return int($count);
}
## @method int add_running_process()
# Adds a running session to the shared mem stats (internal use)
# @return int 1 if success 0 if fail
sub add_running_process{
	my $self = shift;
	if($self->{SHARED}->lock()){
		my $stats = $self->{SHARED}->fetch();
		my ($count,$overall,$processingtime) = split(";",$stats);
		my $new_count = int($count) + 1;
		my $new_overall = int($overall) + 1;
		$self->{SHARED}->store("$new_count;$new_overall;$processingtime"); 
		$self->{SHARED}->unlock();
		return 1;
	}
	return 0;
}
## @method int end_process(%data,$proctime)
# Remove an encoding session from the shared mem stats (internal use)
# @param hash $data A hash with process data, the following keys may be setted
# - id User defined identifier
# - source Unique identifier for this process
# - description A brief description of this process
# - size The resource size in pixels, normally represented by a string wxh (ex. 320x240)
# - format A string representing the format used to encode this resource, as for ffmpeg
# - filename The original name of this resource in servers filesystem
# @param int $proctime Conversion running time  in number of seconds
# @return boolean 1 if success 0 if fail
sub end_process{
	my $self = shift;
	my $data = shift;
	my $proctime = shift||0;
	if($data){
		$ffencoderd::queue->append_xml($data)
	}
	if($self->{SHARED}->lock()){
		my $stats = $self->{SHARED}->fetch();
		my ($count,$overall,$processingtime) = split(";",$stats);
		my $new_count = int($count) - 1;
		my $new_time = int($processingtime) + int($proctime);
		$self->{SHARED}->store("$new_count;$overall;$new_time"); 
		$self->{SHARED}->unlock();
		return 1;
	}
	return 0;
}
## @method void encode_video(%process_data)
# Start a new thread to work in the encoding session
# @param hash %process_data Encoding session definition has the following keys
# - id User defined scalar as identifier of this resource
# - file File name as in the server's fs
# - profile Profile to use for this conversion
# - parameters An array with hash elements nested, these elements contain only one key which has to correspond to a profile parameter name so its value is setted
sub encode_video{
	my $self = shift;
	my $process_data = shift;
	my $guid = _guid();
	while($self->add_running_process() == 0){
		sleep 1;
		next;
	}
	ffencoderd::appendfile( $ffencoderd::LOG,"Starting process with identifier $process_data->{id} and source $guid" );
	unless(my $pid = fork){
			$self->_encode_video($process_data,$guid);
		exit;
	}
}
## @method private void _encode_video(%process_data,$guid)
# Parse encoding definition and start encoding with ffmpeg
# @param hash $process_data With the following keys
# - id User defined scalar as identifier of this resource
# - file File name as in the server's fs
# - profile Profile to use for this conversion
# - parameters An array with hash elements nested, these elements contain only one key which has to correspond to a profile parameter name so its value is setted
# @param String $guid Session identifier
sub _encode_video {
	my $start_time = time;
	my $self = shift;
	my $process_data  = shift;
	# This identifier will give the name to created files
	my $guid       = shift; 
	my $profile_data = undef;
	my $profile_name = 'default';
	if($process_data->{profile}){
		$profile_data = $self->{PROFILES}->getProfile($process_data->{profile});
		$profile_name = $process_data->{profile};
		
	}
	elsif($profile_data = $self->{PROFILES}->getProfile($profile_name)){
		ffencoderd::appendfile($ffencoderd::LOG,"Using default profile for process $process_data->{id}, $guid");
	}
	else{
		ffencoderd::appendfile( $ffencoderd::LOG,"Couldn't find a suitable profile, default doesn't exist nor the one espcified" );
		my $duration = time - $start_time;
		while($self->end_process(undef,$duration) == 0){
			sleep 2;
			next;
		}
		die "Profile not found ($process_data->{profile})";
	}
	if(!-f "$self->{VIDEODIR}/$process_data->{file}"){
		ffencoderd::appendfile( $ffencoderd::LOG,"$self->{VIDEODIR}/$process_data->{file} File not found" );
		my $duration = time - $start_time;
		while($self->end_process(undef,$duration) == 0){
			sleep 2;
			next;
		}
		die "File not found";
	}
	# set an array with arguments to define de command line call
	my @ffmpeg_args = ();
	if($profile_data->{'in'}){
		my @in_args = getArguments($profile_data->{'in'},$process_data);
		push (@ffmpeg_args,@in_args);
	}
	push (@ffmpeg_args,"-i", "$self->{VIDEODIR}/$process_data->{file}","-y");
	if($profile_data->{'out'}){
		my @out_args = getArguments($profile_data->{'out'},$process_data);
		push (@ffmpeg_args,@out_args);
	}
	my $extension = "tmp";
	if($profile_data->{'ext'}){
				$extension = $profile_data->{'ext'};
	}	
	unshift(@ffmpeg_args,$self->{FFMPEG}); # Add binary call to start
	push (@ffmpeg_args,"$self->{OUTPUTDIR}/$guid.$extension"); #
	
	my $ffmpeg_command = join(" ",@ffmpeg_args);
	my %data = (
		id   => "$process_data->{id}",
		source   => "$guid",
		description => "$ffmpeg_command",
		size        => "",
		format      => "$profile_name",
		filename    => "$process_data->{file}"
	);	
	
	#execute the command
	my $t = `echo '$ffmpeg_command' >>$self->{FFMPEG_OUTPUT}`;
	my $log_data = `$ffmpeg_command 2>>$self->{FFMPEG_OUTPUT}`;
	my $duration = time - $start_time;
	while($self->end_process(\%data,$duration) == 0){
		sleep 2;
		next;
	}
} 
## @fn array getArguments(%parameters_list,%process_data)
# Returns arguments for the command line call depending on user defined arguments and the ones from the profile
# @param hash $parameters_list Array with the profiles defined parameters
# @param hash $process_data Array with user defined parameters
# @return array List of validated parameters to be used in the command line call
sub getArguments{
	my $parameters_list = shift;
	my $process_data = shift;
	my @ffmpeg_args = ();
	for my $argument_name (keys %{$parameters_list}){
		#set value
		my $argument_value = undef;
		my $command_argument = $parameters_list->{$argument_name}->{arg};
		#verify if user defined
		if(defined($process_data->{$argument_name})){
			$argument_value = $process_data->{$argument_name};
		}
		#verify if default value
		elsif(defined($parameters_list->{$argument_name}->{default})){
			$argument_value = $parameters_list->{$argument_name}->{default};
		}
		# set only if value not undef 
		if(defined($argument_value)){
			push (@ffmpeg_args,$command_argument,$argument_value);
		}
	}
	return @ffmpeg_args;
		
}
## @method void DESTROY()
# Destroy shared memory 
sub DESTROY{
	my $self = shift;
	$self->{SHARED} = undef;
}
## @fn string _guid()
# Create a unique identifier backportable
# @FIX @arguments problem
# @return string Unique identifier
sub _guid {

	my $uuid_str;

	#	my @arguments = shift;
	#	if (@ARGV) {
	#		$uuid_str = $ARGV[0];
	#	}
	#	else {
	eval {
		require Data::UUID;
		my $ug = new Data::UUID;
		$uuid_str = $ug->create_str;
	};
	$uuid_str =~ s/-//gi; 
	#		if ($@) {
	#			$uuid_str = `uuidgen`;
	#			$uuid_str =~ s/\r?\n?$//;
	#		}
	return $uuid_str;

	#	}
}

1;
