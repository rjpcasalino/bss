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

=head1 NAME

boring static site generator

=head1 SYNOPSIS

bss build [options]

     Options:
       --help     	 display this help message
       --server		 serves DEST dir
       --verbose     	 gets talkative
       --watch		 watches SRC dir for changes
=cut

use v5.10;

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
use POSIX qw(strftime);
use Pod::Usage qw(pod2usage);
use Text::Markdown qw(markdown);
use Template;
use IO::Socket;
use Web;
use YAML;

my $script = File::Basename::basename($0);
my $SELF   = catfile( $FindBin::Bin, $script );

my ($cmd) = @ARGV;
my %opts = ( server => '', verbose => '', help => '' );
my $manifest = "manifest.ini";

GetOptions(
    \%opts, qw(
      server
      verbose
      help
      watch
      )
);

$SIG{INT} = sub {
    @ARGV = qw(build --server --watch);

    #exec($SELF, @ARGV) or die "$0: couldn't restart: $!";
};

do_build() if defined $cmd and $cmd =~ /[bB]uild/ or die pod2usage(1);

pod2usage(1) if $opts{help};

sub do_build {

	$manifest = Config::IniFiles->new( -file => "manifest.ini" );

	# Main config (gets passed around...)
	my %config = (
	    TT_CONFIG => \%tt_config,
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
		Watch: $opts{watch}
		Server -
		 PORT:$config{PORT}
	 } if $opts{verbose};
	 
	mkdir( $config{DEST} ) unless -e $config{DEST};
	
	# FIXME: rm -rf seems like a bad idea
    	system "rm", "-rf", $config{DEST};
	@collections = split /,/, $config{COLLECTIONS};
	my %collections = ();
	for my $dir (@collections) {
		# push an empty list into some hash:
		push( @{ $collections{$dir} }, () );
		find(
		    sub {
			next if $_ eq "." or $_ eq "..";

			# FIXME: only picks up .md ext
			$_ =~ s/\.md$/\.html/;
			push @{ $collections{$dir} }, $_;
		    },
		    File::Spec->catfile( $config{SRC}, $dir )
		);
        $config{COLLECTIONS} = \%collections;
    }

    # the actual build; note the sub and wanted here
    find( { wanted => sub { \&build(%config) } }, $config{SRC} );

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

    say "Site created in $config{DEST}!";
    server(%config)     if $opts{server};
}

sub build {
    my %config = @_;
    my $filename = $_;
    if ( -d $filename ) {

        # FIXME
        if ( $_ =~ /$config{TT_DIR}/ ) {
            say "Ignoring: $File::Find::name" if $opts{verbose};
            $File::Find::prune = 1;
        }
    }
    elsif ( $_ =~ /.md$/ ) {
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
    open $MD, $markdown;
    undef $/;
    my $data = <$MD>;
    if ( $data =~ /---(.+)---/s ) {
        $yaml = Load($1);
    }
    write_html( $markdown, $yaml, %config );
}

sub write_html {
    my ( $html, $yaml, %config ) = @_;
    $html =~ s/\.md$/\.html/;

    my $template = Template->new( $config{TT_CONFIG} );
    my @body;

    open $MD, $_;
    while (<$MD>) {

        # FIXME
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
    find(
        sub {
            if ( $_ =~ /$yaml->{layout}(.tmpl|.template|.html|.tt|.tt2)$/ )
	    {
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
    my $port = $config{PORT};

    # FIXME:
    #  IO::Socket::INET, when waiting for the network,
    #  will block the whole process - that means all
    #  threads, which is clearly undesirable
    my $socket = IO::Socket::INET->new(
        LocalPort => $port,
        Listen    => SOMAXCONN,
        Reuse     => 1
    ) or die "Can't create listen socket: $!";
    say "Started local dev server on $port!";
    say "Watching..." if $opts{watch};

    #if ( $opts{watch} ) {
    #        my $watcher =
    #        File::ChangeNotify->instantiate_watcher
    #        ( directories => [ realpath( $config{SRC} ) ] );

    #        printf "Watching %s for changes\n", realpath( $config{SRC} );
    #        if ( my @events = $watcher->wait_for_events ) {
    #    	    foreach my $event (@events) {
    #    		    if ( $event->path =~ /.md$/ ) {
    #    			say "Markdown file changed!";
    #    		}
    #    	}
    #        }
    #}
    while ( my $c = $socket->accept ) {
        handle_connection($c);
        close $c;
    }
    close $socket;
}
