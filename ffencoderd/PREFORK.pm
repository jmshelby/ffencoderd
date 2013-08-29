## @file
# Implements a hack to SOAP::HTTP::Daemon so it can accept large files attached in a POST request

## @class 
# This class herits from SOAP::HTTP::Daemon creating a prefork http server accepting a large number of requests
# and large files attached to POST requests.
# The prefork is done through the spawnChildren and keepTicking functions, the server can serve many requests per child 
# using all the same port.
package ffencoderd::HTTP::PREFORK;
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
# @version $Id: PREFORK.pm,v 1.6 2008/05/13 02:28:13 makoki Exp $
# @author $Author: makoki $
##  
use POSIX;
use HTTP::Response;
use HTTP::Headers;
use HTTP::Status;
use Pod::Xhtml;
use Pod::WSDL;
use HTML::Template;
require SOAP::Transport::HTTP
	or die "SOAP::Transport::HTTP needed for executing ffencoderd";
use SOAP::Transport::HTTP;
use ffencoderd::Service;

# Add different Content-types, this way it's defined in HTTP response
use LWP::MediaTypes qw(add_type);
add_type("text/html" => qw(html));
add_type("text/xml" => qw(xml xsl));
add_type("text/css" => qw(css));
add_type("text/javascript" => qw(js));
add_type("video/x-flv" => qw(flv));
add_type("application/x-shockwave-flash" => qw(swf));

use constant MAX_CONTENT_LENGTH => 10000000;
use constant MAX_FILE_UPLOAD_LENGTH => (1024**2)*600;
use constant CRLF => "\r\n";

# spawnChildren - initial process to spawn the right number of children
## @var totalChildren
# Default value 10
my $totalChildren = 10;
my $children = 0;
my $childLifetime = 100;			# Let each child serve up to this many requests
my %children;							# Store pids of children
my $daemon;
my $host;
my $port;
my $DATADIR;
my $THUMBNAILDIR;
my $STATICDIR;
my $UPLOADDIR;
my %encoding_processes;
my $running = 0; # parent running?
my @mountPoints;
## @fn void spawnChildren()
# Create $totalChildren processes
sub spawnChildren {
	for (1..$totalChildren) {
		&newChild();
	}
}

