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

use Cwd;
use File::Find;
use Text::Markdown 'markdown';
use Template;
use Log::Dispatch;
use Log::Dispatch::File;
use Log::Dispatch::Screen;
use Getopt::Long qw(GetOptions);
use Pod::Usage qw(pod2usage);

my $log = Log::Dispatch->new();
$log->add(
    Log::Dispatch::File->new(
        name      => "logfile1",
        min_level => "debug",
        filename  => "logfile"
    )
);
$log->add(
    Log::Dispatch::Screen->new(
        name      => "screen",
        min_level => "warning",
    )
);

$log->add(
    Log::Dispatch::Screen->new(
        name      => "screen",
        min_level => "info",
    )
);
 
$log->log( level => "info", message => "Discovery Init\n" );

my $root_dir = getcwd;

my $debug;
my $help;

## Parse options
GetOptions("help|?" => \$help, "DEBUG|d" => \$debug) or pod2usage(2);
pod2usage(1) if $help;

main();

sub main {
	printf "Welcome!\n Enter a command.\n";
	if ($debug) {
		my $time = localtime();
		$log->debug("DEBUG: $time\n");
		$log->info("!DEBUG MODE!\n");
	}
	my $command = <STDIN>;
	if ($command =~ /^(s)tart/i) {
		find(\&start, $root_dir);
	}
	print "\n\tRemember!\n\tDon't give in!\n\tNever, never, never give in.\n\n\n...Goodbye and good luck!";
	exit;
}

sub writehtml {
	my $file = $_;
	my $config = {
	    INCLUDE_PATH => "/$root_dir/templates",  # or list ref
	    INTERPOLATE  => 1,               # expand "$var" in plain text
	    POST_CHOMP   => 1,               # cleanup whitespace
	    EVAL_PERL    => 1,               # evaluate Perl code blocks
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
	while(<$line>) {
		if ($_ =~ /^:[tl]:/i) {
			if ($_ =~ /^:[tT]/) {
				$_ = join("", split(/:[tlTL]:/, $_));
				$_ =~ tr/:://d;
				$title = $_;
				print "Title: $title";
			} elsif ($_ =~ /^:[lL]/) {
				$_ = join("", split(/:[tlTL]:/, $_));
				$_ =~ s/::/\.tmpl/;
				$tmpl = $_;
				$tmpl =~ s/^\s*(.*?)\s*$/$1/; # remove white space; ugly
				print "Template: $_";
			}
		} else {
			push(@body, markdown($_));
		}
	}
	
	my $vars = {
	    title  => $title,
	    # \@ notation will return a reference
	    body => \@body
	};

	# process input template, substituting variables
	$template->process($tmpl, $vars, $fh)
		or die $template->error();
}


sub start {
    if (-d $_ && $_ ne ".") { 
	    # ignore hidden dirs
	    $log->info("Sub-directory encountered: $_\n");
	    if (File::Spec -> abs2rel($File::Find::name, $root_dir) =~ /^\./) {
	    	    $log->info("Ignoring: $File::Find::name\n"); # directory name
		    $File::Find::prune = 1;
	    }
    } elsif ($_ =~ /.md$/) {
	    $log->info("Processing markdown: $_\n");
	    writehtml($_);
    }
}

=head1 NAME

Discovery - A simple static site generator 

=head1 SYNOPSIS

discovery [options] [file ...]

     Options:
       -help|-?|-HELP     prints this help message
       -d|D|DEBUG         DEBUG mode

    Commands:
    	start		 builds _site dir
	server		 builds _site dir and serves it
	stats            get some stats (e.g., how many pages)
