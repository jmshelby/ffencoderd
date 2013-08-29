## @file 
#Manages the encoding processes queue

## @class 
# Implementation of a queue, mainly scanning a directory looking for xml files with encoding processes definition
# also publishes some methods to read these enc. procs definitions.
package ffencoderd::Queue;
#
#   ___    ___                                 __                   __     
# /'___\ /'___\                               /\ \                 /\ \    
#/\ \__//\ \__/   __    ___     ___    ___    \_\ \     __   _ __  \_\ \   
#\ \ ,__\ \ ,__\/'__`\/' _ `\  /'___\ / __`\  /'_` \  /'__`\/\`'__\/'_` \  
# \ \ \_/\ \ \_/\  __//\ \/\ \/\ \__//\ \L\ \/\ \L\ \/\  __/\ \ \//\ \L\ \ 
#  \ \_\  \ \_\\ \____\ \_\ \_\ \____\ \____/\ \___,_\ \____\\ \_\\ \___,_\
#   \/_/   \/_/ \/____/\/_/\/_/\/____/\/___/  \/__,_ /\/____/ \/_/ \/__,_ /
# ffencoderd $Revision: 1.7 $
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
# @version $Id: Queue.pm,v 1.7 2008/05/13 02:28:13 makoki Exp $
# @author $Author: makoki $
##
use POSIX;
use XML::DOM;
use File::Basename;

