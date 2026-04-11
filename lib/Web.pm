# Core Web server routines from:
# Chapter 15 of "Network Programming with Perl"
# Copyright Lincoln D. Stein, 2000 

package Web;

use parent 'Exporter';
our @EXPORT = qw(handle_connection docroot set_dev_mode);

my $DOCUMENT_ROOT = defined($ENV{'BSS_DOCROOT'}) ? $ENV{'BSS_DOCROOT'} : '_site';
my $CRLF = "\015\012";
my $DEV_MODE = 0;
my $META_FILE = '';

my %MIME_TYPES = (
	html  => 'text/html',
	htm   => 'text/html',
	css   => 'text/css',
	js    => 'application/javascript',
	json  => 'application/json',
	xml   => 'application/xml',
	gif   => 'image/gif',
	jpg   => 'image/jpeg',
	jpeg  => 'image/jpeg',
	png   => 'image/png',
	svg   => 'image/svg+xml',
	ico   => 'image/x-icon',
	webp  => 'image/webp',
	woff  => 'font/woff',
	woff2 => 'font/woff2',
	ttf   => 'font/ttf',
	otf   => 'font/otf',
	eot   => 'application/vnd.ms-fontobject',
	pdf   => 'application/pdf',
	txt   => 'text/plain',
);

sub set_dev_mode {
	$META_FILE = shift;
	$DEV_MODE = 1;
}

sub handle_connection {
	my $c = shift; #socket
	my ($fh, $type, $length, $url, $method);
	local $/ = "$CRLF$CRLF"; # set end of line character
	my $request = <$c>; # read request header

	return invalid_request($c)
	 unless ($method, $url) = $request =~ m!^(GET|HEAD) (/.*) HTTP/1\.[01]!;

	# Dev mode: serve build metadata for live reload polling
	if ($DEV_MODE && $url eq '/__bss/poll') {
		return bss_poll($c);
	}

	return not_found($c) unless ($fh, $type, $length) = lookup_file($url);
	return redirect($c, "$url/") if $type eq 'directory';

	# In dev mode, inject live reload script and stats box into HTML
	if ($DEV_MODE && $type eq 'text/html' && $method eq 'GET') {
		return serve_html_with_reload($c, $fh);
	}

	# print the header
	print $c "HTTP/1.0 200 OK$CRLF";
	print $c "Content-length: $length$CRLF";
	print $c "Content-type: $type$CRLF";
	print $c $CRLF;

	return unless $method eq 'GET';

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
	return if $path =~ m!/\.\./!; # don't allow relative paths (..)
	return (undef, 'directory', undef) if -d $path; # oops! a directory
	my ($ext) = $path =~ /\.([^.]+)$/;
	my $type = (defined $ext && $MIME_TYPES{lc $ext}) || 'application/octet-stream';
	return unless my $length = (stat($path))[7]; # file size
	return unless my $fh = IO::File->new($path, "<"); # try to open file
	return ($fh, $type, $length);
}

sub bss_poll {
	my $c = shift;
	my $json = '{}';
	if (-f $META_FILE) {
		if (open my $fh, '<', $META_FILE) {
			local $/;
			$json = <$fh>;
			close $fh;
		}
	}
	my $len = length($json);
	print $c "HTTP/1.0 200 OK$CRLF";
	print $c "Content-type: application/json$CRLF";
	print $c "Content-length: $len$CRLF";
	print $c "Cache-Control: no-cache, no-store$CRLF";
	print $c $CRLF;
	print $c $json;
}

sub serve_html_with_reload {
	my ($c, $fh) = @_;

	local $/;
	my $html = <$fh>;
	close $fh;

	my $snippet = _dev_snippet();

	# Inject before </body> if present, otherwise append
	unless ($html =~ s!(</body>)!$snippet$1!i) {
		$html .= $snippet;
	}

	my $length = length($html);
	print $c "HTTP/1.0 200 OK$CRLF";
	print $c "Content-length: $length$CRLF";
	print $c "Content-type: text/html$CRLF";
	print $c $CRLF;
	print $c $html;
}

