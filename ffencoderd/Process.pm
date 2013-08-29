## @file
#Process representation for the SOAP service

## @class
# Implements the definition of an encoding process with four properties, this object defines a complex type used by the SOAP service
# - file File name to encode
# - id Public identifier not unique in the server
# - profile Profile name to use for the encoding process
# - parameters Array with profile parameters names as keys and values for them as value
package ffencoderd::Process;
#
#   ___    ___                                 __                   __     
# /'___\ /'___\                               /\ \                 /\ \    
#/\ \__//\ \__/   __    ___     ___    ___    \_\ \     __   _ __  \_\ \   
#\ \ ,__\ \ ,__\/'__`\/' _ `\  /'___\ / __`\  /'_` \  /'__`\/\`'__\/'_` \  
# \ \ \_/\ \ \_/\  __//\ \/\ \/\ \__//\ \L\ \/\ \L\ \/\  __/\ \ \//\ \L\ \ 
#  \ \_\  \ \_\\ \____\ \_\ \_\ \____\ \____/\ \___,_\ \____\\ \_\\ \___,_\
#   \/_/   \/_/ \/____/\/_/\/_/\/____/\/___/  \/__,_ /\/____/ \/_/ \/__,_ /
# ffencoderd $Revision: 1.4 $
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
# @version $Id: Process.pm,v 1.4 2008/05/13 02:28:13 makoki Exp $
# @author $Author: makoki $
## 

=pod 

=begin WSDL

	_ATTR profile $string Use profile for this process
	_ATTR file $string Video file to convert
	_ATTR id $int ID for external identification, may be any integer you want
	_ATTR parameters @string List of parameters to pass to ffmpeg

=end WSDL

=cut
## @cmethod ffencoderd::Process new()
# Create a Process instance, used by SOAP::Lite to define a complex data structure
sub new {
    bless {
      file => undef, # Filename (in server filesystem) to encode
      id => -1, # Process identifier, hasn't any use in server side
      profile => "default", # Profile name to use for encoding session
      parameters => (), # Parameters,as defined in the profile, to be setted for this session 
    }, $_[0];
}

1;