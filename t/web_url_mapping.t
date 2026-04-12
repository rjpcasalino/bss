#!/usr/bin/env perl
# Tests for Web.pm internal URL-to-source mapping and template lookup

use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use File::Spec::Functions qw(catfile);
use FindBin qw($Bin);
use lib "$Bin/../lib";

# We test _url_to_source and _find_template by setting up temp dirs
# and calling the functions via the Web module internals.

# --- Setup temp source and template dirs ---
my $src_dir = tempdir(CLEANUP => 1);
my $tt_dir  = tempdir(CLEANUP => 1);

# Create source files
_touch(catfile($src_dir, 'index.md'));
_touch(catfile($src_dir, 'about.md'));
mkdir catfile($src_dir, 'posts') or die "Cannot mkdir posts: $!";
_touch(catfile($src_dir, 'posts', 'hello.md'));
_touch(catfile($src_dir, 'posts', 'index.md'));

# Create template files
_touch(catfile($tt_dir, 'default.html'));
_touch(catfile($tt_dir, 'post.tmpl'));
_touch(catfile($tt_dir, 'page.tt'));

# Load Web module and set up state
require Web;
Web::set_dev_mode(catfile($src_dir, '__bss_meta.json'), $src_dir, $tt_dir);

# --- _url_to_source tests ---

# Basic index page
{
    my $path = Web::_url_to_source('/');
    ok(defined $path, '_url_to_source: / resolves');
    like($path, qr/index\.md$/, '_url_to_source: / maps to index.md');
}

# Named page
{
    my $path = Web::_url_to_source('/about.html');
    ok(defined $path, '_url_to_source: /about.html resolves');
    like($path, qr/about\.md$/, '_url_to_source: /about.html maps to about.md');
}

# Collection page
{
    my $path = Web::_url_to_source('/posts/hello.html');
    ok(defined $path, '_url_to_source: /posts/hello.html resolves');
    like($path, qr/hello\.md$/, '_url_to_source: /posts/hello.html maps to hello.md');
}

# Collection index via trailing slash
{
    my $path = Web::_url_to_source('/posts/');
    ok(defined $path, '_url_to_source: /posts/ resolves');
    like($path, qr/posts.*index\.md$/, '_url_to_source: /posts/ maps to posts/index.md');
}

# Non-existent page
{
    my $path = Web::_url_to_source('/nonexistent.html');
    ok(!defined $path, '_url_to_source: nonexistent page returns undef');
}

# Path traversal is handled by caller, but empty result is fine
{
    my $path = Web::_url_to_source('/../etc/passwd');
    ok(!defined $path, '_url_to_source: path traversal returns undef');
}

# --- _find_template tests ---

# Find by name with .html extension
{
    my $path = Web::_find_template('default');
    ok(defined $path, '_find_template: default found');
    like($path, qr/default\.html$/, '_find_template: default resolves to .html');
}

# Find by name with .tmpl extension
{
    my $path = Web::_find_template('post');
    ok(defined $path, '_find_template: post found');
    like($path, qr/post\.tmpl$/, '_find_template: post resolves to .tmpl');
}

# Find by name with .tt extension
{
    my $path = Web::_find_template('page');
    ok(defined $path, '_find_template: page found');
    like($path, qr/page\.tt$/, '_find_template: page resolves to .tt');
}

# Non-existent template
{
    my $path = Web::_find_template('missing');
    ok(!defined $path, '_find_template: missing returns undef');
}

# Path traversal rejected
{
    my $path = Web::_find_template('../etc/passwd');
    ok(!defined $path, '_find_template: path traversal rejected');
}

# Slash in name rejected
{
    my $path = Web::_find_template('sub/template');
    ok(!defined $path, '_find_template: slash in name rejected');
}

# Empty name
{
    my $path = Web::_find_template('');
    ok(!defined $path, '_find_template: empty name returns undef');
}

done_testing();

sub _touch {
    my ($path) = @_;
    open my $fh, '>', $path or die "Cannot create $path: $!";
    close $fh;
}