## @fn string _guid()
# guid : create a unique identifier backportable
# @return string Unique identifier string
sub _guid {

	my $uuid_str;
	eval {
		require Data::UUID;
		my $ug = new Data::UUID;
		$uuid_str = $ug->create_str;
	};
	$uuid_str =~ s/-//gi;
	return $uuid_str;
}
## @fn HTTP::Response errorPage($type,$msg)
# Generates a error page returning a response object directly
# @param Integer $type Error type number
# @param String $msg Error message string
# @return HTTP::Response
sub errorPage{
	my $header = HTTP::Headers->new;
 	$header->header(Server => "ffencoderd v".$ffencoderd::VERSION);
	my $type = $_[1];
	my $msg = $_[2];
	my $template = HTML::Template->new( filename => 'error.tmpl',
	                                       path => [ $ffencoderd::BASEDIR.'/data/templates']);
	$template->param(ERROR_TITLE => "ERROR $type");
	$template->param(ERROR_MSG => $msg);
	$template->param(COPY_MSG => "v".$ffencoderd::VERSION . " author ".$ffencoderd::AUTHOR);
	$template->param(BASE_URL => "http://".$host.":".$port);
 	$header->header(Content_Type => 'text/html');
	my $f = HTTP::Response->new($type,$msg,$header,$template->output());
	return $f;
}
## @fn HTTP::Response mainPage()
# Main page
# @return HTTP::Response
sub mainPage{
      	my $parsertoo = new Pod::Xhtml( StringMode => 1 , FragmentOnly => 1);
        $parsertoo->parse_from_file( $ffencoderd::BASEDIR.'/ffencoderd/Service.pm');
        my $podxhtml = $parsertoo->asString;
        $parsertoo->parse_from_file( $ffencoderd::BASEDIR.'/ffencoderd.pl');
        my $docxhtml = $parsertoo->asString;
		my $header = HTTP::Headers->new;
 		$header->header(Content_Type => 'text/html');
 		$header->header(Server => "ffencoderd v".$ffencoderd::VERSION);
 		 my $url = "http://".$host.":".$port; 
 		 my $template = HTML::Template->new( filename => 'main.tmpl',global_vars => 1,
                                       path => [ $ffencoderd::BASEDIR.'/data/templates']);
		 $template->param(SERVICES => $podxhtml);
		 $template->param(DOCUMENTATION => $docxhtml);
		 $template->param(SHOW_NEWS => $ffencoderd::SHOW_NEWS);
		 $template->param(WSDL_URL => $url."/?wsdl");
		 $template->param(COPY_MSG => "v".$ffencoderd::VERSION . " author ".$ffencoderd::AUTHOR);

		 $template->param(MOUNTPOINTS => @mountPoints);
		 $template->param(BASE_URL => $url);
		 $template->param(UPLOAD_URL => $url."/upload");
		 $template->param(SOAP_URL => $url."/soap");
		 
      	 my $f = HTTP::Response->new( RC_OK, "", $header,$template->output() );
      	 return $f;
}
## @fn HTTP::Response exformPage()
# Form example page
# @return HTTP::Response
sub exformPage{
	    		
		 my $header = HTTP::Headers->new;
 		$header->header(Server => "ffencoderd v".$ffencoderd::VERSION);
 		 $header->header(Content_Type => 'text/html');
 		 my $url = "http://".$host.":".$port; 
 		 my $template = HTML::Template->new( filename => 'form.tmpl',
                                       path => [ $ffencoderd::BASEDIR.'/data/templates']);
		 $template->param(COPY_MSG => "v".$ffencoderd::VERSION . " author ".$ffencoderd::AUTHOR);
		 $template->param(POST_URL => $url."/upload");
		 $template->param(POST_MSG => "");
		 
      	 my $f2 = HTTP::Response->new( RC_OK, "", $header,$template->output() );
      	 return $f2
}
## @fn HTTP::Response fileUploadResponsePage($filename,$length)
# XML upload succesful page
# @param string $filename Final file name for the uploaded file in the server
# @param string $length String with the number of bytes as in the server filesystem
# @return HTTP::Response
sub fileUploadResponsePage{
	 	my $filename = shift;
	 	my $length = shift;
		my $doc  = XML::DOM::Document->new;
		my $body = $doc->createElement('upload');
		
		my $xml_stats = $doc->createElement('data');
		$xml_stats->setAttribute( 'source',$filename );
		$xml_stats->setAttribute( 'size', $length);
		$body->appendChild($xml_stats);
		my $header = HTTP::Headers->new;
 		$header->header(Server => "ffencoderd v".$ffencoderd::VERSION);
 		$header->header(Content_Type => 'text/xml');
		my $f = HTTP::Response->new(RC_OK,"",$header,$body->toString);
		$doc->dispose;
		return $f;
}
## @fn HTTP::Response statsPage()
# XML stats document page
# @return HTTP::Response
sub statsPage{
	my $doc  = XML::DOM::Document->new;
	my $body = $doc->createElement('stats');
		
	# Create some comments on XML
	my $cdoc = $doc->createComment('overallruntime: total daemon running time');
	$body->appendChild($cdoc);
	$cdoc = $doc->createComment('running: concurrent encoding processes running');
	$body->appendChild($cdoc);
	$cdoc = $doc->createComment('runtime: total encoding process run time');
	$body->appendChild($cdoc);
	$cdoc = $doc->createComment('total: total encoding processes since init');
	$body->appendChild($cdoc);
	
	my $xml_stats = $doc->createElement('data');
	$xml_stats->setAttribute( 'overallruntime',
			(time - ffencoderd::START_TIME) );
	my $stats = $ffencoderd::encoder->getStats() || "nodata";
	my ($running,$total,$timeproc) = split(";",$stats);
	my $st = $ffencoderd::encoder->getNumberOfProcesses() || "nodata";
	$xml_stats->setAttribute( 'running', $running);
	$xml_stats->setAttribute( 'runtime', $timeproc);
	$xml_stats->setAttribute( 'total', $total);
	$body->appendChild($xml_stats);
	my $header = HTTP::Headers->new;
 	$header->header(Server => "ffencoderd v".$ffencoderd::VERSION);
 	$header->header(Content_Type => 'text/xml');
	my $f = HTTP::Response->new(RC_OK,"",$header,$body->toString);
	$doc->dispose;
	return $f;
}
## @fn HTTP::Response newsFilePage()
# Fetches and return as a HTTP::Response object the news from main site to show them on main page
# @return HTTP::Response
sub newsFilePage{
	if($ffencoderd::SHOW_NEWS){
		my $content;
		my $update_file = 1;
		if(-e "$STATICDIR/news.xml"){
			my $last_modified =(stat("$STATICDIR/news.xml"))[9];
			if($last_modified > (time - (3600*24))){
				$update_file = 0;
			}
		}
		if($update_file){
			eval{
	 				my $news_request = HTTP::Request->new(GET => 'http://sourceforge.net/export/rss2_projnews.php?group_id=218142');
	 				my $ua = LWP::UserAgent->new;
	 				my $news_response = $ua->request($news_request);
	 				$content = $news_response->content;
			} or return errorPage(RC_NOT_FOUND,"Couldn't fetch news file!!! $!");
			if(open(NFH,">","$STATICDIR/news.xml")){
				print NFH $content;
				close NFH;
			}
			else{
				return errorPage(RC_NOT_FOUND,"Couldn't fetch news file!!! $!");
			}
		}
		else{
			my @b;
			if(open(NFH,"<","$STATICDIR/news.xml")){
				@b = <NFH>;
				close NFH;
				$content = "@b";
			}
			else{
				return errorPage(RC_NOT_FOUND,"Couldn't fetch news file $!");
			}
		}
		if($content){
			my $header = HTTP::Headers->new;
 			$header->header(Server => "ffencoderd v".$ffencoderd::VERSION);
 			$header->header(Content_Type => 'text/xml');
			my $f = HTTP::Response->new(RC_OK,"",$header,$content);
	   		return $f;
		}
	}
	my $r = errorPage(RC_NOT_FOUND,"News option is not activated. Set show.news=true in the config file to get this file.");
	return $r;
}
## @fn HTTP::Response procsPage()
# XML processes document page
# @return HTTP::Response
sub procsPage{
	
	my $parser = new XML::DOM::Parser;
	$doc = $parser->parsefile("$self->{PROCESSDIR}/$file");
	if(! $doc){
		return 0;
	}
	my $doc  = XML::DOM::Document->new;
	my $body = $doc->createElement('stats');
		
	my $xml_stats = $doc->createElement('data');
	$xml_stats->setAttribute( 'timestamp',
			(time - ffencoderd::START_TIME) );
	my $st = $ffencoderd::encoder->getNumberOfProcesses()||"nodata";
	$xml_stats->setAttribute( 'total', $st);
	$body->appendChild($xml_stats);
	my $header = HTTP::Headers->new;
 	$header->header(Server => "ffencoderd v".$ffencoderd::VERSION);
 	$header->header(Content_Type => 'text/xml');
	my $f = HTTP::Response->new(RC_OK,"",$header,$body->toString);
	$doc->dispose;
	return $f;
	
}
## @fn HTTP::Response wsdlPage()
# Returns WSDL service defintion
# @return HTTP::Response
sub wsdlPage{
	
	my $header = HTTP::Headers->new;
    my $pod = Pod::WSDL->new(
      				source => $ffencoderd::BASEDIR.'/ffencoderd/Service.pm', 
        			location => "http://".$host.":".$port."/soap",
       				pretty => 0,
       				withDocumentation => 0) or die "Couldn't create WSDL $!";
 	$header->header(Content_Type => 'text/xml'); 
 	$header->header(Server => "ffencoderd v".$ffencoderd::VERSION);
 	
	my $f = HTTP::Response->new( RC_OK, "", $header,$pod->WSDL);
	return $f;
}
## @fn void keepTicking()
# keepTicking - a never ending loop for the parent process which just monitors
# dying children and generates new ones
sub keepTicking {
	while ( 1 ) {
		sleep;
	  	for (my $i = $children; $i < $totalChildren; $i++ ) {
			&newChild() if($running);			
		}
	};
}
## @fn void newChild()
# a forked child process that parses the different accessible paths and SOAP requests. This function does all the work for
# the server, parsing the requests done to them and serving the response for these requests.
sub newChild {
  	CLIENT:
	my $pid;
	my $sigset = POSIX::SigSet->new(SIGINT);				# Delay any interruptions!
   sigprocmask(SIG_BLOCK, $sigset) or die "Can't block SIGINT for fork: $!";
   die "Cannot fork child: $!\n" unless defined ($pid = fork);
	if ($pid) {
		$children{$pid} = 1;										# Report a child is using this pid
		$children++;												# Increase the child count
		#warn "forked new child, we now have $children children";
		return;														# Head back to wait around
	}
	
	my $i = 0;
	while ($i < $childLifetime) {				# Loop for $childLifetime requests
		$i++;
		my $c = $daemon->accept or last;							# Accept a request, or if timed out.. die early
		$c->autoflush(1);
     	my $r = $c->get_request(1) or last;					# Get the request headers only, if multipart or chunked see later

		# Insert your own logic code here. The request is in $r

	  my $req = $r->uri || "";
	  my $useragent = $r->header('User-Agent') || "";
	  my $encoding = $r->header('Content-Encoding') || "";
	  my $content_type = $r->header('Content-Type') || "";
      my $method = $r->method || "GET";
      my $large_file_request = 0;
      my $length = $r->content_length || 0;
      my $peerhost = $c->peerhost || "?";
      #
      # Log Request
      #
      ffencoderd::appendfile( $ffencoderd::LOG,"$peerhost - $method $req -- $useragent - $length b" );
      ##
      # Look up if a buffer for reading is needed, this is done to upload large files to the server.
      # Uses MAX_FILE_UPLOAD_LENGTH
      ##
      if($req =~ m/^\/upload/i){
      	#
      	# Show upload form if used method is GET
      	#
      	if($method eq "GET"){     	
			 $c->send_response(exformPage());
      	}
      	#
      	# Save the file if Content-type is multipart (and POST method)
      	#
      	elsif($content_type =~ m/^multipart/i){
	      	 if($length > MAX_FILE_UPLOAD_LENGTH){
	      	 	
				 	$c->send_response(errorPage(RC_INTERNAL_SERVER_ERROR,"Request too large")); 
				 	$c->close;
				 	last;
	      	 }
      		my $boundary_pos = index($content_type,"boundary="); # get boundary from content-type header
      		my $boundary = substr($content_type,$boundary_pos+9); # get boundary definition
      		my $CRLF = CRLF||"\r\n"; # set newline
      		my $buf_len = $length; # set total length of uploaded file from Content-length header
      		my $_gu = _guid(); # Get a random filename to save to 
      		my $temp_file_name = "$UPLOADDIR/$_gu.tmp";
      		my $real_filename = "Noname";
     		my $buf; # buffer where all stuff will get in and written
     		my $file_extenstion = "tmp";
      		open(FH,">$temp_file_name");
      		binmode(FH);
		    while ($buf_len > 0){    
			    if ($buf=$c->read_buffer)  {
			        # Anything that get_request read, but didn't use, was
			        # left in the read buffer. The call to sysread() should
			        # NOT be made until we've emptied this source, first.
			        $buf_len-= length($buf);
			        $c->read_buffer(''); # Clear it, now that it's read
			    } else {
			        $buf_len -= sysread($c, $buf,($buf_len < 2048) ? $buf_len : 2048);
			    }
			    $buf =~ s/--${boundary}${CRLF}//gi; # supress all RFC stuff
			    $buf =~ s/[${CRLF}]*--${boundary}--${CRLF}//gi; # supress all RFC stuff
			    
     			# Obtain filename if is defined
			    if($buf =~ m/Content.*\s*.*[;]?\s*(name=.*)\s*[;]?\s+(filename=.*)\s*[;]?\s*[${CRLF}]*/i){
			    	my $name;
			    	my $junk;
			    	($junk, $name) = split /"/, $1;
			    	($junk, $real_filename) = split /"/, $2;
			    	$real_filename = $real_filename||$name;
			    	$real_filename =~ s/\.\.//;
			    	$real_filename =~ s/://;
			    	$real_filename =~ s/\///;
			    	if($real_filename =~ m/.*\.(.*)$/i){
			    		$file_extension = $+;
			    	} 
			    }
			    $buf =~ s/Content.*[${CRLF}]*//gi; # supress all RFC stuff
			    syswrite FH, $buf;   
		    }
		  	close(FH);
		  	# Try to rename the file as posted or replace with $guid.$file_extension
		  	if(! -e "$UPLOADDIR/$real_filename" ){
		  		rename($temp_file_name,"$UPLOADDIR/$real_filename");		  		
		  	}else{
		  		$real_filename = "$_gu.$file_extension";
		  		rename($temp_file_name,"$UPLOADDIR/$real_filename");
		  	}
     		ffencoderd::appendfile( $ffencoderd::LOG,"Uploaded $real_filename ($length b)" );
		     		
			#Ok send XML response
		 	$c->send_response(fileUploadResponsePage($real_filename,$length)); 
      	}
      	else{
			 	$c->send_response(errorPage(RC_NOT_IMPLEMENTED,"Not implemented"));
      	}
      	
      }
      #
      # Normal request, no use for a buffer using content()
      # Uses MAX_CONTENT_LENGTH
      #
      else{
      	
      	 if($length > MAX_CONTENT_LENGTH){
      	 	
			 	$c->send_response(errorPage(RC_INTERNAL_SERVER_ERROR,"Request too large")); 
			 	$c->close;
			 	last;
      	 }
      	 #
      	 # Read content from connection
      	 #
     	  my $cont;
		  my $buf;
      	  my $buf_len = $length;
		    while ($buf_len > 0){    
			    if ($buf=$c->read_buffer)  {
			        # Anything that get_request read, but didn't use, was
			        # left in the read buffer. The call to sysread() should
			        # NOT be made until we've emptied this source, first.
			        $buf_len-= length($buf);
			        $c->read_buffer(''); # Clear it, now that it's read
			    } else {
			        $buf_len -= sysread($c, $buf,($buf_len < 2048) ? $buf_len : 2048);
			    }
			    $cont .= $buf;     
		    }
		  $r->content($cont);
		  
		  #
		  # Serving request for content
		  #/[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}/mountpoint
	      if($req =~ m/^\/([a-f0-9]{8}[a-f0-9]{4}[a-f0-9]{4}[a-f0-9]{4}[a-f0-9]{12})/i){
	      	my $guid = $1 || undef;
	      	
	    	if(!defined $guid){
	    		$c->send_response(errorPage(RC_NOT_FOUND,"File not found"));
	    	}
	    	my $extension = undef;
	    	my $requestedProfile = undef;
	    	use Data::Dumper;
	    	#search a corresponding mountpoint
	    	my $mntpts = $mountPoints[0];
	    	my $mountpoint = undef;
	    	for my $data (@$mntpts){
	    		my $name = $data->{name};
	    		$mountpoint = $data->{mountpoint};
	    		my $type = $data->{type};
	    		if($req =~ m/[a-f0-9]{8}[a-f0-9]{4}[a-f0-9]{4}[a-f0-9]{4}[a-f0-9]{12}\/(.*)$/i && $mountpoint eq $1){
					$requestedProfile = $name;
					$extension = $data->{ext};
				 	last;
				}
	    	}
	    	if(!$requestedProfile){
			 	$c->send_response(errorPage(RC_NOT_FOUND,"Didn't found a suitable profile for this path")); 
	    	}
			#verify the resource exists in the server dir
	 		if(-e "$DATADIR/$guid.$extension"){
	  			$c->send_file_response("$DATADIR/$guid.$extension");
			}
			else{
			 	$c->send_response(errorPage(RC_NOT_FOUND,"File not found"));  
			}
			
	      }
	      elsif($req =~ m/^\/static/i){
	      	$req =~ s/^\/static\///g;
	      	$req =~ s/\.\.//g;
	      	$c->send_response(errorPage(RC_NOT_FOUND,"File not found")) if($req eq "" || $req eq "/");
	      	my $requested_static_file = "$STATICDIR/$req";
	      	if(-e "$requested_static_file"){
	  			$c->send_file_response("$requested_static_file");     		
	      	}
	      	else{
			 	$c->send_response(errorPage(RC_NOT_FOUND,"File not found"));      		
	      	}
	      }
	      elsif($req =~ m/^\/news\.xml/i){
			 	$c->send_response(newsFilePage());    
			 	
	      }
	      elsif($req =~ m/^\/stats\.xml/i){
			 	$c->send_response(statsPage());    
			 	
	      }
	      elsif($req =~ m/^\/processes\.xml/i){
	 			my $header = HTTP::Headers->new;
	 			$header->header(Content_Type => 'text/xml');
	  			$c->send_file_response("$ffencoderd::XML_FILE");  
			 	
	      }
	      #
	      # Serving WSDL
	      elsif($req =~ m/\?wsdl$/i){
			  $c->send_response(wsdlPage());
	      	
	      }
	      ##
	      # Serving home page
	      ##
	      elsif($req =~ m/^\/$/i){
			 $c->send_response(mainPage());
	      }
	      #
	      # Serving SOAP
	      #
	      elsif($req =~ m/^\/soap/i){
	      	$req =~ s/://i;
	      	$daemon->request($r);
	      	$daemon->SOAP::Transport::HTTP::Server::handle;
	      	$c->send_response($daemon->response);
	      }
	      else{
			 $c->send_response(errorPage(RC_NOT_FOUND,"File not found"));
	      }
		}
      $c->close;
	}
	
	#warn "child terminated after $i requests";
	exit;
}
## @fn void REAPER()
# a reaper of dead children/zombies with exit codes to spare
sub REAPER {    
	                       
	my $stiff;
	while (($stiff = waitpid(-1, &WNOHANG)) > 0) {
		#warn ("child $stiff terminated -- status $?");
		$children--;
		#$children{$stiff};
		&newChild() if($running); # Restart child unless KILL signal used
	}
	$SIG{CHLD} = \&REAPER;
} 

