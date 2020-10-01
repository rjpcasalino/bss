#!/usr/bin/env perl

use v5.10;

use lib './lib';
use IO::Socket;
use Web;

my $port = shift || 1987;
my $socket = IO::Socket::INET->new( LocalPort => $port,
				    Listen => SOMAXCONN,
			    	    Reuse => 1 )
			    	    or die "Can't create listen socket: $!";

say "Started local web server on $port!";
while (my $c = $socket->accept) {
	handle_connection($c);
	close $c;
}
close $socket;