sub _dev_snippet {
	return <<'END_SNIPPET';
<!-- bss dev mode: live reload + stats -->
<style>
#bss-dev-stats {
    position: fixed;
    bottom: 12px;
    right: 12px;
    background: #1e1e2e;
    color: #cdd6f4;
    font-family: 'SF Mono', 'Fira Code', 'Cascadia Code', monospace;
    font-size: 11px;
    padding: 8px 12px;
    border-radius: 8px;
    border: 1px solid #45475a;
    box-shadow: 0 4px 12px rgba(0, 0, 0, 0.4);
    z-index: 99999;
    line-height: 1.7;
    cursor: pointer;
    transition: all 0.2s ease;
    max-width: 220px;
    user-select: none;
}
#bss-dev-stats:hover {
    border-color: #89b4fa;
    box-shadow: 0 4px 16px rgba(137, 180, 250, 0.15);
}
#bss-dev-stats .bss-header {
    font-weight: 600;
    color: #89b4fa;
    font-size: 12px;
}
#bss-dev-stats .bss-detail {
    display: none;
    margin-top: 6px;
    padding-top: 6px;
    border-top: 1px solid #313244;
}
#bss-dev-stats.bss-open .bss-detail { display: block; }
#bss-dev-stats .bss-row {
    display: flex;
    justify-content: space-between;
    gap: 12px;
}
#bss-dev-stats .bss-label { color: #a6adc8; }
#bss-dev-stats .bss-value { color: #a6e3a1; font-weight: 500; }
#bss-dev-stats .bss-dot {
    display: inline-block;
    width: 6px;
    height: 6px;
    border-radius: 50%;
    background: #a6e3a1;
    margin-right: 6px;
    animation: bss-pulse 2s infinite;
}
@keyframes bss-pulse {
    0%, 100% { opacity: 1; }
    50% { opacity: 0.4; }
}
</style>
<div id="bss-dev-stats" onclick="this.classList.toggle('bss-open')">
    <div class="bss-header"><span class="bss-dot"></span>bss dev</div>
    <div class="bss-detail">
        <div class="bss-row"><span class="bss-label">Pages</span><span class="bss-value" id="bss-pages">&mdash;</span></div>
        <div class="bss-row"><span class="bss-label">Files</span><span class="bss-value" id="bss-files">&mdash;</span></div>
        <div class="bss-row"><span class="bss-label">Size</span><span class="bss-value" id="bss-size">&mdash;</span></div>
        <div class="bss-row"><span class="bss-label">Build</span><span class="bss-value" id="bss-build-time">&mdash;</span></div>
        <div class="bss-row"><span class="bss-label">Built at</span><span class="bss-value" id="bss-built-at">&mdash;</span></div>
    </div>
</div>
<script>
(function() {
    var lastBuildId = null;
    function formatBytes(bytes) {
        if (bytes < 1024) return bytes + ' B';
        if (bytes < 1048576) return (bytes / 1024).toFixed(1) + ' KB';
        return (bytes / 1048576).toFixed(1) + ' MB';
    }
    function updateStats(data) {
        var el = function(id) { return document.getElementById(id); };
        el('bss-pages').textContent = data.page_count;
        el('bss-files').textContent = data.file_count;
        el('bss-size').textContent = formatBytes(data.total_size_bytes);
        el('bss-build-time').textContent = data.build_duration_ms + 'ms';
        el('bss-built-at').textContent = data.build_time;
    }
    function poll() {
        fetch('/__bss/poll')
            .then(function(r) { return r.json(); })
            .then(function(data) {
                if (lastBuildId === null) {
                    lastBuildId = data.build_id;
                } else if (data.build_id !== lastBuildId) {
                    location.reload();
                    return;
                }
                updateStats(data);
            })
            .catch(function() {});
    }
    setInterval(poll, 1000);
    poll();
})();
</script>
END_SNIPPET
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
<p> The requested document has moved <a href="$moved_to">here</a>.</p>
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
