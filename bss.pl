#!/usr/bin/env perl

# bss - boring static site generator
# Copyright (C) 2020  Ryan Joseph Patrick Casalino
#

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

use v5.10;

use autodie;
use Config::IniFiles;
use Cwd qw(abs_path realpath);
use Data::Dumper;
use File::Find;
use File::Basename;
use FindBin qw($Bin);
use lib "$Bin/lib";
use Getopt::Long qw(GetOptions);
use IO::File;
use POSIX qw(strftime);
use Pod::Usage qw(pod2usage);
use Text::Markdown qw(markdown);
use Template;
use IO::Socket;
use Web;

my $manifest = "manifest.ini";
say "No manifest.ini found!" and exit unless -e $manifest;

$manifest = Config::IniFiles->new( -file => "manifest.ini" );
my %config = (
    TT_CONFIG => \%tt_config,
    TT_DIR =>
      realpath( $manifest->val( "build", "templates_dir" ) // "templates" ),
    SRC => $manifest->val( "build", "src" )
      // "src",    # TODO: disallow back/forward slashes
    DEST        => $manifest->val( "build", "dest" )        // "_site",
    ENCODING    => $manifest->val( "build", "encoding" )    // "UTF-8",
    COLLECTIONS => $manifest->val( "build", "collections" ) // undef,
    WATCH       => $manifest->val( "build", "watch" )       // "false",
    EXCLUDE => $manifest->val( "build",  "exclude" ) // "*.md, templates",
    PORT    => $manifest->val( "server", "port" )    // "9000",
    HOST    => $manifest->val( "server", "host" )    // "localhost"
);

# TEMPLATE TOOLKIT #
my $tt_config = {
    INCLUDE_PATH => undef,
    INTERPOLATE  => 0,
    POST_CHOMP   => 1,
    EVAL_PERL    => 1,
    RELATIVE     => 1,
    ENCODING     => undef
};

mkdir( $config{DEST} ) unless -e $config{DEST};

# set template toolkit options
$config{TT_CONFIG}->{INCLUDE_PATH} = $config{TT_DIR};
$config{TT_CONFIG}->{ENCODING}     = $config{ENCODING};

# TODO: build is a command not an option. server as well?
# also don't forget about 'watch'
my %opts = ( build => '', server => '', verbose => '', help => '' );

GetOptions(
    \%opts, qw(
      build
      verbose
      help
      server
      watch
      )
);

do_build(%config) if $opts{build};
server()          if $opts{server};

pod2usage(1) if $opts{help};

say "--manifest--" if $opts{verbose};
foreach $key ( sort keys %config ) {
    $value = $config{$key};
    say "$key: $value" if $opts{verbose};
}

$greetings = "Hello!\t Bonjour!\t Welcome!\t ひ!\t\n";
say "
	$greetings
	SRC: $config{SRC}
	DEST: $config{DEST}
	Excluding: $config{EXCLUDE}
	Encoding: $config{ENCODING}
	Server -
	 PORT:$config{PORT}
	 "
  if $opts{verbose};

sub do_build {
    system "rm", "-rf", $config{DEST};
    @collections = split /,/, $config{COLLECTIONS};
    my %collections = ();
    for my $dir (@collections) {

        # this pushes an empty list into the hash...
        push( @{ $collections{$dir} }, () );
        find(
            sub {
                next if $_ eq "." or $_ eq "..";
                push @{ $collections{$dir} }, $_;
            },
            File::Spec->catfile( $config{SRC}, $dir )
        );
        $config{COLLECTIONS} = \%collections;
    }
    find( \&build, $config{SRC} );
    open my $exclude_fh, ">", "exclude.txt";
    @excludes = split /,/, $config{EXCLUDE};
    for $line (@excludes) {
        say $exclude_fh "$line";
    }
    system "rsync", "-avmh", "--exclude-from=exclude.txt", $config{SRC},
      $config{DEST};

    # house cleaning
    unlink("exclude.txt");
    find(
        sub {
            if ( $_ =~ /.html$/ ) { unlink($_) }
        },
        $config{SRC}
    );

    # thanks for stopping by!
    say "Site created in $config{DEST}!";
    1;
}

sub server {
    my $port   = $config{PORT};
    my $socket = IO::Socket::INET->new(
        LocalPort => $port,
        Listen    => SOMAXCONN,
        Reuse     => 1
    ) or die "Can't create listen socket: $!";
    say "Started local dev server on $port!";
    while ( my $c = $socket->accept ) {
        handle_connection($c);
        close $c;
    }
    close $socket;
}

sub handleYAML {
    use YAML;
    my $yaml;
    open $MD, $_;
    undef $/;
    my $data = <$MD>;
    if ( $data =~ /---(.+)---/s ) {
        $yaml = Load($1);
    }
    writehtml( $_, $yaml );
}

sub writehtml {
    my ( $html, $yaml ) = @_;
    $html =~ s/\.md$/\.html/;

    my $template = Template->new( $config{TT_CONFIG} );
    my $layout;
    my @body;

    open $MD, $_;
    while (<$MD>) {

        # remove YAML block
        # FIXME
        # this just subs in blank lines, which we do not want
        if ( $_ =~ /(---(.+)---)/s ) {
            s/$1//g;
        }
        push( @body, markdown($_) );
    }
    open my $HTML, ">", $html;

    my $site_modified = strftime '%c', localtime();

    # my $page_modified;

    my $vars = {
        title         => $yaml->{title},
        body          => \@body,
        collections   => $config{COLLECTIONS},
        site_modified => $site_modified,
    };

    $template->process( "$yaml->{layout}.tmpl", $vars, $HTML )
      or die $template->error();
    say "$yaml->{title} processed." if $opts{verbose};
}

sub build {
    my $filename = $_;
    if ( -d $filename ) {

        # ignore these dirs always:
        # FIXME
        if ( $_ =~ /^$config{SRC}|^$config{TT_DIR}/ ) {
            say "Ignoring: $File::Find::name" if $opts{verbose};
            $File::Find::prune = 1;
        }
    }
    elsif ( $_ =~ /.md$/ ) {
        handleYAML();
    }
    elsif ( $_ =~ /.png|.jpg|.jpeg|.gif|.svg$/i ) {

        # TODO
    }
}

=head1 NAME

boring static site generator

=head1 SYNOPSIS

[env] bss [options] [command]

     Options:
       --help     	 prints this help message
       --verbose     	 gets talkative
       --build		 builds _site dir
       --server		 builds _site dir and serves it