## @fn void init($host,$port,$totalChildren,$childLifetime,$DATADIR,$UPLOADDIR)
# Start HTTP server, this will start $totalChildren children of this process
# @param string $host Host IP address, it will serve only this address
# @param int $port Port represented as integer where to run the http server
# @param int $totalChildren Max number of spawned children processes of the http server (prefork)
# @param int $childLifetime Max number of iterations to run each child process before dying
# @param string $DATADIR Absolute path to dir where static data is found
# @param string $UPLOADDIR Absolute path where user uploaded files are
sub init {
	POSIX::setsid();
	close (STDOUT);												# Close file handles to detach from any terminals
	close (STDIN);
	close (STDERR);
	#get parameters
	($host,$port,$totalChildren,$childLifetime,$DATADIR,$UPLOADDIR) = @_;
	$STATICDIR = $ffencoderd::BASEDIR."/data/www";
	@mountPoints = $ffencoderd::encoder->{PROFILES}->getMountPoints();
	$0 = $ffencoderd::PROGRAM."-http";
	$daemon = SOAP::Transport::HTTP::Daemon
  	 -> new (LocalAddr => $host, LocalPort => $port, ReuseAddr => 1, Timeout => 80)
 	 -> dispatch_to("Service") 
	;
	my $url = $daemon->url;
	$running = 1;
	ffencoderd::appendfile( $ffencoderd::LOG,"Starting $0 $url spawning $totalChildren children (max. $childLifetime requests per children)" );
	$SIG{CHLD} = \&REAPER;
	&spawnChildren;
	&keepTicking;
	exit;
}
## @fn void DESTROY()
# Destroy all uneeded data after ending
sub DESTROY{
	$running = 0;
	ffencoderd::appendfile( $ffencoderd::LOG,"Finalizing ffencoderd-http" );
}
## @fn string product_tokens()
#Overload product_tokens from LWP
sub product_tokens{
	return "$ffencoderd::PROGRAM $ffencoderd::VERSION";
}
1;