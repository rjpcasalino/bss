# Core Web server routines from:
# Chapter 15 of "Network Programming with Perl"
# Copyright Lincoln D. Stein, 2000 

package Web;

use parent 'Exporter';
our @EXPORT = qw(handle_connection docroot set_dev_mode);

use IO::Compress::Gzip qw(gzip $GzipError);
use Cwd qw(abs_path realpath);
use File::Spec::Functions qw(catfile);
use JSON::PP;

my $DOCUMENT_ROOT = defined($ENV{'BSS_DOCROOT'}) ? $ENV{'BSS_DOCROOT'} : '_site';
my $CRLF = "\015\012";
my $DEV_MODE = 0;
my $META_FILE = '';
my $SRC_DIR = '';
my $TT_DIR = '';

my $MAX_POST_BODY  = 10_000_000;  # 10 MB
my $MIN_GZIP_BYTES = 256;         # skip compression for tiny responses

my @MD_EXTENSIONS = qw(.md .markdown .mdown .mkdn .mkd .MD .Markdown);

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

my %COMPRESSIBLE = map { $_ => 1 } qw(
	text/html text/css application/javascript application/json
	application/xml image/svg+xml text/plain
);

sub set_dev_mode {
	$META_FILE = shift;
	$SRC_DIR = shift // '';
	$TT_DIR = shift // '';
	$DEV_MODE = 1;
}

