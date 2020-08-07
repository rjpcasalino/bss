#!/usr/bin/env perl

# Discovery: a simple static site generator 
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

use strict;
use warnings;

use POSIX qw(strftime);
use Cwd;
use File::Find;
use File::Copy;
use File::Path qw(make_path remove_tree);
use Text::Markdown 'markdown';
use Template;
use Log::Dispatch;
use Log::Dispatch::File;
use Log::Dispatch::Screen;
use Getopt::Long qw(GetOptions);
use Pod::Usage qw(pod2usage);


my $debug;
my $help;
my $root_dir = getcwd;

## Parse options
GetOptions("HELP|help|h" => \$help, "DEBUG|debug|d" => \$debug) or pod2usage(2);
pod2usage(1) if $help;


## Log options
my $log = Log::Dispatch->new();

$log->add(
    Log::Dispatch::Screen->new(
        name      => "screen_debug",
        min_level => "debug",
    )
);

# TODO:
# only log to file on debug
sub llog {
	my ($oblig_msg) = @_;
	if (defined $debug) {
		$log->log(level => "debug", message => "DEBUG: $oblig_msg\n");
	} else {
		$log->log(level => "info", message => "INFO: $oblig_msg\n");
	}
}

my $time = localtime();
if ($debug) {
	$log->log(level => "debug", message => "!!!\tDEBUG MODE\t!!!\n");
	$log->log(level => "debug", message =>"$time\n");
}
main();

sub main {
	llog("Main init!");
	printf "Welcome!\n ? (e.g., info)\n";
	
	my $command = <STDIN>;
	if ($command =~ /start/i) {
		find(\&start, $root_dir);
	} elsif ($command =~ /info/i) {
		llog("someday there will be some info here.");
	}
	print "\n\tRemember!\n\tDon't give in!\n\tNever, never, never give in.\n\n\n...Goodbye and good luck!";
	exit;
}

my @posts;

sub writehtml {
	my $file = $_;
	my $config = {
	    INCLUDE_PATH => "/$root_dir/templates",  # or list ref
	    INTERPOLATE  => 1,               # expand "$var" in plain text
	    POST_CHOMP   => 1,               # cleanup whitespace
	    EVAL_PERL    => 1,               # evaluate Perl code blocks
	    RELATIVE => 1		     # used to indicate if templates specified with absolute filename
	};

	# create Template object
	my $template = Template->new($config);

	my $title;
	my @body;

	my $tmpl;
	# TODO: log and die prints to screen twice? why...
	open my $line, $file or $log->log_and_die(level => "warning", message => "$!");
	$file =~ s/\.md$/\.html/;
	open my $fh, ">", $file or die "open error: $!";
	my $site_modified = strftime '%c', localtime();
	while(<$line>) {
		if ($_ =~ /^:[tT]/) {
			$_ = join("", split(/:[tlTL]:/, $_));
			$_ =~ tr/:://d;
			llog("Title: $_");
			$title = $_;
		} elsif ($_ =~ /^:[lL]/) {
			$_ = join("", split(/:[tlTL]:/, $_));
			$_ =~ s/::/\.tmpl/;
			$tmpl = $_;
			$tmpl =~ s/^\s*(.*?)\s*$/$1/; # remove white space; ugly
			llog("Template: $_");
		} else {
			push(@body, markdown($_));
		}
	}

	
	my $vars = {
	    title  => $title,
	    # \@ notation will return a reference
	    body => \@body,
	    site_modified => $site_modified,
	    posts => \@posts
	};

	# process input template, substituting variables
	$template->process($tmpl, $vars, $fh)
		or die $template->error();
	
	# move this file and it's upper dir;
	#my $updir = File::Spec->updir();
	#llog($updir);
	#copy($updir, "/_site") or die "$!";
	# copy just file;
	#llog($template);
	#copy($template, "$root_dir/_site/") or die "$!";
}

sub start {
    my @site = make_path("$root_dir/_site/");
    if (-d $_ && $_ ne ".") { 
	    # ignore hidden dirs
	    llog("Sub-dir: $_");
	    # TODO: File::Spec into scalar 
	    if (File::Spec -> abs2rel($File::Find::name, $root_dir) =~ /^\./ or File::Spec -> abs2rel($File::Find::name, $root_dir) =~ /^_site/) {
	    	    llog("Ignoring: $File::Find::name"); # directory name
		    $File::Find::prune = 1;
	    }
    } elsif ($_ =~ /.md$/) {
	    writehtml($_);
    } elsif ($_ =~ /.png|.jpg|.jpeg|.gif|.svg$/i) {
	    llog("move to _site/static/imgs!");
    }
}

=head1 NAME

Discovery - A simple static site generator 

=head1 SYNOPSIS

discovery [options] [file ...]

     Options:
       --help     	 prints this help message
       --debug   	 DEBUG mode

    Commands:
    	start		 builds _site dir
	server		 builds _site dir and serves it
	stats            get some stats (e.g., how many pages)
