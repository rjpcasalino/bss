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
no warnings "uninitialized";

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
my $manifest = "manifest.ini";
my $quit     = 0;
my $MD_EXT_RE = qr/\.[mM](ark)?[dD](own)?$/;

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

    print "bss: No manifest.ini found!" and exit unless -e $manifest;
    $manifest = Config::IniFiles->new( -file => "manifest.ini" );

    # Main config (gets passed around...)
    my %config = (
        TT_DIR =>
          realpath( $manifest->val( "build", "templates_dir" ) // "templates" ),
        SRC => $manifest->val( "build", "src" )
          // "src",    # TODO: disallow back/forward slashes
        DEST        => $manifest->val( "build", "dest" )        // "_site",
        ENCODING    => $manifest->val( "build", "encoding" )    // "UTF-8",
        COLLECTIONS => $manifest->val( "build", "collections" ) // undef,
        EXCLUDE => $manifest->val( "build",  "exclude" ) // "*.md, templates",
        EVAL_PERL => $manifest->val( "build",  "evaluate perl" ) // 0,
        PORT    => $manifest->val( "server", "port" )    // "9000",
        HOST    => $manifest->val( "server", "host" )    // "localhost"
    );


    # set template toolkit options
    $config{TT_CONFIG}->{INCLUDE_PATH} = $config{TT_DIR};
    $config{TT_CONFIG}->{ENCODING}     = $config{ENCODING};
    $config{TT_CONFIG}->{EVAL_PERL}    = $config{EVAL_PERL};
    $config{TT_CONFIG}->{PLUGINS}      = { Markdown => 'Markdown' };

    my $debug_tt_config = Dumper($config{TT_CONFIG});

    say qq{
	SRC: $config{SRC}
	DEST: $config{DEST}
	Excluding: $config{EXCLUDE}
	Encoding: $config{ENCODING}
	Template Toolkit Config: $debug_tt_config
	Server -
	 PORT:$config{PORT}
    } if $opts{verbose};

    mkdir( $config{DEST} ) unless -e $config{DEST};

    my @collections = split /,/, $config{COLLECTIONS};
    my %collections = ();
    for my $dir (@collections) {
        $collections{$dir} = [];
        find(
            sub {
                return if $_ eq "." or $_ eq "..";
                # FIXME: only picks up .md ext
                (my $name = $_) =~ s/$MD_EXT_RE/\.html/;
                push @{ $collections{$dir} }, $name;
            },
            File::Spec->catfile( $config{SRC}, $dir )
        );
        $config{COLLECTIONS} = \%collections;
    }

    # the actual build; note the sub and wanted here
    find(
        {
            wanted => sub { \&build(%config) }
        },
        $config{SRC}
    );

    # rsync is annoying...
    # easy to exclude things using a file, however.
    open my $exclude_fh, ">", "exclude.txt";
    my @excludes = split /,/, $config{EXCLUDE};
    for my $line (@excludes) {
        say $exclude_fh "$line";
    }

    # rsync info
    my $info_flags = "NONE";
    $info_flags = "ALL" if $opts{verbose};

    system "rsync", "-avmh", "--exclude-from=exclude.txt",
      "--info=$info_flags", $config{SRC},
      $config{DEST};

    # house cleaning
    unlink("exclude.txt");
    find(
        sub {
            if ( $_ =~ /.html$/ ) { unlink($_) }
        },
        $config{SRC}
    );

    say "Site created in $config{DEST}!";
    server(%config) if $opts{server};
}

sub build {
    my %config   = @_;
    my $filename = $_;
    if ( -d $filename ) {

        # FIXME
        if ( $_ =~ /$config{TT_DIR}/ ) {
            say "Ignoring: $File::Find::name" if $opts{verbose};
            $File::Find::prune = 1;
        }
    }
    elsif ( $_ =~ /$MD_EXT_RE/ ) {
        handle_yaml(%config);
    }
    elsif ( $_ =~ /\.png|\.jpg|\.jpeg|\.gif|\.svg$/i ) {
        # images are copied as-is by rsync
    }
}

sub handle_yaml {
    my %config = @_;
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
    write_html( $markdown, $yaml, $body, %config );
}

sub write_html {
    my ( $html, $yaml, $body, %config ) = @_;
    $html =~ s/$MD_EXT_RE/\.html/;

    my $template = Template->new( $config{TT_CONFIG} );

    my $rendered_body = markdown($body);
    open my $HTML, ">", $html;

    my $vars = {
        title         => $yaml->{title},
        body          => [$rendered_body],
        collections   => $config{COLLECTIONS},
    };

    # select layout (template)
    find(
	sub {
	    # see no warnings 'uninitialized';
	    if ( $_ =~ /$yaml->{layout}(.tmpl|.template|.html|.tt|.tt2)$/ ) {
		$yaml->{layout} = $_;
	    }
	},
	$config{TT_DIR}
    );
    # FIXME
    # seems slow; look into speeding up
    # takes 13 ~ seconds on 900MHz Intel
    $template->process( $yaml->{layout}, $vars, $HTML )
      or die $template->error();
    say "$yaml->{title} processed." if $opts{verbose};
}

sub server {
    my %config = @_;

    my $listen_socket = IO::Socket::INET->new(
        LocalPort => $config{PORT},
        Listen    => "SOMAXCONN",
        Reuse     => 1
    ) or die "Can't create listen socket: $!";
    say "Started local dev server on $config{PORT}!";

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
       -s, --server   serves config DEST
       -v, --verbose  gets talkative

=head1 DESCRIPTION

bss is a boring static site generator.
There isn't much to it. As such, beware!

=head1 LICENSE

This is released under the Artistic
License. See L<perlartistic>.
=cut
