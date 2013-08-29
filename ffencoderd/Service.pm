## @file
# Implements the webservice of ffencoderd

## @class 
# Service class of ffencoderd. Used as dispatcher by soap::lite used to route soap requests to the /soap path of the server.
# This class implements the functionality of the webservice. See its documentation to learn about the SOAP API of ffencoderd.
package Service;
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
# @version $Id: Service.pm,v 1.6 2008/05/13 02:28:13 makoki Exp $
# @author $Author: makoki $
##

use ffencoderd::Process;
use XML::DOM;
use XML::Simple;
use Data::Dumper;
@ISA = ("ffencoderd");

=pod

=head1 Constants

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

=cut

#
# Constant definition
#
use constant FFENCODERD_FAIL => 100;
use constant FFENCODERD_OK => 101;
use constant FFENCODERD_UNKNOWN => 200;
use constant FFENCODERD_PROCESSING => 201;
use constant FFENCODERD_SUCCESS => 202;
use constant FFENCODERD_PROBLEM => 203;

=pod

=head1 Metodos 

The following methods conform the SOAP interface of ffencoderd, they may be accesed through the SOAP proxy available, here you can find some information on how to use them.

=head2 L<status>

The method returns the status of the ffencoderd process. It returns an integer value corresponding 
to an ffencoderd SOAP API constant

=over 1

=item B<status>

=over 2
 
=item B<Return>

integer : Constant with the status of the server FFENCODERD_OK|FFENCODERD_FAIL. If FFENCODERD_FAIL there is some problem with the server

=back

=back

=begin WSDL

 _RETURN $int Constant with the status of the server

=end WSDL

=cut

## @method int status()
# returns a constant indicating the status of the server
# @return int FFENCODERD_OK if server running correctly, FFENCODERD_FAIL otherwise
sub status {
	my $encoder_status = $ffencoderd::encoder->getNumberOfProcesses();
	if(!defined $encoder_status && $encoder_status != 0) {
		return FFENCODERD_FAIL;
	}
	return FFENCODERD_OK;
}


=head2 L<getProcess>

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

=begin WSDL

 _IN processId $string Process uid
 _RETURN $string An xml string

=end WSDL

=cut

## @method string getProcess($processID)
# Returns an xml string with metadata about the requested process
# @param string $processId A uid of an existing ended encoding process
# @return string An xml string with metadata about the encoding process or FFENCODERD_FAIL if was not found
sub getProcess{
    my $self = shift;
    my $processId  = shift;
    my $XML     = FFENCODERD_FAIL;
    
    eval{
        my $xml = XMLin($ffencoderd::XML_FILE,ForceArray => 1,KeepRoot => 1,ForceContent => 1);
       
        foreach(@{$xml->{ffencoderd}->[0]->{video}}){
            if($_->{source} eq $processId){ 
			$XML=<<_XML_;
			<?xml version="1.0"?>
			    <video source="$_->{source}" ID="$_->{ID}">
			    <description>
			        $_->{description}->[0]->{content}
			    </description>
			    <size>
			        $_->{size}->[0]->{content}
			    </size>
			    <format>
			        $_->{format}->[0]->{content}
			    </format>
			    <filename>
			        $_->{filename}->[0]->{content}
			    </filename>
			</video>
_XML_
				
            }
        }
    };print $@ if($@);
    
    return $XML;
}

=head2 L<getList>

Returns an xml formatted response with a list with uid of ended encoding processes 

=over 1

=item B<getList>

=over 2
 
=item B<Return>

string : An xml string with a list of processes listed by uid

=back

=back

=begin WSDL

 _RETURN $string An xml string with a list of processes listed by uid

=end WSDL

=cut

## @method string getList()
# Returns an xml formatted response with a list with uid of ended encoding processes
# @return string An xml string with a list of processes listed by uid
sub getList{
    
    my $XML = "<?xml version=\"1.0\"?>\n";
       $XML.= "<Processes>\n";
        
    eval{
       
          
        my $xml = XMLin($ffencoderd::XML_FILE,ForceArray => 1 , KeepRoot => 1);
        
        foreach(@{$xml->{ffencoderd}->[0]->{video}}){
            $XML.="<ProcID>$_->{source}</ProcID>\n";
        }
            
    };
    
        $XML.="</Processes>";
        return $XML; 
}

=head2 L<addProcess>

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

=begin WSDL

 _IN process $ffencoderd::Process An object with the project definition
 _RETURN $string Returns a constant value FFENCODERD_SUCCESS or FFENCODERD_PROBLEM

=end WSDL

=cut

## @method string addProcess(ffencoderd::Process process)
# @param ffencoderd::Process $process A process definition
# @return string Constant inidicating the result of the operation
sub addProcess {
	my $self = shift;
	my $process = shift;
	if($ffencoderd::queue->createProcess($process)){
		#Just return a status so the client knows everything went right
		return FFENCODERD_SUCCESS;
	}
	return FFENCODERD_PROBLEM;
}

=head2 L<version>

Returns the API version

=over 1

=item B<version>

=over 2
 
=item B<Return>

string : A string with the API's version

=back

=back

=begin WSDL

 _RETURN $string The API's version

=end WSDL

=cut

## @method string version()
# @return string Version of the ffencoderd API
sub version {
	return $ffencoderd::VERSION;
}
1;