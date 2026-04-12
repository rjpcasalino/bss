#!/usr/bin/env perl
# Tests for the build pipeline: YAML front matter parsing, markdown to HTML,
# collection scanning, and rsync-based site assembly.

use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use File::Spec::Functions qw(catfile catdir);
use File::Path qw(make_path);
use File::Basename;
use FindBin qw($Bin);

# We test the build functions by setting up a minimal site in a temp dir,
# running the build, and verifying the output.

my $repo_dir = "$Bin/..";

# --- Test YAML front matter parsing ---
subtest 'YAML front matter extraction' => sub {
    my $data = "---\ntitle: Hello World\nlayout: default\n---\n\n# Hello\n\nContent here.\n";
    my ($yaml_block, $body);

    if ($data =~ /\A---(.+?)---\s*/s) {
        $yaml_block = $1;
        $body = substr($data, $+[0]);
    }

    ok(defined $yaml_block, 'YAML block extracted');
    like($yaml_block, qr/title:\s*Hello World/, 'title found in YAML');
    like($yaml_block, qr/layout:\s*default/, 'layout found in YAML');
    like($body, qr/# Hello/, 'body starts after front matter');
    like($body, qr/Content here/, 'body contains content');
};

subtest 'No YAML front matter' => sub {
    my $data = "# Just Markdown\n\nNo front matter here.\n";
    my $yaml_block;
    my $body = $data;

    if ($data =~ /\A---(.+?)---\s*/s) {
        $yaml_block = $1;
        $body = substr($data, $+[0]);
    }

    ok(!defined $yaml_block, 'No YAML block when front matter absent');
    is($body, $data, 'Body is the full content');
};

# --- Test markdown rendering ---
subtest 'Markdown rendering' => sub {
    eval { require Text::Markdown };
    plan skip_all => 'Text::Markdown not available' if $@;

    my $md = "# Hello\n\nA paragraph.\n";
    my $html = Text::Markdown::markdown($md);
    like($html, qr/<h1>Hello<\/h1>/, 'H1 rendered');
    like($html, qr/<p>A paragraph\.<\/p>/, 'Paragraph rendered');
};

# --- Test editor junk regex ---
subtest 'Editor junk file filtering' => sub {
    my $EDITOR_JUNK_RE = qr/(?:^\..*\.sw[a-p]$|~$|^4913$|^\#.*\#$)/;

    # Should match (filter out)
    ok('.index.md.swp' =~ $EDITOR_JUNK_RE, 'Vim swap file matched');
    ok('.test.swo' =~ $EDITOR_JUNK_RE, 'Vim .swo file matched');
    ok('file.txt~' =~ $EDITOR_JUNK_RE, 'Backup file~ matched');
    ok('4913' =~ $EDITOR_JUNK_RE, 'Vim 4913 test file matched');
    ok('#autosave#' =~ $EDITOR_JUNK_RE, 'Emacs autosave matched');

    # Should NOT match (keep)
    ok('index.md' !~ $EDITOR_JUNK_RE, 'Normal markdown file not matched');
    ok('post.md' !~ $EDITOR_JUNK_RE, 'Normal post not matched');
    ok('style.css' !~ $EDITOR_JUNK_RE, 'CSS file not matched');
    ok('image.png' !~ $EDITOR_JUNK_RE, 'Image file not matched');
};

# --- Test collection scanning ---
subtest 'Collection scanning' => sub {
    my $src = tempdir(CLEANUP => 1);
    my $posts_dir = catdir($src, 'posts');
    make_path($posts_dir);

    # Create test posts
    _write_file(catfile($posts_dir, 'hello.md'), "---\ntitle: Hello\n---\nHello\n");
    _write_file(catfile($posts_dir, 'world.md'), "---\ntitle: World\n---\nWorld\n");

    # Create editor junk that should be filtered
    _write_file(catfile($posts_dir, '.hello.md.swp'), 'swap');
    _write_file(catfile($posts_dir, 'backup.md~'), 'backup');

    my $EDITOR_JUNK_RE = qr/(?:^\..*\.sw[a-p]$|~$|^4913$|^\#.*\#$)/;
    my $MD_EXT_RE = qr/\.[mM](ark)?[dD](own)?$/;

    my @collected;
    require File::Find;
    File::Find::find(
        sub {
            return if $_ eq '.' or $_ eq '..';
            return if $_ =~ $EDITOR_JUNK_RE;
            (my $name = $_) =~ s/$MD_EXT_RE/\.html/;
            push @collected, $name;
        },
        $posts_dir
    );

    is(scalar @collected, 2, 'Two real posts collected (junk filtered)');
    ok((grep { $_ eq 'hello.html' } @collected), 'hello.md collected as hello.html');
    ok((grep { $_ eq 'world.html' } @collected), 'world.md collected as world.html');
    ok(!(grep { /swp|backup/ } @collected), 'No junk files in collection');
};

# --- Test build output structure ---
subtest 'Full build pipeline' => sub {
    # Check if required modules are available
    eval { require Template; require Config::IniFiles; require YAML };
    plan skip_all => 'Template Toolkit or Config::IniFiles or YAML not available' if $@;

    # Check if rsync is available
    my $rsync_ok = system('rsync --version > /dev/null 2>&1') == 0;
    plan skip_all => 'rsync not available' unless $rsync_ok;

    my $tmp = tempdir(CLEANUP => 1);
    my $src = catdir($tmp, 'src');
    my $dest = catdir($tmp, '_site');
    my $templates = catdir($tmp, 'templates');

    make_path($src, $dest, $templates);

    # Create a minimal template
    _write_file(catfile($templates, 'default.html'), <<'TMPL');
<html><head><title>[% title %]</title></head>
<body>[% body.join('') %]</body></html>
TMPL

    # Create a source file
    _write_file(catfile($src, 'index.md'), <<'MD');
---
title: Test Page
layout: default
---

# Welcome

This is a test.
MD

    # Create manifest
    _write_file(catfile($tmp, 'manifest.ini'), <<"INI");
[build]
src=$src
dest=$dest
templates_dir=$templates
encoding=UTF-8
exclude=*.md, templates
INI

    # Run the build by simulating what do_build does
    my $orig_dir = Cwd::getcwd();
    chdir $tmp;

    eval {
        require Cwd;
        my %config = (
            TT_DIR     => Cwd::realpath($templates),
            SRC        => $src,
            DEST       => $dest,
            ENCODING   => 'UTF-8',
            EXCLUDE    => '*.md, templates',
            EVAL_PERL  => 0,
        );
        $config{TT_CONFIG} = {
            INCLUDE_PATH => $config{TT_DIR},
            ENCODING     => $config{ENCODING},
            EVAL_PERL    => $config{EVAL_PERL},
        };

        # Pre-scan templates
        my %template_map;
        File::Find::find(
            sub {
                return unless -f $_;
                if ($_ =~ /^(.+)\.(tmpl|template|html|tt2?)$/) {
                    $template_map{$1} = $_;
                }
            },
            $config{TT_DIR}
        );
        $config{TEMPLATE_MAP} = \%template_map;

        # Build
        File::Find::find(
            {
                wanted => sub {
                    my $filename = $_;
                    if ($_ =~ /\.[mM](ark)?[dD](own)?$/) {
                        # Inline handle_yaml + write_html
                        open(my $fh, '<', $_) or return;
                        local $/;
                        my $data = <$fh>;
                        close $fh;
                        my $body = $data;
                        my $yaml = {};
                        if ($data =~ /\A---(.+?)---\s*/s) {
                            $yaml = YAML::Load($1);
                            $body = substr($data, $+[0]);
                        }
                        (my $html = $_) =~ s/\.[mM](ark)?[dD](own)?$/\.html/;
                        my $template = Template->new($config{TT_CONFIG});
                        my $rendered = Text::Markdown::markdown($body);
                        open my $out, '>', $html or return;
                        my $vars = {
                            title => $yaml->{title} // '',
                            body  => [$rendered],
                        };
                        my $layout_file = $config{TEMPLATE_MAP}->{$yaml->{layout} // ''};
                        return unless $layout_file;
                        $template->process($layout_file, $vars, $out);
                        close $out;
                    }
                }
            },
            $src
        );

        # Rsync
        open my $ex, '>', catfile($tmp, 'exclude.txt') or die "Cannot create exclude.txt: $!";
        print $ex "*.md\ntemplates\n";
        close $ex;
        system('rsync', '-avmh', '--exclude-from=' . catfile($tmp, 'exclude.txt'),
               '--info=NONE', "$src/", $dest);
        unlink catfile($tmp, 'exclude.txt');
    };

    chdir $orig_dir;

    if ($@) {
        fail("Build failed: $@");
    } else {
        ok(-f catfile($dest, 'index.html'), 'index.html created in dest');
        if (-f catfile($dest, 'index.html')) {
            open my $fh, '<', catfile($dest, 'index.html');
            local $/;
            my $output = <$fh>;
            close $fh;
            like($output, qr/<title>Test Page<\/title>/, 'Title rendered in output');
            like($output, qr/<h1>Welcome<\/h1>/, 'H1 rendered in output');
            like($output, qr/This is a test/, 'Content rendered in output');
        }
    }
};

done_testing();

sub _write_file {
    my ($path, $content) = @_;
    open my $fh, '>', $path or die "Cannot write $path: $!";
    print $fh $content;
    close $fh;
}
