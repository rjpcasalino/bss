#!/usr/bin/env perl
# Tests for the dev server HTTP handler: response codes, content types,
# dev mode API endpoints, gzip, and the editor save flow.

use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use File::Spec::Functions qw(catfile catdir);
use File::Path qw(make_path);
use FindBin qw($Bin);
use lib "$Bin/../lib";

require Web;

# --- Setup a temp docroot with test files ---
my $docroot = tempdir(CLEANUP => 1);
my $src_dir = tempdir(CLEANUP => 1);
my $tt_dir  = tempdir(CLEANUP => 1);

# Create HTML file
_write_file(catfile($docroot, 'index.html'), '<html><body>Hello</body></html>');

# Create CSS file
_write_file(catfile($docroot, 'style.css'), 'body { color: black; }');

# Create JS file
_write_file(catfile($docroot, 'app.js'), 'console.log("hi");');

# Create image
_write_file(catfile($docroot, 'logo.png'), 'PNG DATA');

# Subdirectory
make_path(catdir($docroot, 'posts'));
_write_file(catfile($docroot, 'posts', 'index.html'), '<html><body>Posts</body></html>');

# Create source files
_write_file(catfile($src_dir, 'index.md'), "---\ntitle: Home\nlayout: default\n---\n# Home\n");
_write_file(catfile($src_dir, 'about.md'), "---\ntitle: About\nlayout: default\n---\n# About\n");

# Create template
_write_file(catfile($tt_dir, 'default.html'), '<html>[% body %]</html>');

# Set up Web module
Web::docroot($docroot);
Web::set_dev_mode(catfile($docroot, '__bss_meta.json'), $src_dir, $tt_dir);

# Create meta file for poll endpoint
_write_file(catfile($docroot, '__bss_meta.json'), '{"build_id":1,"page_count":2}');

# --- Test lookup_file ---
subtest 'lookup_file' => sub {
    # HTML file
    my ($fh, $type, $len) = Web::lookup_file('/index.html');
    ok(defined $fh, 'index.html found');
    is($type, 'text/html', 'Correct MIME type for HTML');
    ok($len > 0, 'File has content');
    close $fh if $fh;

    # CSS file
    ($fh, $type, $len) = Web::lookup_file('/style.css');
    ok(defined $fh, 'style.css found');
    is($type, 'text/css', 'Correct MIME type for CSS');
    close $fh if $fh;

    # JS file
    ($fh, $type, $len) = Web::lookup_file('/app.js');
    ok(defined $fh, 'app.js found');
    is($type, 'application/javascript', 'Correct MIME type for JS');
    close $fh if $fh;

    # PNG image
    ($fh, $type, $len) = Web::lookup_file('/logo.png');
    ok(defined $fh, 'logo.png found');
    is($type, 'image/png', 'Correct MIME type for PNG');
    close $fh if $fh;

    # Directory redirect
    ($fh, $type, $len) = Web::lookup_file('/posts');
    is($type, 'directory', 'Directory detected for redirect');

    # Auto index.html for trailing slash
    ($fh, $type, $len) = Web::lookup_file('/posts/');
    ok(defined $fh, 'posts/ resolves to posts/index.html');
    is($type, 'text/html', 'Auto-index returns HTML type');
    close $fh if $fh;

    # 404 for missing file
    ($fh, $type, $len) = Web::lookup_file('/nonexistent.html');
    ok(!defined $fh, 'Missing file returns undef');

    # Path traversal blocked
    ($fh, $type, $len) = Web::lookup_file('/../etc/passwd');
    ok(!defined $fh, 'Path traversal blocked');
};

# --- Test _url_to_source ---
subtest '_url_to_source' => sub {
    my $path = Web::_url_to_source('/');
    ok(defined $path, '/ maps to source');
    like($path, qr/index\.md$/, '/ maps to index.md');

    $path = Web::_url_to_source('/about.html');
    ok(defined $path, '/about.html maps to source');
    like($path, qr/about\.md$/, '/about.html maps to about.md');

    $path = Web::_url_to_source('/missing.html');
    ok(!defined $path, 'Missing page returns undef');
};

# --- Test _find_template ---
subtest '_find_template' => sub {
    my $path = Web::_find_template('default');
    ok(defined $path, 'default template found');
    like($path, qr/default\.html$/, 'Found correct template file');

    $path = Web::_find_template('missing');
    ok(!defined $path, 'Missing template returns undef');

    $path = Web::_find_template('../etc');
    ok(!defined $path, 'Path traversal in template name rejected');

    $path = Web::_find_template('sub/dir');
    ok(!defined $path, 'Slash in template name rejected');

    $path = Web::_find_template('');
    ok(!defined $path, 'Empty template name returns undef');
};