sub handle_connection {
	my $c = shift; #socket
	local $/ = "$CRLF$CRLF"; # set end of line character
	my $request = <$c>; # read request header

	return invalid_request($c)
	 unless my ($method, $url) = $request =~ m!^(GET|HEAD|POST) (/.*) HTTP/1\.[01]!;

	# Parse headers for Accept-Encoding and Content-Length
	my %headers;
	while ($request =~ /^([^:]+):\s*(.+?)\s*$/mg) {
		$headers{lc($1)} = $2;
	}
	my $accept_gzip = ($headers{'accept-encoding'} // '') =~ /\bgzip\b/;

	# Read POST body
	my $post_body = '';
	if ($method eq 'POST') {
		my $len = int($headers{'content-length'} // 0);
		if ($len > 0 && $len < $MAX_POST_BODY) {
			my $remaining = $len;
			while ($remaining > 0) {
				my $bytes_read = read($c, my $chunk, $remaining);
				last unless $bytes_read;
				$post_body .= $chunk;
				$remaining -= $bytes_read;
			}
		}
	}

	# Dev mode API routes
	if ($DEV_MODE) {
		return bss_poll($c, $accept_gzip) if $url eq '/__bss/poll';
		if ($url =~ m!^/__bss/source!) {
			return bss_source($c, $url, $accept_gzip) if $method eq 'GET';
		}
		if ($url =~ m!^/__bss/template!) {
			return bss_template($c, $url, $accept_gzip) if $method eq 'GET';
		}
		if ($url =~ m!^/__bss/save!) {
			return bss_save($c, $url, $post_body) if $method eq 'POST';
		}
	}

	return invalid_request($c) unless $method =~ /^(GET|HEAD)$/;

	my ($fh, $type, $length);
	return not_found($c) unless ($fh, $type, $length) = lookup_file($url);
	return redirect($c, "$url/") if $type eq 'directory';

	# In dev mode, inject live reload script, stats box, and editor into HTML
	if ($DEV_MODE && $type eq 'text/html' && $method eq 'GET') {
		return serve_html_with_reload($c, $fh, $url, $accept_gzip);
	}

	# Serve with gzip compression for compressible text types
	if ($accept_gzip && $COMPRESSIBLE{$type} && $method eq 'GET') {
		local $/;
		my $body = <$fh>;
		close $fh;
		return _send_response($c, $type, $body, 1);
	}

	# print the header
	my $ct = $type;
	if ($type =~ m!^text/!) {
		$ct .= '; charset=utf-8' unless $ct =~ /charset/;
	}
	print $c "HTTP/1.0 200 OK$CRLF";
	print $c "Content-length: $length$CRLF";
	print $c "Content-type: $ct$CRLF";
	print $c $CRLF;

	return unless $method eq 'GET';

	my $buffer;
	while ( read($fh, $buffer, 1024) ) {
		print $c $buffer;
	}
	close $fh;
}

sub _send_response {
	my ($c, $type, $body, $try_gzip, %extra) = @_;
	my $encoding = '';

	# Encode wide-character strings to UTF-8 bytes before compression/output
	utf8::encode($body) if utf8::is_utf8($body);

	if ($try_gzip && $COMPRESSIBLE{$type} && length($body) > $MIN_GZIP_BYTES) {
		my $compressed;
		if (gzip(\$body => \$compressed)) {
			$body = $compressed;
			$encoding = 'gzip';
		}
	}

	my $length = length($body);
	my $ct = $type;
	# Add charset for text types so browsers interpret UTF-8 correctly
	if ($type =~ m!^text/! || $type eq 'application/javascript' || $type eq 'application/json') {
		$ct .= '; charset=utf-8' unless $ct =~ /charset/;
	}
	print $c "HTTP/1.0 200 OK$CRLF";
	print $c "Content-type: $ct$CRLF";
	print $c "Content-length: $length$CRLF";
	print $c "Content-Encoding: gzip$CRLF" if $encoding;
	print $c "Vary: Accept-Encoding$CRLF" if $COMPRESSIBLE{$type};
	for my $h (keys %extra) {
		print $c "$h: $extra{$h}$CRLF";
	}
	print $c $CRLF;
	print $c $body;
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
	my ($c, $accept_gzip) = @_;
	my $json = '{}';
	if (-f $META_FILE) {
		if (open my $fh, '<', $META_FILE) {
			local $/;
			$json = <$fh>;
			close $fh;
		}
	}
	_send_response($c, 'application/json', $json, $accept_gzip,
		'Cache-Control' => 'no-cache, no-store');
}

# GET /__bss/source?url=/path — return raw markdown source for editing
sub bss_source {
	my ($c, $request_url, $accept_gzip) = @_;

	my ($target) = $request_url =~ /[?&]url=([^&]*)/;
	$target //= '/';
	$target =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/ge;

	my $source_path = _url_to_source($target);
	unless ($source_path) {
		return _send_json($c, 404, '{"error":"source not found"}');
	}

	if (open my $fh, '<:encoding(UTF-8)', $source_path) {
		local $/;
		my $content = <$fh>;
		close $fh;

		# Extract layout name from YAML front matter
		my $layout = '';
		if ($content =~ /\A---(.+?)---/s) {
			my $yaml_block = $1;
			if ($yaml_block =~ /^\s*layout\s*:\s*(.+?)\s*$/m) {
				$layout = $1;
			}
		}

		my $json = JSON::PP->new->utf8->encode({
			path    => $source_path,
			content => $content,
			layout  => $layout,
		});

		_send_response($c, 'application/json', $json, $accept_gzip,
			'Cache-Control' => 'no-cache, no-store');
	} else {
		_send_json($c, 500, '{"error":"cannot read file"}');
	}
}

# GET /__bss/template?name=layout_name — return template source for editing
sub bss_template {
	my ($c, $request_url, $accept_gzip) = @_;

	my ($name) = $request_url =~ /[?&]name=([^&]*)/;
	$name //= '';
	$name =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/ge;

	unless ($name && $TT_DIR) {
		return _send_json($c, 404, '{"error":"template not found"}');
	}

	# Security: reject template names with path traversal components
	if ($name =~ m!(?:^|/)\.\.(?:/|$)! || $name =~ m!/!) {
		return _send_json($c, 403, '{"error":"forbidden"}');
	}

	my $template_path = _find_template($name);
	unless ($template_path) {
		return _send_json($c, 404, '{"error":"template not found"}');
	}

	if (open my $fh, '<:encoding(UTF-8)', $template_path) {
		local $/;
		my $content = <$fh>;
		close $fh;

		my $json = JSON::PP->new->utf8->encode({
			path    => $template_path,
			content => $content,
		});

		_send_response($c, 'application/json', $json, $accept_gzip,
			'Cache-Control' => 'no-cache, no-store');
	} else {
		_send_json($c, 500, '{"error":"cannot read template"}');
	}
}

# POST /__bss/save?url=/path — write source/template back to disk
# For templates, pass type=template&path=/full/path
sub bss_save {
	my ($c, $request_url, $body) = @_;

	my ($save_type) = $request_url =~ /[?&]type=([^&]*)/;
	$save_type //= 'source';

	my $source_path;
	my $guard_dir;

	if ($save_type eq 'template') {
		my ($tpath) = $request_url =~ /[?&]path=([^&]*)/;
		$tpath //= '';
		$tpath =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/ge;
		$source_path = $tpath;
		$guard_dir = $TT_DIR;
	} else {
		my ($target) = $request_url =~ /[?&]url=([^&]*)/;
		$target //= '/';
		$target =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/ge;
		$source_path = _url_to_source($target);
		$guard_dir = $SRC_DIR;
	}

	unless ($source_path) {
		return _send_json($c, 404, '{"error":"source not found"}');
	}

	# Security: resolve symlinks and verify the path is within the guard dir
	my $abs_path = realpath($source_path);
	my $abs_guard = realpath($guard_dir);
	unless ($abs_path && $abs_guard && $abs_path =~ /^\Q$abs_guard\E/) {
		return _send_json($c, 403, '{"error":"forbidden"}');
	}

	if (open my $fh, '>:encoding(UTF-8)', $source_path) {
		print $fh $body;
		close $fh;
		_send_json($c, 200, '{"ok":true}');
	} else {
		_send_json($c, 500, '{"error":"cannot write file"}');
	}
}

sub _send_json {
	my ($c, $code, $json) = @_;
	my $status = $code == 200 ? 'OK'
		: $code == 403 ? 'Forbidden'
		: $code == 404 ? 'Not Found'
		: 'Internal Server Error';
	my $len = length($json);
	print $c "HTTP/1.0 $code $status$CRLF";
	print $c "Content-type: application/json$CRLF";
	print $c "Content-length: $len$CRLF";
	print $c $CRLF;
	print $c $json;
}

# Map a served URL back to its source markdown file
sub _url_to_source {
	my ($url) = @_;
	return undef unless $SRC_DIR;

	$url =~ s!^/!!;               # strip leading /
	$url =~ s!\?.*$!!;            # strip query string
	$url =~ s!/$!index.html!;     # trailing / → index.html
	$url = 'index.html' if $url eq '';

	# If the URL includes the SRC directory name as a prefix, strip it
	my $src_base = (File::Spec->splitdir($SRC_DIR))[-1];
	$url =~ s!^\Q$src_base\E/!! if defined $src_base;

	# Remove .html extension and try markdown extensions
	(my $base = $url) =~ s!\.html$!!;

	for my $ext (@MD_EXTENSIONS) {
		my $path = catfile($SRC_DIR, $base . $ext);
		return $path if -f $path;
	}

	# Try as directory index
	for my $ext (@MD_EXTENSIONS) {
		my $path = catfile($SRC_DIR, $base, "index" . $ext);
		return $path if -f $path;
	}

	return undef;
}

# Find a template file by layout name inside TT_DIR
sub _find_template {
	my ($name) = @_;
	return undef unless $name && $TT_DIR && -d $TT_DIR;

	# Reject names with path traversal or directory separators
	return undef if $name =~ m!(?:^|/)\.\.(?:/|$)! || $name =~ m!/!;

	my @exts = qw(.tmpl .template .html .tt .tt2);

	for my $ext (@exts) {
		my $path = catfile($TT_DIR, $name . $ext);
		return $path if -f $path;
	}

	# Try bare name (exact filename)
	my $bare = catfile($TT_DIR, $name);
	return $bare if -f $bare;

	return undef;
}

sub serve_html_with_reload {
	my ($c, $fh, $url, $accept_gzip) = @_;

	local $/;
	my $html = <$fh>;
	close $fh;

	my $snippet = _dev_snippet($url);

	# Inject before </body> if present, otherwise append
	unless ($html =~ s!(</body>)!$snippet$1!i) {
		$html .= $snippet;
	}

	_send_response($c, 'text/html', $html, $accept_gzip);
}

sub _dev_snippet {
	my ($url) = @_;
	$url //= '/';
	# Escape for safe embedding in JS string
	$url =~ s/'/\\'/g;
	return <<"END_SNIPPET";
<!-- bss dev mode: live reload + stats + editor -->
<link rel="icon" href="data:image/svg+xml,<svg xmlns=%22http://www.w3.org/2000/svg%22 viewBox=%220 0 100 100%22><text y=%22.9em%22 font-size=%2290%22>\x{270f}\x{fe0f}</text></svg>">
<style>
html {
    transition: opacity 0.15s ease;
}
html.bss-fade-out {
    opacity: 0 !important;
}
/* --- Stats overlay: flat B&W A4 paper style --- */
#bss-dev-stats {
    position: fixed;
    bottom: 12px;
    right: 12px;
    background: #fff;
    color: #000;
    font-family: 'Courier New', Courier, monospace;
    font-size: 11px;
    padding: 10px 14px;
    border: 1px solid #000;
    z-index: 99999;
    line-height: 1.7;
    cursor: pointer;
    max-width: 220px;
    user-select: none;
}
#bss-dev-stats .bss-header {
    font-weight: 700;
    font-size: 12px;
    color: #000;
    border-bottom: 1px solid #000;
    padding-bottom: 4px;
    margin-bottom: 4px;
}
#bss-dev-stats .bss-detail {
    display: none;
    margin-top: 4px;
}
#bss-dev-stats.bss-open .bss-detail { display: block; }
#bss-dev-stats .bss-row {
    display: flex;
    justify-content: space-between;
    gap: 12px;
}
#bss-dev-stats .bss-label { color: #555; }
#bss-dev-stats .bss-value { color: #000; font-weight: 600; }
#bss-dev-stats .bss-dot {
    display: inline-block;
    width: 6px;
    height: 6px;
    border-radius: 50%;
    background: #000;
    margin-right: 6px;
    animation: bss-pulse 2s infinite;
}
\@keyframes bss-pulse {
    0%, 100% { opacity: 1; }
    50% { opacity: 0.3; }
}
/* --- Editor panel: flat B&W A4 paper style --- */
#bss-editor {
    position: fixed;
    bottom: 0;
    left: 0;
    right: 0;
    background: #fff;
    color: #000;
    font-family: 'Courier New', Courier, monospace;
    font-size: 12px;
    z-index: 99998;
    border-top: 2px solid #000;
    transition: transform 0.25s ease, height 0.25s ease;
    transform: translateY(100%);
    height: 310px;
    display: flex;
    flex-direction: column;
}
#bss-editor.bss-editor-open {
    transform: translateY(0);
}
#bss-editor.bss-editor-full {
    height: 100vh !important;
}
#bss-editor.bss-dragging {
    transition: none;
    user-select: none;
}
#bss-editor .bss-drag-handle {
    height: 6px;
    cursor: ns-resize;
    background: #f5f5f5;
    display: flex;
    align-items: center;
    justify-content: center;
    flex-shrink: 0;
}
#bss-editor .bss-drag-handle::after {
    content: '';
    width: 36px;
    height: 3px;
    border-top: 1px solid #999;
    border-bottom: 1px solid #999;
}
#bss-editor .bss-editor-bar {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 6px 14px;
    background: #f5f5f5;
    border-bottom: 1px solid #000;
    user-select: none;
}
#bss-editor .bss-editor-bar .bss-editor-title {
    color: #000;
    font-weight: 700;
}
#bss-editor .bss-editor-bar .bss-editor-path {
    color: #555;
    font-size: 11px;
    margin-left: 12px;
}
#bss-editor .bss-editor-tabs {
    display: flex;
    gap: 0;
    margin-left: 16px;
}
#bss-editor .bss-editor-tabs button {
    background: #fff;
    color: #000;
    border: 1px solid #000;
    border-bottom: none;
    padding: 3px 14px;
    font-family: inherit;
    font-size: 11px;
    cursor: pointer;
    font-weight: 400;
}
#bss-editor .bss-editor-tabs button.bss-tab-active {
    background: #000;
    color: #fff;
    font-weight: 700;
}
#bss-editor .bss-editor-bar .bss-editor-actions {
    display: flex;
    gap: 8px;
    align-items: center;
}
#bss-editor .bss-editor-bar button.bss-action-btn {
    background: #fff;
    color: #000;
    border: 1px solid #000;
    padding: 3px 12px;
    font-family: inherit;
    font-size: 11px;
    cursor: pointer;
}
#bss-editor .bss-editor-bar button.bss-action-btn:hover {
    background: #000;
    color: #fff;
}
#bss-editor .bss-editor-bar button.bss-save-btn {
    background: #000;
    color: #fff;
    border: 1px solid #000;
    font-weight: 700;
}
#bss-editor .bss-editor-bar button.bss-save-btn:hover {
    background: #333;
}
#bss-editor .bss-editor-status {
    font-size: 11px;
    margin-left: 8px;
    color: #555;
}
#bss-editor textarea {
    width: 100%;
    flex: 1;
    min-height: 0;
    background: #fff;
    color: #000;
    border: none;
    border-top: 1px solid #ccc;
    padding: 12px 14px;
    font-family: 'Courier New', Courier, monospace;
    font-size: 13px;
    line-height: 1.6;
    resize: none;
    outline: none;
    box-sizing: border-box;
    tab-size: 4;
}
#bss-editor textarea:focus {
    background: #fffff8;
}
/* Toggle button: flat B&W */
#bss-editor-toggle {
    position: fixed;
    bottom: 12px;
    right: 240px;
    background: #fff;
    color: #000;
    font-family: 'Courier New', Courier, monospace;
    font-size: 12px;
    font-weight: 700;
    padding: 7px 14px;
    border: 1px solid #000;
    z-index: 99999;
    cursor: pointer;
    user-select: none;
}
#bss-editor-toggle:hover {
    background: #000;
    color: #fff;
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
<div id="bss-editor-toggle" onclick="bssToggleEditor()">\x{270f}\x{fe0f} Edit</div>
<div id="bss-editor">
    <div class="bss-drag-handle" id="bss-drag-handle"></div>
    <div class="bss-editor-bar">
        <div style="display:flex;align-items:center">
            <span class="bss-editor-title">\x{270f}\x{fe0f} Editor</span>
            <span class="bss-editor-path" id="bss-editor-path"></span>
            <div class="bss-editor-tabs" id="bss-editor-tabs">
                <button class="bss-tab-active" id="bss-tab-source" onclick="event.stopPropagation();bssSwitchTab('source')">Source</button>
                <button id="bss-tab-template" onclick="event.stopPropagation();bssSwitchTab('template')">Template</button>
            </div>
        </div>
        <div class="bss-editor-actions" onclick="event.stopPropagation()">
            <span class="bss-editor-status" id="bss-editor-status"></span>
            <button class="bss-save-btn" onclick="bssSave()">Save</button>
            <button class="bss-action-btn" onclick="bssToggleEditor()">\x{2715} Close</button>
        </div>
    </div>
    <textarea id="bss-editor-textarea" onclick="event.stopPropagation()" spellcheck="false"></textarea>
