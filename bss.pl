#!/usr/bin/env perl

# bss - a simple static site generator 
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
#

use v5.10;

use feature 'say';
use autodie;
use Config::IniFiles;
use Cwd qw(abs_path realpath);
use POSIX qw(strftime);
use File::Find;
use File::Copy qw(move);
use File::Basename;
use File::Path qw(make_path remove_tree);
use Getopt::Long qw(GetOptions);
use IO::File;
use POSIX qw(strftime);
use Pod::Usage qw(pod2usage);
use Text::Markdown qw(markdown);
use Template;

my $Verbose = $ENV{VERBOSE} // 0;
my $help;

GetOptions("HELP|help|h" => \$help) or pod2usage(2);
pod2usage(1) if $help;

my $manifest = "manifest.ini";
say "No manifest found!\n See README." and exit unless -e $manifest;

my $tt_config = {
    INCLUDE_PATH => "",  	     # or list ref
    INTERPOLATE  => 0,               # expand "$var" in plain text
    POST_CHOMP   => 1,               # cleanup whitespace
    EVAL_PERL    => 1,               # evaluate Perl code blocks
    RELATIVE => 1,    		     # used to indicate if templates specified with absolute filename
    ENCODING => ""
};

# load manifest;
$manifest = Config::IniFiles->new(-file => "manifest.ini");
my %config = (
	TT_CONFIG => $tt_config,
	TT_DIR => (realpath $manifest->val("build", "templates_dir")),
	SRC => (abs_path $manifest->val("build", "src")),
	DEST => $manifest->val("build", "dest"),
	ENCODING => $manifest->val("build", "encoding"),
	COLLECTIONS => $manifest->val("build", "collections"),
	WATCH => $manifest->val("build", "watch"),
	EXCLUDE => $manifest->val("build", "exclude"),
	PORT => $manifest->val("server", "port") // "4000",
	HOST => $manifest->val("server", "host") // "localhost"
);

sub main {
	mkdir($config{DEST}) unless -e $config{DEST};
	# set template toolkit options
	$config{TT_CONFIG}->{INCLUDE_PATH} = $config{TT_DIR};
	
	foreach $key (sort keys %config) {
		$value = $config{$key};
		say "$key => $value" if $Verbose;
	}

	$greeting = "hello! bonjour! welcome!";
	say "
		$greeting
		Working in: $config{SRC}
	     	Dest: $config{DEST}
	     	Layouts/Templates: $config{TT_DIR}
	     	Watch? $config{WATCH}
	     	Excluding: $config{EXCLUDE}
	     	Encoding: $config{ENCODING}
		Server -
		 PORT:$config{PORT}
		 HOST:$config{HOST}
		 "
	if $Verbose;
	
	say "?";
	my $command = <STDIN>;
	if ($command =~ /build/i) {
		find(\&build, $config{SRC});
    		system "rm", "-rf", $config{DEST};
		# TODO: read up on rsync filter rules
		system "rsync", "-avm", "--exclude=$config{EXCLUDE}", $config{SRC}, $config{DEST};
		move "$config{DEST}/src", "$config{DEST}/www";
		## remove compiled *.html files; can ttoolkit do this itself?
		find(\&clean, $config{SRC});
		exit;
	} elsif ($command =~ /server/i) {
		# TODO
	}
	pod2usage(1);
}

sub writehtml {
	my ($html, %config) = @_;
	$html =~ s/\.md$/\.html/;
	my $template = Template->new($config{TT_CONFIG});
	my $layout; 

	my $title;
	my @body;

	open $MD, $_;
	while(<$MD>) {
		if ($_ =~ /^:[tT]/) {
			$_ = join("", split(/:[tlTL]:/, $_));
			$_ =~ tr/:://d;
			say "Title: $_" if $Verbose;
			$title = $_;
		} elsif ($_ =~ /^:[lL]/) {
			$_ = join("", split(/:[tlTL]:/, $_));
			$_ =~ s/::/\.tmpl/;
			$layout = $_;
			$layout =~ s/^\s*(.*?)\s*$/$1/; # TODO: remove; use LP 7th ed
			say "Layout $_" if $Verbose;
		} else {
			push(@body, markdown($_));
		}
	}
	open my $HTML, ">:encoding($config{ENCODING})", $html;
	my $site_modified = strftime '%c', localtime();
	
	my $vars = {
	    title  => $title,
	    body => \@body,
	    site_modified => $site_modified
	};
	
	$template->process($layout, $vars, $HTML)
		or die $template->error();
}

sub build {
    my $filename = $_;
    if (-d $filename) { 
	    # ignore these dirs always:
	    if ($_ =~ /^_site|^templates/) {
	    	    say "Ignoring: $File::Find::name" if $Verbose; # directory name
		    $File::Find::prune = 1;
	    }
    } elsif ($_ =~ /.md$/) {
	    writehtml($_, %config);
    } elsif ($_ =~ /.png|.jpg|.jpeg|.gif|.svg$/i) {
	    # TODO
    }
}

sub clean {
    my $filename = $_;
    if (-d $filename) { 
	    if ($_ =~ /^_site|^templates/) {
	    	    say "Unlinking: $File::Find::name" if $Verbose;
		    $File::Find::prune = 1;
	    }
    } elsif ($_ =~ /.html$/) {
    	unlink($_);
    }
}

main();

=head1 NAME

boring static site generator - a simple static site generator 

=head1 SYNOPSIS

[env] bss [options] [file ...]

     Options:
       --help     	 prints this help message

    Commands:
    	build		 builds _site dir
	server		 builds _site dir and serves it
