# Core Web server rounties from:
# Chapter 15 of "Network Programming with Perl"
# Copyright Lincoln D. Stein, 2000 

package Web;

use vars '@ISA', '@EXPORT';
require Exporter;

@ISA = 'Exporter';
@EXPORT = qw(handle_connection docroot);

# hacky but whatever
my $DOCUMENT_ROOT = $ENV{'BSS_DOCROOT'};
my $CRLF = "\015\012";

sub handle_connection {
	my $c = shift; #socket
	my ($fh, $type, $length, $url, $method);
	local $/ = "$CRLF$CRLF"; # set end of line character
	my $request = <$c>; # read request header

	return invalid_request($c)
	 unless ($method, $url) = $request =~ m!^(GET|HEAD) (/.*) HTTP/1\.[01]!;
	return not_found($c) unless ($fh, $type, $length) = lookup_file($url);
	return redirect($c, "$url/") if $type eq 'directory';

	# print the header
	print $c "HTTP/1.0 200 OK$CRLF";
	print $c "Content-length: $length$CRLF";
	print $c "Content-type: $type$CRLF";
	print $c $CRLF;

	return unless $method eq 'GET';

	# print the content
	#STDIN->fdopen($c, "<", "/dev/null") or die "Can't reopen STDIN: $!";
	#STDOUT->fdopen($c, ">", "/dev/null") or die "Can't reopen STDIN: $!";
	#STDERR->fdopen($c, ">&", STDOUT) or die "Can't reopen STDIN: $!";
	my $buffer;
	while ( read($fh, $buffer, 1024) ) {
		print $c $buffer;
	}
	close $fh;
}

sub lookup_file {
	my $url = shift;
	my $path = $DOCUMENT_ROOT . $url; # turn into path
	$path =~ s/\?.*$//; # ger rid of query
	$path =~ s/\#.*$//; # get rid of fragment
	$path .= 'index.html' if $url =~ m!/$!; # get index.html if path ends in /
	return if $path =~ m!/\.\\./!; # don't allow relative paths (..)
	return (undef, 'directory', undef) if -d $path; # oops! a directory
	my $type = 'text/plain'; # default MIME type
	$type = 'text/html' if $path =~ /\.html?$/i; # HTML file?
	$type = 'text/gif' if $path =~ /\.gif?$/i; # gif file?
	$type = 'text/jpeg' if $path =~ /\.jpe?g$/i; # jpg file?
	return unless my $length = (stat(_))[7]; # file size
	return unless my $fh = IO::File->new($path, "<"); # try to open file
}

sub redirect {
	my ($c, $url) = @_;
	my $host = $c->sockhost;
	my $port = $c->sockport;
	my $moved_to = "http://$host:$port$url";
	print $c "HTTP/1.0 301 Moved permanently$CRLF";
	print $c "Location: $moved_to$CRLF";
	print $c "Content-type: text/html$CRLF$CRLF";
	print $c <<END;
<html>
<head><title>301 Moved</title>
</head>
<body>
<h1>MOVED</h1>
<p> The requested document has moved <a href="$moved_to">here</a>.<.p>
</body>
</html>
END
}

sub invalid_request {
	my $c = shift;
	print $c "HTTP/1.0 400 Bad Request$CRLF";
	print $c "Content-type: text/html$CRLF$CRLF";
	print $c <<END;
<html>
<head><title>400 Bad Request</title>
</head>
<body><h1>Bad Request</h1>
</body>
</html>
END
}

sub not_found {
	my $c = shift;
	print $c "HTTP/1.0 404 Not Found$CRLF";
	print $c "Content-type: text/html$CRLF$CRLF";
	print $c <<END;
<html>
<head><title>404 Not Found</title>
</head>
<body>
<h1>404 Not Found</h1>
</body>
</html>
END
}

sub docroot {
	$DOCUMENT_ROOT = shift if @_;
	return $DOCUMENT_ROOT;
}

1; # perl programs end this way :-) 