</div>
<script>
(function() {
    var lastBuildId = null;
    var currentUrl = '$url';
    var editorLoaded = false;
    var activeTab = 'source';
    var sourceData = null;
    var templateData = null;
    var templateLoaded = false;

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
    function smoothReload() {
        document.documentElement.classList.add('bss-fade-out');
        setTimeout(function() { location.reload(); }, 180);
    }
    function poll() {
        fetch('/__bss/poll')
            .then(function(r) { return r.json(); })
            .then(function(data) {
                if (lastBuildId === null) {
                    lastBuildId = data.build_id;
                } else if (data.build_id !== lastBuildId) {
                    smoothReload();
                    return;
                }
                updateStats(data);
            })
            .catch(function() {});
    }
    setInterval(poll, 1000);
    poll();

    /* Restore editor state from localStorage */
    var wasOpen = false;
    try { wasOpen = localStorage.getItem('bss-editor-open') === '1'; } catch(e) {}
    if (wasOpen) {
        /* Defer so DOM is ready */
        setTimeout(function() { bssToggleEditor(); }, 0);
    }

    /* Editor functions */
    window.bssToggleEditor = function() {
        var editor = document.getElementById('bss-editor');
        var toggle = document.getElementById('bss-editor-toggle');
        var isOpen = editor.classList.toggle('bss-editor-open');
        toggle.style.display = isOpen ? 'none' : 'block';
        try { localStorage.setItem('bss-editor-open', isOpen ? '1' : '0'); } catch(e) {}
        if (isOpen && !editorLoaded) {
            bssLoadSource();
        }
    };

    window.bssSwitchTab = function(tab) {
        activeTab = tab;
        document.getElementById('bss-tab-source').className = tab === 'source' ? 'bss-tab-active' : '';
        document.getElementById('bss-tab-template').className = tab === 'template' ? 'bss-tab-active' : '';
        var ta = document.getElementById('bss-editor-textarea');
        var pathEl = document.getElementById('bss-editor-path');
        if (tab === 'source' && sourceData) {
            ta.value = sourceData.content;
            pathEl.textContent = sourceData.path;
        } else if (tab === 'template') {
            if (templateData) {
                ta.value = templateData.content;
                pathEl.textContent = templateData.path;
            } else if (sourceData && sourceData.layout) {
                bssLoadTemplate(sourceData.layout);
            } else {
                ta.value = 'No template found for this page';
                pathEl.textContent = '';
            }
        }
    };

    window.bssLoadSource = function() {
        var status = document.getElementById('bss-editor-status');
        status.textContent = 'Loading...';
        status.style.color = '#555';
        fetch('/__bss/source?url=' + encodeURIComponent(currentUrl))
            .then(function(r) { return r.json(); })
            .then(function(data) {
                if (data.error) {
                    status.textContent = data.error;
                    status.style.color = '#c00';
                    return;
                }
                sourceData = data;
                if (activeTab === 'source') {
                    document.getElementById('bss-editor-textarea').value = data.content;
                    document.getElementById('bss-editor-path').textContent = data.path;
                }
                status.textContent = '';
                editorLoaded = true;
            })
            .catch(function(e) {
                status.textContent = 'Failed to load';
                status.style.color = '#c00';
            });
    };

    window.bssLoadTemplate = function(layoutName) {
        var status = document.getElementById('bss-editor-status');
        status.textContent = 'Loading template...';
        status.style.color = '#555';
        fetch('/__bss/template?name=' + encodeURIComponent(layoutName))
            .then(function(r) { return r.json(); })
            .then(function(data) {
                if (data.error) {
                    status.textContent = data.error;
                    status.style.color = '#c00';
                    return;
                }
                templateData = data;
                templateLoaded = true;
                if (activeTab === 'template') {
                    document.getElementById('bss-editor-textarea').value = data.content;
                    document.getElementById('bss-editor-path').textContent = data.path;
                }
                status.textContent = '';
            })
            .catch(function(e) {
                status.textContent = 'Failed to load template';
                status.style.color = '#c00';
            });
    };

    window.bssSave = function() {
        var status = document.getElementById('bss-editor-status');
        var content = document.getElementById('bss-editor-textarea').value;
        status.textContent = 'Saving...';
        status.style.color = '#555';
        var saveUrl;
        if (activeTab === 'template' && templateData) {
            saveUrl = '/__bss/save?type=template&path=' + encodeURIComponent(templateData.path);
            templateData.content = content;
        } else {
            saveUrl = '/__bss/save?url=' + encodeURIComponent(currentUrl);
            if (sourceData) sourceData.content = content;
        }
        fetch(saveUrl, {
            method: 'POST',
            headers: { 'Content-Type': 'text/plain' },
            body: content
        })
        .then(function(r) { return r.json(); })
        .then(function(data) {
            if (data.ok) {
                status.textContent = 'Saved!';
                status.style.color = '#080';
                setTimeout(function() { status.textContent = ''; }, 2000);
            } else {
                status.textContent = data.error || 'Save failed';
                status.style.color = '#c00';
            }
        })
        .catch(function() {
            status.textContent = 'Save failed';
            status.style.color = '#c00';
        });
    };

    /* Tab key inserts a tab instead of leaving the textarea */
    var ta = document.getElementById('bss-editor-textarea');
    ta.addEventListener('keydown', function(e) {
        if (e.key === 'Tab') {
            e.preventDefault();
            var start = this.selectionStart;
            var end = this.selectionEnd;
            this.value = this.value.substring(0, start) + '\\t' + this.value.substring(end);
            this.selectionStart = this.selectionEnd = start + 1;
        }
        /* Ctrl/Cmd+S to save */
        if ((e.ctrlKey || e.metaKey) && e.key === 's') {
            e.preventDefault();
            bssSave();
        }
    });

    /* Drag-to-resize editor panel */
    (function() {
        var handle = document.getElementById('bss-drag-handle');
        var editor = document.getElementById('bss-editor');
        var defaultH = parseInt(getComputedStyle(editor).height, 10) || 310;
        var dragging = false;
        var startY = 0;
        var startH = 0;

        function snapAfterDrag() {
            dragging = false;
            editor.classList.remove('bss-dragging');
            var h = editor.offsetHeight;
            var maxH = window.innerHeight;
            if (h > maxH * 0.7) {
                editor.style.height = '';
                editor.classList.add('bss-editor-full');
                try { localStorage.setItem('bss-editor-full', '1'); localStorage.removeItem('bss-editor-height'); } catch(e) {}
            } else if (h < defaultH * 1.3) {
                editor.style.height = defaultH + 'px';
                try { localStorage.setItem('bss-editor-full', '0'); localStorage.removeItem('bss-editor-height'); } catch(e) {}
            } else {
                try { localStorage.setItem('bss-editor-full', '0'); localStorage.setItem('bss-editor-height', h); } catch(e) {}
            }
        }

        function clampHeight(deltaY) {
            var newH = startH + deltaY;
            var maxH = window.innerHeight;
            if (newH < 100) newH = 100;
            if (newH > maxH) newH = maxH;
            editor.style.height = newH + 'px';
        }

        function startDrag(y) {
            dragging = true;
            startY = y;
            startH = editor.offsetHeight;
            editor.classList.add('bss-dragging');
            editor.classList.remove('bss-editor-full');
        }

        handle.addEventListener('mousedown', function(e) {
            e.preventDefault();
            startDrag(e.clientY);
        });

        document.addEventListener('mousemove', function(e) {
            if (!dragging) return;
            clampHeight(startY - e.clientY);
        });

        document.addEventListener('mouseup', function() {
            if (!dragging) return;
            snapAfterDrag();
        });

        /* Touch support for mobile */
        handle.addEventListener('touchstart', function(e) {
            e.preventDefault();
            startDrag(e.touches[0].clientY);
        }, {passive: false});

        document.addEventListener('touchmove', function(e) {
            if (!dragging) return;
            clampHeight(startY - e.touches[0].clientY);
        });

        document.addEventListener('touchend', function() {
            if (!dragging) return;
            snapAfterDrag();
        });

        /* Restore editor size from localStorage */
        try {
            if (localStorage.getItem('bss-editor-full') === '1') {
                editor.classList.add('bss-editor-full');
            } else {
                var savedH = localStorage.getItem('bss-editor-height');
                if (savedH) {
                    editor.style.height = parseInt(savedH, 10) + 'px';
                }
            }
        } catch(e) {}

        /* Double-click handle to toggle full-screen / default */
        handle.addEventListener('dblclick', function(e) {
            e.preventDefault();
            if (editor.classList.contains('bss-editor-full')) {
                editor.classList.remove('bss-editor-full');
                editor.style.height = defaultH + 'px';
                try { localStorage.setItem('bss-editor-full', '0'); localStorage.removeItem('bss-editor-height'); } catch(e2) {}
            } else {
                editor.style.height = '';
                editor.classList.add('bss-editor-full');
                try { localStorage.setItem('bss-editor-full', '1'); localStorage.removeItem('bss-editor-height'); } catch(e2) {}
            }
        });
    })();
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
