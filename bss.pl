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

my $tt_config = {
    INCLUDE_PATH => "",  	     # or list ref
    INTERPOLATE  => 0,               # expand "$var" in plain text
    POST_CHOMP   => 1,               # cleanup whitespace
    EVAL_PERL    => 1,               # evaluate Perl code blocks
    RELATIVE => 1,    		     # used to indicate if templates specified with absolute filename
    ENCODING => ""
};

sub main {
	my $manifest = "manifest.ini";
	say "No manifest found!\n See README." and exit unless -e $manifest;
	
	# load manifest;
	$manifest = Config::IniFiles->new(-file => "manifest.ini");
	my ($src, $dest, $tt_dir, $watch, $exclude, $encoding, $port, $host, $greeting);
	$src = abs_path $manifest->val("build", "src");
	$dest = $manifest->val("build", "dest");
	mkdir($dest) unless -e $dest;
	$tt_dir = realpath $manifest->val("build", "templates_dir");
	$watch = $manifest->val("build", "watch");
	$exclude = $manifest->val("build", "exclude");
	$encoding = $manifest->val("build", "encoding");
	# server
	$port //= $manifest->val("server", "port") // "4000";
	$host //= $manifest->val("server", "host") // "localhost";

	$greeting = "Hello! Bonjour! Welcome!";

	say "$greeting\n
		Working in: $src
	     	Dest: $dest
	     	Layouts/Templates: $tt_dir
	     	Watch? $watch
	     	Excluding: $exclude
	     	Encoding: $encoding
		Server -
		 PORT:$port
		 HOST:$host" 
	if $Verbose;
	
	# set template toolkit options plus others
	# e.g., encoding
	$tt_config->{INCLUDE_PATH} = "$tt_dir";
	$tt_config->{ENCODING} = "$encoding";

	say "?";
	my $command = <STDIN>;
	if ($command =~ /build/i) {
		find(\&build, $src);
    		system "rm", "-rf", $dest;
		# TODO: read up on rsync filter rules
		system "rsync", "-avm", "--exclude=$exclude", $src, $dest;
		# rename src like one would see in apache /www/html...
		move "$dest/src", "$dest/www";
		## remove compiled *.html files; can ttoolkit do this itself?
		find(\&clean, $src);
		exit;
	} elsif ($command =~ /server/i) {
		# TODO
	}
	pod2usage(1);
}

sub writehtml {
	my $html = $_;
	$html =~ s/\.md$/\.html/;
	my $template = Template->new($tt_config);
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
	open my $HTML, ">:encoding($tt_config->{'ENCODING'})", $html;
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
	    writehtml($_, $tt_config);
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
