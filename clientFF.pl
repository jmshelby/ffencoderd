#!/usr/bin/perl -w
use SOAP::Lite;
use Data::Dumper;
my $soap = SOAP::Lite
       ->proxy('http://10.0.0.27:8080/soap')
       ->uri('Service');
use ffencoderd::Process;
my $p = ffencoderd::Process->new();
$p->{file} = "ser5.mov";
$p->{id} = 21;
$p->{audiocodec} = "mp3";
my $invoca = $soap->addProcess($p);
#my $invoca = $soap->status();
if ( !$invoca->fault() ) {
   my $resultado = $invoca->result();
   print "\nEl servidor responde: $resultado \n";
}else{
   print "\nERROR:";
   print "\n\t faultcode : ".$invoca->faultcode();
   print "\n\t faultstring : ".$invoca->faultstring();
   print "\n\t faultdetail : ".$invoca->faultdetail();
print Dumper($invoca);
}

=head1
# Basic pre-forking HTTP daemon - version 2
# By Peter Cooper - http://www.petercooper.co.uk/
#
# Inspiration and various rehashed snippetsof code from the Perl 
# cfdaemon engine - http://perl-cfd.sourceforge.net/
#
# You can switch out HTTP::Daemon and make it a pre-forking daemonized 
# 'anything' if you wish..

use HTTP::Daemon;
use HTTP::Status;
use CGI;
use POSIX;

my $totalChildren = 15;				# Number of listening children to keep alive
my $childLifetime = 10;			# Let each child serve up to this many requests
my $logFile = "/tmp/daemon.log";	# Log requests and errors to this file
my %children;							# Store pids of children
my $children = 0;						# Store number of currently active children

&daemonize;								# Daemonize the parent

my $d = HTTP::Daemon->new( LocalPort => 1981, LocalAddr => '127.0.0.1', Reuse => 1, Timeout => 180 ) || die "Cannot create socket: $!\n";

warn ("master is ", $d->url);

&spawnChildren;
&keepTicking;
exit;


# spawnChildren - initial process to spawn the right number of children

sub spawnChildren {
	for (1..$totalChildren) {
		&newChild();
	}
}


# keepTicking - a never ending loop for the parent process which just monitors
# dying children and generates new ones

sub keepTicking {
	while ( 1 ) {
		sleep;
	  	for (my $i = $children; $i < $totalChildren; $i++ ) {
		  &newChild();
		}
	};
}


# newChild - a forked child process that actually does some work

sub newChild {
	my $pid;
	my $sigset = POSIX::SigSet->new(SIGINT);				# Delay any interruptions!
   sigprocmask(SIG_BLOCK, $sigset) or die "Can't block SIGINT for fork: $!";
   die "Cannot fork child: $!\n" unless defined ($pid = fork);
	if ($pid) {
		$children{$pid} = 1;										# Report a child is using this pid
		$children++;												# Increase the child count
		warn "forked new child, we now have $children children";
		return;														# Head back to wait around
	}
	
	my $i;
	while ($i < $childLifetime) {				# Loop for $childLifetime requests
		$i++;
		my $c = $d->accept or last;							# Accept a request, or if timed out.. die early
		$c->autoflush(1);
		logMessage ("connect:". $c->peerhost . "\n");	# We've accepted a connection!
     	my $r = $c->get_request(1) or last;					# Get the request. If it fails, die early

		# Insert your own logic code here. The request is in $r
		# What we do here is check if the method is not GET, if so.. send back a 403.

		my $url = $r->url;
		$url =~ s/^\///g;

     	if ($r->method ne 'GET') { 
			$c->send_error(RC_FORBIDDEN); 
			logMessage ($c->peerhost . " made weird request\n"); 
			redo;
		}
		
		my $response = HTTP::Response->new(200);			# Put together a response
		logMessage ($c->peerhost . " " . $d->url . $url . "\n");	
		$response->content("<html><body>The daemon works! This child has served $i requests.</body></html>");
#				$response->content("document.write('OK $i<br \/>');");
		$response->header("Content-Type" => "text/html");
		$c->send_response($response);							# Send back a basic response
		
		logMessage ("disconnect:" . $c->peerhost . " - ct[$i]\n");		# Log the end of the request
      $c->close;
	}
	
	warn "child terminated after $i requests";
	exit;
}


# REAPER - a reaper of dead children/zombies with exit codes to spare

sub REAPER {                            
	my $stiff;
	while (($stiff = waitpid(-1, &WNOHANG)) > 0) {
		warn ("child $stiff terminated -- status $?");
		$children--;
		$children{$stiff};
	}
	$SIG{CHLD} = \&REAPER;
}        

# daemonize - daemonize the parent/control app

sub daemonize {
	my $pid = fork;												# Fork off the main process
	defined ($pid) or die "Cannot start daemon: $!"; 	# If no PID is defined, the daemon failed to start
	print "Parent daemon running.\n" if $pid;				# If we have a PID, the parent daemonized okay
	exit if $pid;													# Return control to the user

   # Now we're a daemonized parent process!

	POSIX::setsid();												# Become a session leader

	close (STDOUT);												# Close file handles to detach from any terminals
	close (STDIN);
	close (STDERR);

	# Set up signals we want to catch. Let's log warnings, fatal errors, and catch hangups and dying children

	$SIG{__WARN__} = sub {
			&logMessage ("NOTE! " . join(" ", @_));
	};
	
	$SIG{__DIE__} = sub { 
		&logMessage ("FATAL! " . join(" ", @_));
		exit;
	};

	$SIG{HUP} = $SIG{INT} = $SIG{TERM} = sub {			# Any sort of death trigger results in instant death of all
	  my $sig = shift;
	  $SIG{$sig} = 'IGNORE';
	  kill 'INT' => keys %children;
	  die "killed by $sig\n";
	  exit;
	};	
	
	$SIG{CHLD} = \&REAPER;
}

# logMessage - append messages to a log file. messy, but it works for now.

sub logMessage {
	my $message = shift;
	(my $sec, my $min, my $hour, my $mday, my $mon, my $year) = gmtime();
	$mon++;
	$mon = sprintf("%0.2d", $mon);
	$mday = sprintf("%0.2d", $mday);
	$hour = sprintf("%0.2d", $hour);
	$min = sprintf("%0.2d", $min);
	$sec = sprintf("%0.2d", $sec);
	$year += 1900;
	my $time = qq{$year/$mon/$mday $hour:$min:$sec};
	open (FH, ">>" . $logFile);
	print FH $time . " - " . $message;
	close (FH);
}
=cut
