## @file
# Interact with profiles file

## @class
# Get information about the different enabled profiles, gets data out from the profiles xml file. There is a schema defined
# as DTD in the doc folder. The DTD describes the profile element, see it for more information.
package ffencoderd::Profiles;
#
#   ___    ___                                 __                   __     
# /'___\ /'___\                               /\ \                 /\ \    
#/\ \__//\ \__/   __    ___     ___    ___    \_\ \     __   _ __  \_\ \   
#\ \ ,__\ \ ,__\/'__`\/' _ `\  /'___\ / __`\  /'_` \  /'__`\/\`'__\/'_` \  
# \ \ \_/\ \ \_/\  __//\ \/\ \/\ \__//\ \L\ \/\ \L\ \/\  __/\ \ \//\ \L\ \ 
#  \ \_\  \ \_\\ \____\ \_\ \_\ \____\ \____/\ \___,_\ \____\\ \_\\ \___,_\
#   \/_/   \/_/ \/____/\/_/\/_/\/____/\/___/  \/__,_ /\/____/ \/_/ \/__,_ /
# ffencoderd $Revision$
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
# @version $Id$
# @author $Author$
## 
use POSIX;
use XML::DOM;
=pod
	use POSIX;
	use ffencoderd::Profiles;
	use Data::Dumper;
	my $profiles = new ffencoderd::Profiles(("profiles"=>"./data/profiles.xml"));
	my $mountpoints = $profiles->getMountPoints();
	print Dumper($mountpoints);
	my @profiles_list = $profiles->getProfiles(); # this will reload profiles
	print Dumper(@profiles_list);
	my $default_profile = $profiles->getProfile("default");
	print Dumper($default_profile->{'out'});
