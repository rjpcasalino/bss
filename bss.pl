#!/usr/bin/env perl

# bss - boring static site generator
# Copyright (C) 2021,2022  Ryan Joseph Patrick Casalino
#
# This program is free software; you can redistribute it and/or modify it under
# the same terms as Perl itself.

# See http://www.perl.com/perl/misc/Artistic.html

use v5.36;
use strict;
use warnings;
use open qw( :std :encoding(UTF-8) );
use Time::HiRes qw(time);

# FIXME
# Template Toolkit is doing something strange
# I was getting these warnings:
# each on anonymous hash will always start from the beginning at /nix/store/longhash-perl5.36.0-Template-Toolkit-3.009/lib/perl5/site_perl/5.36.0/x86_64-linux-thread-multi/Template/Document.pm line 75.
# each on anonymous hash will always start from the beginning at /nix/store/longhash-perl5.36.0-Template-Toolkit-3.009/lib/perl5/site_perl/5.36.0/x86_64-linux-thread-multi/Template/Provider.pm line 376.
# each on anonymous hash will always start from the beginning at /nix/store/longhash-perl5.36.0-Template-Toolkit-3.009/lib/perl5/site_perl/5.36.0/x86_64-linux-thread-multi/Template/Provider.pm line 875.
# each on anonymous hash will always start from the beginning at /nix/store/longhash-perl5.36.0-Template-Toolkit-3.009/lib/perl5/site_perl/5.36.0/x86_64-linux-thread-multi/Template/Provider.pm line 894.
# the syntax below is cobbled together from answers on SO
# see: https://stackoverflow.com/questions/27556539/any-way-to-turn-off-warning-generated-in-use-module-statement-in-perl
# and: https://stackoverflow.com/questions/19490351/how-can-i-suppress-warnings-from-a-perl-function
# note that changing "require" to "use" will make the warning reappear
# also see: https://perldoc.perl.org/functions/use
BEGIN {
    local $SIG{__WARN__} = sub {};
    require Template;
}

use autodie;
use Config::IniFiles;
use Cwd qw(abs_path realpath);
use Data::Dumper;
use File::Find;
use File::Basename;
use File::Spec::Functions qw(catfile);
use FindBin qw($Bin);
use lib "$Bin/lib";
use Getopt::Long qw(GetOptions);
use IO::File;
use POSIX qw(setsid strftime);
use Pod::Usage qw(pod2usage);
use Text::Markdown qw(markdown);
use IO::Socket;
use Web;
use YAML;

my $script = File::Basename::basename($0);
my $SELF   = catfile( $FindBin::Bin, $script );

my ($cmd)    = @ARGV;
my %opts     = ( server => '', verbose => '', help => '');
my $manifest_ini = "manifest.ini";
my $quit     = 0;
my $MD_EXT_RE = qr/\.[mM](ark)?[dD](own)?$/;
my $build_id  = 0;