## @cmethod ffencoderd::Queue new(%params)
# @param hash %params with three possible keys
# - queueDir String with the path where enc. procs files reside
# - xmlFile String with the path of the xml file where enc. processes are stored once are finished and definition is removed
# - dtd String with the path where a public dtd file is accessible (optional) 
sub new{
	my ($class) = shift;
	my (%params) = @_;
	$self = {};
	$self->{PROCESSDIR} = $params{"queueDir"};
	$self->{XMLFILE} = $params{"xmlFile"};
	$self->{DTD} = $params{"dtd"};
	bless $self,$class;
	return $self;
}
## @method array update()
# Reads the processes files directory and returns an array with files that match the conditions
# @return Array an array with new files in process dir
sub update{
	my $self = shift;
	if(-e "$self->{PROCESSDIR}"){
	opendir( PROCESS_DIR, "$self->{PROCESSDIR}" ) or die "No process dir defined";
	my @processes_files = grep {
		   /.xml$/                             # Archivos *.xml
		  && -f "$self->{PROCESSDIR}/$_"    # and is a file
		  && -r "$self->{PROCESSDIR}/$_"
	} readdir(PROCESS_DIR);
	
	closedir(PROCESS_DIR);
	return @processes_files;
	}
	return 0;
}
## @method array readProcessFile($file)
# Reads a encoding session defintion file and returns an array of hashes with its information
# @param String $file Path to file with enc. session definition
# @return array Array of hashes with information of the enc. session definition, each element of the array will have at least two keys id and profile, alternatively may have more that define the parameters used
sub readProcessFile {
	my $self = shift;
	my $doc;
	my $file = shift;
	#my $content;
	if(-e "$self->{PROCESSDIR}/$file"){
		my $parser = new XML::DOM::Parser;
		$doc = $parser->parsefile("$self->{PROCESSDIR}/$file");
		if(! $doc){
			return 0;
		}
		my $processes = $doc->getElementsByTagName('process');
		my $n = $processes->getLength();
		my @processes_array = ();
		
		#read all processes
		for(my $i=0;$i <$n ; $i++){
			my %process_data = undef;
			my $process = $processes->item($i);
			my $process_attr = $process->getAttributes();
			my $procid = $process_attr->getNamedItem("id");
			$process_data{"id"} = $procid->getValue;
			$process_data{"profile"} = "default";
			if($process_attr->getNamedItem("profile")){
				$process_data{"profile"} = $process_attr->getNamedItem("profile")->getValue;
			}
			
			if($process->hasChildNodes()){
				#read process parameters
				for my $parameter ($process->getChildNodes){
					
					my $tag_name = $parameter->getTagName() or next;
					# get file by tag Name
					if(lc($tag_name) eq "file"){
						$process_data{$tag_name} = $parameter->getFirstChild->toString();
						next;
					}
					#get parameters
					elsif(lc($tag_name) eq "parameter"){
						my $param_name = $parameter->getAttribute("name") || undef;
						if($parameter->getFirstChild && defined($param_name)){
							$process_data{$param_name} = $parameter->getFirstChild->toString();
							
						}
					}
				}
			}
			if(%process_data){
				push(@processes_array,\%process_data);
			}
		}
		return @processes_array;
	}
	return 0;
}
## @method int createProcess(ffencoderd::Process process)
# Create a encoding session defintion file with parameters given
# @param ffencoderd::Process $process Encoding session definition, contains next keys
# - id User defined identifier
# - profile Profile name to use for encoding in this session
# - file Server's filesystem filename
# - parameters A hash with key value pairs to define encoding parameters that must match those in the profile
# @return Boolean
sub createProcess{
	my $self = shift;
	my $parameters = shift;
	
	my $file = File::Basename::basename($parameters->{file});
	if(! $file){
		ffencoderd::appendfile($ffencoderd::LOG,"No file defined ". $file);
		return 0;
	}
	my $id = $parameters->{id};
	my $command_parameters = $parameters->{parameters};
	$doc  = XML::DOM::Document->new or die "Cannot create new XML document";
	$body = $doc->createElement('ffencoderd');
	my $filename = ffencoderd::Encoder::_guid().".xml";#unique name in process dir
	# probamos de escribir el xml
	if ( open( XML_FILE, ">",$self->{PROCESSDIR}."/$filename") ) {
		flock(XML_FILE,LOCK_EX);
		my $xml_process = $doc->createElement('process');
		$xml_process->setAttribute( 'id',"$id" );
		$xml_process->setAttribute( 'profile',"$parameters->{profile}" );
		my $xml_file = $doc->createElement('file');
		$xml_file->appendChild( $doc->createTextNode($file) );
		$xml_process->appendChild($xml_file);
		while ( my ($key, $value) = each(%$command_parameters) ) {
			if($value){
				my $xml_parameter = $doc->createElement('parameter');
				$xml_parameter->setAttribute( 'name',"$key" );
				if( defined($value) ){
					$xml_parameter->appendChild( $doc->createTextNode($value) );
	    		}
	    		else{
	    			warn "Can't find a value defined for parameter $key";
	    		}
				$xml_process->appendChild($xml_parameter);	
			}
    	}
		
		
		$body->appendChild($xml_process);
		my $xml_pi  = $doc->createXMLDecl('1.0');
		my $xml_dtd = $doc->createDocumentType( 'ffencoderd', "$self->{DTD}");

		print XML_FILE $xml_pi->toString;
		print XML_FILE $xml_dtd->toString;
		print XML_FILE $body->toString;

		flock(XML_FILE,LOCK_UN);
		close(XML_FILE);
		$doc->dispose;
		ffencoderd::appendfile( $ffencoderd::LOG,"New process created ($id,$file)" );
		return 1;
	}
	else{
		ffencoderd::appendfile($ffencoderd::LOG,"Problem writing process file, verify ".$parameters->{PROCESSDIR}." permissions.");
	}
	return 0;
}
## @method int append_xml(%data)
# Add an entry to the XML control file
# @param Hash $data with the following keys
# - id A user defined identifier
# - filename The original filename in the server filesystem
# - description A description for the encoded file
# - size The size in wxh of the encoded file
# - format The encoded file format
# - source The uinque identifier used to identify the resource in the server filesystem
# @return boolean
sub append_xml {
	my $self = shift;
	my $data = shift;
	my $doc;
	my $body;
	if ( -e "$self->{XMLFILE}" ) {

		my $parser = new XML::DOM::Parser;
		$doc = $parser->parsefile("$self->{XMLFILE}");
		my $node_body = $doc->getElementsByTagName('ffencoderd');
		if ( $node_body->getLength > 0 ) {
			$body = $node_body->item(0);
		}
		else {
			$body = $doc->createElement('ffencoderd');
		}
	}

	# No existe todavia archivo XML
	else {

		$doc  = XML::DOM::Document->new;
		$body = $doc->createElement('ffencoderd');
	}

	# probamos de escribir el xml
	if ( open( XML_FILE,">","$self->{XMLFILE}" ) ) {
		flock(XML_FILE,LOCK_EX);
		
		my $id			= $data->{id};
		my $source    = $data->{source};
		my $description = $data->{description};
		my $size        = $data->{size};
		my $format      = $data->{format};
		my $original_filename  = $data->{filename};

		# generamos el xml
		my $xml_video = $doc->createElement('video');
		$xml_video->setAttribute( 'source',
			"$source" );
		$xml_video->setAttribute( 'ID', $id ); #@FIX changed to capitals as asked by z3vil

		# creamos los elementos correspondientes al video
		my $xml_desc = $doc->createElement('description');
		$xml_desc->appendChild( $doc->createTextNode($description) );

		my $xml_size = $doc->createElement('size');
		$xml_size->appendChild( $doc->createTextNode($size) );

		my $xml_format = $doc->createElement('format');
		$xml_format->appendChild( $doc->createTextNode($format) );

		my $xml_filename = $doc->createElement('filename');
		$xml_filename->appendChild( $doc->createTextNode($original_filename) );

		# anadimos al elemento video
		$xml_video->appendChild($xml_desc);
		$xml_video->appendChild($xml_size);
		$xml_video->appendChild($xml_format);
		$xml_video->appendChild($xml_filename);
		$body->appendChild($xml_video);
		my $xml_pi  = $doc->createXMLDecl('1.0');
		my $xml_style = $doc->createProcessingInstruction ("xml-stylesheet", "type=\"text/xsl\" href=\"/static/style.xsl\"");
		my $xml_dtd =
		  $doc->createDocumentType( 'ffencoderd', "$self->{DTD}");

		print XML_FILE $xml_pi->toString;
		print XML_FILE $xml_style->toString;
		print XML_FILE $xml_dtd->toString;
		print XML_FILE $body->toString;

		$doc->dispose;
		flock(XML_FILE,LOCK_UN);
		close(XML_FILE);
		return 1;
	}
	ffencoderd::appendfile( $ffencoderd::LOG,"No se puede escribir en $self->{XMLFILE}" );
	return 0;
}
1;