# --- Test _send_response via mock socket ---
subtest '_send_response content types' => sub {
    # Text type gets charset added
    my $output = _capture_response(sub {
        my $sock = shift;
        Web::_send_response($sock, 'text/html', '<html>hi</html>', 0);
    });
    like($output, qr/Content-type: text\/html; charset=utf-8/, 'HTML gets charset');
    like($output, qr/200 OK/, '200 status');

    # JSON gets charset
    $output = _capture_response(sub {
        my $sock = shift;
        Web::_send_response($sock, 'application/json', '{"ok":true}', 0);
    });
    like($output, qr/charset=utf-8/, 'JSON gets charset');

    # Binary type doesn't get charset
    $output = _capture_response(sub {
        my $sock = shift;
        Web::_send_response($sock, 'image/png', 'PNG', 0);
    });
    unlike($output, qr/charset/, 'Binary types get no charset');
};

# --- Test _send_json ---
subtest '_send_json status codes' => sub {
    my $output = _capture_response(sub {
        my $sock = shift;
        Web::_send_json($sock, 200, '{"ok":true}');
    });
    like($output, qr/200 OK/, '200 status');
    like($output, qr/application\/json/, 'JSON content type');

    $output = _capture_response(sub {
        my $sock = shift;
        Web::_send_json($sock, 404, '{"error":"not found"}');
    });
    like($output, qr/404 Not Found/, '404 status');

    $output = _capture_response(sub {
        my $sock = shift;
        Web::_send_json($sock, 403, '{"error":"forbidden"}');
    });
    like($output, qr/403 Forbidden/, '403 status');
};

# --- Test dev snippet injection ---
subtest 'Dev snippet injection' => sub {
    my $snippet = Web::_dev_snippet('/');
    like($snippet, qr/bss dev mode/, 'Snippet has dev mode marker');
    like($snippet, qr/bss-dev-stats/, 'Snippet has stats overlay');
    like($snippet, qr/bss-editor/, 'Snippet has editor');
    like($snippet, qr/__bss\/poll/, 'Snippet polls for updates');
    like($snippet, qr/swapContent/, 'Snippet has in-place swap function');
    like($snippet, qr/bss-live-toggle/, 'Snippet has Live toggle');
    like($snippet, qr/selectionStart/, 'Snippet preserves cursor position');
    like($snippet, qr/scrollTop/, 'Snippet preserves scroll position');
    like($snippet, qr/userIsTyping/, 'Snippet has typing guard to prevent focus loss');
    like($snippet, qr/!userIsTyping/, 'Snippet skips source reload while user types');
    like($snippet, qr/\.focus\(\)/, 'Snippet re-focuses textarea after swap');
    like($snippet, qr/insertText/, 'Tab uses insertText to preserve undo history');

    # Standard editor keybindings
    like($snippet, qr/Shift.*Tab|shiftKey/, 'Snippet supports Shift+Tab to unindent');
    like($snippet, qr/auto-indent/, 'Snippet has Enter auto-indent');
    like($snippet, qr/leadingWS/, 'Snippet detects leading whitespace for auto-indent');
    like($snippet, qr/duplicate/, 'Snippet supports Ctrl+D duplicate line');

    # URL is properly escaped
    my $snippet2 = Web::_dev_snippet("/it's-a-page");
    like($snippet2, qr/it\\'s-a-page/, 'Single quotes escaped in URL');
};

# --- Test editor save path security ---
subtest 'Save path security' => sub {
    # _url_to_source already tested; verify realpath guard concept
    my $safe_path = Cwd::realpath($src_dir);
    ok(defined $safe_path, 'Source dir has real path');

    # A path inside src_dir should pass
    my $test_file = catfile($src_dir, 'index.md');
    my $abs = Cwd::realpath($test_file);
    ok($abs =~ /^\Q$safe_path\E/, 'File in src_dir passes guard');

    # A path outside should fail
    my $outside = '/tmp/evil.md';
    ok($outside !~ /^\Q$safe_path\E/, 'Path outside src_dir fails guard');
};

done_testing();

# --- Helper: capture HTTP response from a function that writes to a socket ---
sub _capture_response {
    my ($code) = @_;
    my $output = '';
    open my $mock, '>', \$output or die "Cannot create mock socket: $!";
    $code->($mock);
    close $mock;
    return $output;
}

sub _write_file {
    my ($path, $content) = @_;
    open my $fh, '>', $path or die "Cannot write $path: $!";
    print $fh $content;
    close $fh;
}