# Editor temp/swap files to ignore (vim .swp/.swo/~, emacs #file#/file~, etc.)
my $EDITOR_JUNK_RE = qr/(?:^\..*\.sw[a-p]$|~$|^4913$|^\#.*\#$)/;

$SIG{CHLD} = sub {
    while ( waitpid( -1, POSIX::WNOHANG ) > 0 ) { }
};

$SIG{INT} = sub { say "\nGoodbye!"; $quit++ };

GetOptions(
    \%opts, qw(
      server|s
      verbose|v
      help|h
      )
);

if ( !defined $cmd || $cmd !~ /^[bB]uild$/ ) {
    pod2usage(1);
}

do_build();

sub do_build {

    print "bss: No manifest.ini found!" and exit unless -e $manifest_ini;
    my $ini = Config::IniFiles->new( -file => "manifest.ini" );

    # Parsed manifest (gets passed around...)
    my %manifest = (
        TT_DIR =>
          realpath( $ini->val( "build", "templates_dir" ) // "templates" ),
        SRC => $ini->val( "build", "src" )
          // "src",    # TODO: disallow back/forward slashes
        DEST        => $ini->val( "build", "dest" )        // "_site",
        ENCODING    => $ini->val( "build", "encoding" )    // "UTF-8",
        COLLECTIONS => $ini->val( "build", "collections" ) // undef,
        EXCLUDE => $ini->val( "build",  "exclude" ) // "*.md, templates",
        # Security: EVAL_PERL allows arbitrary Perl in templates; only
        # enable for trusted template sources.
        EVAL_PERL => $ini->val( "build",  "evaluate perl" ) // 0,
        PORT    => $ini->val( "server", "port" )    // "9000",
        HOST    => $ini->val( "server", "host" )    // "localhost"
    );


    # set template toolkit options
    $manifest{TT_CONFIG}->{INCLUDE_PATH} = $manifest{TT_DIR};
    $manifest{TT_CONFIG}->{ENCODING}     = $manifest{ENCODING};
    $manifest{TT_CONFIG}->{EVAL_PERL}    = $manifest{EVAL_PERL};
    $manifest{TT_CONFIG}->{PLUGINS}      = { Markdown => 'Markdown' };

    my $debug_tt_manifest = Dumper($manifest{TT_CONFIG});

    say qq{
	SRC: $manifest{SRC}
	DEST: $manifest{DEST}
	Excluding: $manifest{EXCLUDE}
	Encoding: $manifest{ENCODING}
	Template Toolkit Config: $debug_tt_manifest
	Server -
	 PORT:$manifest{PORT}
    } if $opts{verbose};

    mkdir( $manifest{DEST} ) unless -e $manifest{DEST};

    # Run the initial build
    run_build(%manifest);

    say "Site created in $manifest{DEST}!";

    if ($opts{server}) {
        set_dev_mode(catfile($manifest{DEST}, '__bss_meta.json'), $manifest{SRC}, $manifest{TT_DIR});
        fork_watcher(%manifest);
        say "Watching $manifest{SRC} for changes...";
        server(%manifest);
    }
}

sub run_build {
    my %manifest    = @_;
    my $start_time = time();

    # Parse collections (re-scanned each build so new files are picked up)
    my @collections =
      defined( $manifest{COLLECTIONS} ) && !ref( $manifest{COLLECTIONS} )
      ? split( /,/, $manifest{COLLECTIONS} )
      : ();
    my %collections = ();
    for my $dir (@collections) {
        $dir =~ s/^\s+|\s+$//g;    # trim whitespace from collection names
        $collections{$dir} = [];
        find(
            sub {
                return unless -f $_;
                return if $_ =~ $EDITOR_JUNK_RE;
                return unless $_ =~ $MD_EXT_RE;
                ( my $name = $_ ) =~ s/$MD_EXT_RE/\.html/;
                push @{ $collections{$dir} }, $name;
            },
            File::Spec->catfile( $manifest{SRC}, $dir )
        );
    }
    $manifest{COLLECTIONS} = \%collections if @collections;

    # Pre-scan template directory to build a layout lookup table
    my %template_map;
    find(
        sub {
            return unless -f $_;
            if ( $_ =~ /^(.+)\.(tmpl|template|html|tt2?)$/ ) {
                $template_map{$1} = $_;
            }
        },
        $manifest{TT_DIR}
    );
    $manifest{TEMPLATE_MAP} = \%template_map;

    # the actual build
    find(
        {
            wanted => sub { build(%manifest) }
        },
        $manifest{SRC}
    );

    # rsync
    open my $exclude_fh, ">", "exclude.txt";
    my @excludes = split /,/, $manifest{EXCLUDE};
    for my $line (@excludes) {
        say $exclude_fh "$line";
    }
    close $exclude_fh;

    my $info_flags = "NONE";
    $info_flags = "ALL" if $opts{verbose};

    my $rsync_exit = system "rsync", "-avmh", "--exclude-from=exclude.txt",
      "--info=$info_flags", "$manifest{SRC}/",
      $manifest{DEST};
    warn "rsync exited with status $rsync_exit\n" if $rsync_exit != 0;

    # house cleaning
    unlink("exclude.txt");
    find(
        sub {
            if ( $_ =~ /.html$/ ) { unlink($_) }
        },
        $manifest{SRC}
    );

    # Gather stats and write build metadata
    my $elapsed_ms = int( ( time() - $start_time ) * 1000 );
    $build_id++;
    my ( $page_count, $file_count, $total_size ) =
      gather_site_stats( $manifest{DEST} );

    write_bss_meta(
        $manifest{DEST},
        {
            build_id         => $build_id,
            build_time       => strftime( "%Y-%m-%d %H:%M:%S", localtime() ),
            build_duration_ms => $elapsed_ms,
            page_count       => $page_count,
            file_count       => $file_count,
            total_size_bytes => $total_size,
        }
    );
}

sub gather_site_stats {
    my ($dest_dir) = @_;
    my ( $page_count, $file_count, $total_size ) = ( 0, 0, 0 );
    find(
        sub {
            return unless -f $_;
            return if $_ eq '__bss_meta.json';
            $file_count++;
            $total_size += -s $_;
            $page_count++ if /\.html$/;
        },
        $dest_dir
    );
    return ( $page_count, $file_count, $total_size );
}

sub write_bss_meta {
    my ( $dest, $stats ) = @_;
    my $meta_path = catfile( $dest, '__bss_meta.json' );
    open my $fh, ">", $meta_path;
    printf $fh "{\n";
    printf $fh "  \"build_id\": %d,\n",           $stats->{build_id};
    printf $fh "  \"build_time\": \"%s\",\n",      $stats->{build_time};
    printf $fh "  \"build_duration_ms\": %d,\n",   $stats->{build_duration_ms};
    printf $fh "  \"page_count\": %d,\n",           $stats->{page_count};
    printf $fh "  \"file_count\": %d,\n",           $stats->{file_count};
    printf $fh "  \"total_size_bytes\": %d\n",      $stats->{total_size_bytes};
    printf $fh "}\n";
    close $fh;
}

sub scan_src_mtimes {
    my ( $src_dir, $tt_dir ) = @_;
    my %mtimes;
    find(
        sub {
            return unless -f $_;
            return if /\.html$/;    # skip generated HTML
            return if $_ =~ $EDITOR_JUNK_RE;
            $mtimes{$File::Find::name} = ( stat($_) )[9];
        },
        $src_dir
    );
    if ( defined $tt_dir && -d $tt_dir ) {
        find(
            sub {
                return unless -f $_;
                return if $_ =~ $EDITOR_JUNK_RE;
                $mtimes{$File::Find::name} = ( stat($_) )[9];
            },
            $tt_dir
        );
    }
    return %mtimes;
}

sub has_changes {
    my ( $old_ref, $new_ref ) = @_;
    for my $file ( keys %$new_ref ) {
        return 1 unless exists $old_ref->{$file};
        return 1 if $new_ref->{$file} != $old_ref->{$file};
    }
    for my $file ( keys %$old_ref ) {
        return 1 unless exists $new_ref->{$file};
    }
    return 0;
}

sub fork_watcher {
    my %manifest = @_;

    defined( my $pid = fork() ) or die "Can't fork watcher: $!";

    if ( $pid == 0 ) {
        # Child process: watch for file changes and rebuild.
        # Create a new session so the child is fully detached from the
        # parent's controlling terminal, then redirect stdout/stderr to
        # /dev/null so rebuild output (including rsync) never leaks to
        # the parent terminal or other terminal windows.
        setsid();
        open STDOUT, '>', '/dev/null' or die "Can't redirect STDOUT: $!";
        open STDERR, '>', '/dev/null' or die "Can't redirect STDERR: $!";

        my %last_mtimes =
          scan_src_mtimes( $manifest{SRC}, $manifest{TT_DIR} );

        while ( !$quit ) {
            sleep 1;
            my %current =
              scan_src_mtimes( $manifest{SRC}, $manifest{TT_DIR} );
            if ( has_changes( \%last_mtimes, \%current ) ) {
                eval { run_build(%manifest) };
                %last_mtimes =
                  scan_src_mtimes( $manifest{SRC}, $manifest{TT_DIR} );
            }
        }
        exit 0;
    }
}

sub build {
    my %manifest   = @_;
    my $filename = $_;
    if ( -d $filename ) {
        my $resolved = abs_path($File::Find::name);
        if ( defined $resolved && $resolved eq $manifest{TT_DIR} ) {
            say "Ignoring: $File::Find::name" if $opts{verbose};
            $File::Find::prune = 1;
        }
    }
    elsif ( $_ =~ /$MD_EXT_RE/ ) {
        handle_yaml(%manifest);
    }
    elsif ( $_ =~ /\.(png|jpe?g|gif|svg)$/i ) {
        # images are copied as-is by rsync
    }
}

sub handle_yaml {
    my %manifest = @_;
    my $yaml;
    my $markdown = $_;
    open(my $MD, $markdown);

    local $/;
    my $data = <$MD>;
    close $MD;

    my $body = $data;
    if ( $data =~ /\A---(.+?)---\s*/s ) {
        $yaml = Load($1);
        $body = substr($data, $+[0]);
    }
    $yaml //= {};
    write_html( $markdown, $yaml, $body, %manifest );
}

sub write_html {
    my ( $html, $yaml, $body, %manifest ) = @_;
    $html =~ s/$MD_EXT_RE/\.html/;

    my $template = Template->new( $manifest{TT_CONFIG} );

    my $rendered_body = markdown($body);
    open my $HTML, ">", $html;

    my $vars = {
        title         => $yaml->{title} // '',
        body          => [$rendered_body],
        collections   => $manifest{COLLECTIONS},
    };

    # Resolve layout name to a template file via the pre-scanned map
    my $layout_name = $yaml->{layout} // '';
    my $layout_file = $manifest{TEMPLATE_MAP}->{$layout_name};
    unless ( defined $layout_file ) {
        warn "No template found for layout '$layout_name' in $html\n";
        close $HTML;
        return;
    }

    $template->process( $layout_file, $vars, $HTML )
      or die $template->error();
    my $title = $yaml->{title} // $html;
    say "$title processed." if $opts{verbose};
}

sub server {
    my %manifest = @_;

    my $listen_socket = IO::Socket::INET->new(
        LocalPort => $manifest{PORT},
        Listen    => "SOMAXCONN",
        Reuse     => 1
    ) or die "Can't create listen socket: $!";
    say "Started local dev server on $manifest{PORT}!";

    while ( !$quit ) {

        next unless my $connection = $listen_socket->accept;

        defined( my $child = fork() ) or die "Can't fork: $!";

        if ( $child == 0 ) {
            $listen_socket->close;
            handle_connection($connection);
            exit 0;
        }
        $connection->close;
    }
}
=head1 NAME

boring static site generator

=head1 SYNOPSIS

bss build [options]

     Options:
       -h, --help     display this help message
       -s, --server   serves manifest DEST
       -v, --verbose  gets talkative

=head1 DESCRIPTION

bss is a boring static site generator.
There isn't much to it. As such, beware!

=head1 LICENSE

This is released under the Artistic
License. See L<perlartistic>.
=cut
