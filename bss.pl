#!/usr/bin/env perl

# bss - boring static site generator
# Copyright (C) 2021  Ryan Joseph Patrick Casalino
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

use v5.32;

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
use Template;
use IO::Socket;
use Web;
use YAML;

my $script = File::Basename::basename($0);
my $SELF   = catfile( $FindBin::Bin, $script );

my ($cmd)    = @ARGV;
my %opts     = ( server => '', verbose => '', help => '');
my $manifest = "manifest.ini";
my $quit     = 0;

$SIG{CHLD} = sub {
    while ( waitpid( -1, "WNOHANG" ) > 0 ) { }
};
$SIG{INT} = sub { say "Goodbye!"; sleep 1; $quit++ };

GetOptions(
    \%opts, qw(
      server
      verbose
      help
      )
);

do_build() if defined $cmd and $cmd =~ /[bB]uild/ or die pod2usage(1);

pod2usage(1) if $opts{help};

sub do_build {

    print "bss: No manifest.ini found!" and exit unless -e $manifest;
    $manifest = Config::IniFiles->new( -file => "manifest.ini" );

    # Main config (gets passed around...)
    my %config = (
        TT_CONFIG => \my %tt_config,
        TT_DIR =>
          realpath( $manifest->val( "build", "templates_dir" ) // "templates" ),
        SRC => $manifest->val( "build", "src" )
          // "src",    # TODO: disallow back/forward slashes
        DEST        => $manifest->val( "build", "dest" )        // "_site",
        ENCODING    => $manifest->val( "build", "encoding" )    // "UTF-8",
        COLLECTIONS => $manifest->val( "build", "collections" ) // undef,
        EXCLUDE => $manifest->val( "build",  "exclude" ) // "*.md, templates",
        PORT    => $manifest->val( "server", "port" )    // "9000",
        HOST    => $manifest->val( "server", "host" )    // "localhost"
    );

    # Template Toolkit #
    my $tt_config = {
        INCLUDE_PATH => undef,
        INTERPOLATE  => 1,
        EVAL_PERL    => 1,
        RELATIVE     => 1,
        ENCODING     => undef
    };

    # set template toolkit options
    $config{TT_CONFIG}->{INCLUDE_PATH} = $config{TT_DIR};
    $config{TT_CONFIG}->{ENCODING}     = $config{ENCODING};

    say qq{
	SRC: $config{SRC}
	DEST: $config{DEST}
	Excluding: $config{EXCLUDE}
	Encoding: $config{ENCODING}
	Server -
	 PORT:$config{PORT}
    } if $opts{verbose};

    mkdir( $config{DEST} ) unless -e $config{DEST};

    system "rm", "-rf", $config{DEST};
    my @collections = split /,/, $config{COLLECTIONS};
    my %collections = ();
    for my $dir (@collections) {

        # push an empty list into some hash:
        push( @{ $collections{$dir} }, () );
        find(
            sub {
                next if $_ eq "." or $_ eq "..";

                # FIXME: only picks up .md ext
                $_ =~ s/\.[mM](ark)?[dD](own)?$/\.html/;
                push @{ $collections{$dir} }, $_;
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
    elsif ( $_ =~ /.[mM](ark)?[dD](own)?$/ ) {
        handle_yaml(%config);
    }
    elsif ( $_ =~ /.png|.jpg|.jpeg|.gif|.svg$/i ) {

        # TODO
    }
}

sub handle_yaml {
    my %config = @_;
    my $yaml;
    my $markdown = $_;
    open my $MD, $markdown;

    undef $/;
    my $data = <$MD>;
    if ( $data =~ /---(.+)---/s ) {
        $yaml = Load($1);
    }
    write_html( $markdown, $yaml, %config );
}

sub write_html {
    my ( $html, $yaml, %config ) = @_;
    $html =~ s/\.[mM](ark)?[dD](own)?$/\.html/;

    my $template = Template->new( $config{TT_CONFIG} );
    my @body;

    open my $MD, $_;
    while (<$MD>) {

        # FIXME:
        # hacky way to get rid of the YAML
        # block. That should be gone before
        # this...alas, here we are...
        if ( $_ =~ /(---(.+)---)/s ) {
            s/$1//g;
        }
        push( @body, markdown($_) );
    }
    open my $HTML, ">", $html;

    my $site_modified = strftime '%c', localtime();

    my $vars = {
        title         => $yaml->{title},
        body          => \@body,
        collections   => $config{COLLECTIONS},
        site_modified => $site_modified,
    };

    # select layout (template)
    find(
        sub {
            if ( $_ =~ /$yaml->{layout}(.tmpl|.template|.html|.tt|.tt2)$/ ) {
                $yaml->{layout} = $_;
            }
        },
        $config{TT_DIR}
    );
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
       --help     display this help message
       --server   serves config DEST
       --verbose  gets talkative

=head1 DESCRIPTION

bss is a boring static site generator.
There isn't much to it. As such, beware!

=head1 LICENSE

This is released under the Artistic
License. See L<perlartistic>.
=cut