=cut
## @cmethod ffencoderd::Profiles new(%params)
# Create a new profile instance
# @param hash %params 
# -profiles Path to profiles file
# @return A Profiles instance
##
sub new{
	my ($class) = shift;
	my (%params) = @_;
	my $self = {};
	$self->{PROFILES_FILE} = $params{"profiles"}; # path to profiles file
	$self->{PROFILES} = undef; # stores complete profiles definition
	$self->{MOUNTPOINTS} = undef; # Stores mount points setted in profiles
	bless $self,$class;
	return $self;
}
## @method hash getProfile($profile_name)
# Return a hash with the profile definition, if profiles information aren't setted tries to set it
# @param String $profile_name Name of the profile to obtain definition
# @return hash Profile definition in a hash Returned hash has the following keys
# - in
#  - name
#   - arg
#   - default
#   - name
#  - ...
# - out
#  - name
#   - arg
#   - default
#   - name
#  - ...
# - mount
# - type
sub getProfile{
	my $self = shift;
	my $profile_name = shift || "default";
	if($self->{PROFILES}){
		if($self->{PROFILES}->{$profile_name}){
			return $self->{PROFILES}->{$profile_name};
		}
	}
	else{
		my @profile_names = $self->getProfiles();
		my @profiles_matched = grep {lc($_) eq lc($profile_name)} @profile_names;
		if(@profiles_matched > 1){
			die "Problem, more than one profile with the same name";
		}
		elsif(@profiles_matched == 1 ){
			return $self->{PROFILES}->{$profile_name};
		}
		else{
			return 0;
		}
	}
	die "Profile wasn't found in profiles file";
}
## @method array getMountPoints()
# Returns all mountpoints stored in MOUNTPOINTS, if $self->{MOUNTPOINTS} is not setted it calls getProfiles 
# to set it up. The returned array contains hashes elements, these have two keys
# @par
# - name The profile name
# - ext The extension that the ffmpeg command produces as output
# - mountpoint The sufix for the path from where to access encoded resources with this profile
# - type  Media type to be used in the mount point
# @return Array With profiles mount points, four keys "name", "ext" ,"type" and "mountpoint"
sub getMountPoints{
	my $self = shift;
	#if(!$self->{MOUNTPOINTS}){
		my @profile_names = $self->getProfiles();
		my @i = ();
		$self->{MOUNTPOINTS} = ();
		for my $profile (keys %{$self->{PROFILES}}){
			push @i,{'name'=> $profile,'ext'=> $self->{PROFILES}->{$profile}->{'ext'},'type' => $self->{PROFILES}->{$profile}->{'type'},'mountpoint' => $self->{PROFILES}->{$profile}->{'mount'}};
			
		}
		$self->{MOUNTPOINTS} = \@i;
	#}
	return $self->{MOUNTPOINTS};
}
## @method array getProfiles()
# Returns an array with names of all existing profiles, it stores profiles information in $self->{PROFILES} 
# may be retrieved with the getProfile method.
# @return Array List with names of profiles
sub getProfiles{
	my $self = shift;
	# Verify that the profiles file exists
	if(-e "$self->{PROFILES_FILE}"){
		my @profile_names;
		my $parser = new XML::DOM::Parser;
		# Try to parse the profiles file
		$doc = $parser->parsefile("$self->{PROFILES_FILE}");
		if(! $doc){
			die "Problem reading profile file ($self->{PROFILES_FILE})";
		}
		my $default = 0;
		my $profiles = $doc->getElementsByTagName("profile");
		# Save into memory profiles for later use
    	for(my $i=0;$i < $profiles->getLength(); $i++){
    		my $profile = $profiles->item($i);
			my $profile_attr = $profile->getAttributes();
			my $profile_name = $profile_attr->getNamedItem("name")->getValue;
			my $profile_mount = $profile_attr->getNamedItem("mount")->getValue;
			my $profile_ext = $profile_attr->getNamedItem("ext")->getValue;
			
			my $profile_type = undef;
			if($profile_attr->getNamedItem("type")){
				$profile_type = $profile_attr->getNamedItem("type")->getValue
			}
			if(lc($profile_name) eq "default"){
				if($default){
					die "More than one default profile defined";
				}
				$default = 1;
			}
			if($profile->hasChildNodes()){
				push @profile_names,$profile_name;
				$self->{PROFILES}{$profile_name}{'mount'} = $profile_mount;
				$self->{MOUNTPOINTS}->{$profile_mount} = $profile_name;
				$self->{PROFILES}{$profile_name}{'type'} = $profile_type;
				$self->{PROFILES}{$profile_name}{'ext'} = $profile_ext;
			}
			else{
				warn("Profile $profile_name isn't defined properly");
				next;
			}
			#
			# Get profile definition into a hash
			#
			if(my $in_tag = $profile->getElementsByTagName('infile')){
				if($in_tag->item(0)){
					my $item = $in_tag->item(0);
					if(!$item->hasChildNodes()){
						next;
					}
					my $in_arguments = $item->getChildNodes();
					for(my $j = 0;$j < $in_arguments->getLength();$j++){
						my $argument = $in_arguments->item($j);
						if($argument->getAttributes()){
							my $argument_attr = $argument->getAttributes();
							my $argument_name = $argument_attr->getNamedItem("name")->getValue;
							my $argument_command = $argument_attr->getNamedItem("arg")->getValue;
							my $argument_default = undef;
							if($argument_attr->getNamedItem("default")){
								$argument_default = $argument_attr->getNamedItem("default")->getValue;
							}
							$self->{PROFILES}{$profile_name}{'in'}{$argument_name} = {'name'=>$argument_name,'arg'=>$argument_command,'default'=>$argument_default};
						}
					}
				}
			}
			if(my $out_tag = $profile->getElementsByTagName('outfile')){
				if($out_tag->item(0)){
					my $item = $out_tag->item(0);
					if(!$item->hasChildNodes()){
						next;
					}
					my $out_arguments = $item->getChildNodes();
					for(my $k = 0;$k < $out_arguments->getLength();$k++){
						my $argument = $out_arguments->item($k);
						if($argument->getAttributes()){
							my $argument_attr = $argument->getAttributes();
							my $argument_name = $argument_attr->getNamedItem("name")->getValue;
							my $argument_command = $argument_attr->getNamedItem("arg")->getValue;
							my $argument_default = undef;
							if($argument_attr->getNamedItem("default")){
								$argument_default = $argument_attr->getNamedItem("default")->getValue;
							}
							$self->{PROFILES}{$profile_name}{'out'}{$argument_name} = {'name'=>$argument_name,'arg'=>$argument_command,'default'=>$argument_default};
						}
					}
				}
			}
    	} # end for
    	
    	if($default){
    		return @profile_names;
    	}
    	else{
    		die "No default profile defined, please define one in $self->{PROFILES_FILE}";
    	}
	}
	else{
		die "Problem reading profile file, see file permissions ($self->{PROFILES_FILE})\n$!";
	}
}
1;