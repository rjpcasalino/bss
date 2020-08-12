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
package bss;

use strict;
use warnings;
use feature 'say';

use autodie;
use Config::IniFiles;
use Cwd;
use POSIX qw(strftime);
use File::Find;
use File::Copy qw(move);
use File::Basename;
use File::Path qw(make_path remove_tree);
use Getopt::Long qw(GetOptions);
use Log::Dispatch;
use Log::Dispatch::File;
use Log::Dispatch::Screen;
use POSIX qw(strftime);
use Pod::Usage qw(pod2usage);
use Text::Markdown 'markdown';
use Template;
use base qw(HTTP::Server::Simple::CGI);

my $debug;
my $help;

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
	my ($msg) = @_;
	if (defined $debug) {
		my $time = localtime();
		$log->log(level => "debug", message => "DEBUG $time: $msg\n");
	} else {
		$log->log(level => "info", message => "INFO: $msg\n");
	}
}

if ($debug) {
	$log->log(level => "debug", message => "!!!\tDEBUG MODE\t!!!\n");
}

my $tt_config = {
    INCLUDE_PATH => "",  # or list ref
    INTERPOLATE  => 0,               # expand "$var" in plain text
    POST_CHOMP   => 1,               # cleanup whitespace
    EVAL_PERL    => 1,               # evaluate Perl code blocks
    RELATIVE => 1		     # used to indicate if templates specified with absolute filename
};

sub handle_request {
	my ($self, $cgi) = @_;
	my $method = $ENV{REQUEST_METHOD};
	my $timestamp = time();
	if (lc($method) eq 'post') {
		print "Received POST request at $timestamp";
	}
	else {
		print "Good night or good morning? $timestamp";
	}
}

main();

sub main {
	my $manifest = "manifest.ini";
	say "No manifest found!\n See README" and exit unless -e $manifest;
	
	# load manifest;
	$manifest = Config::IniFiles->new( -file => "manifest.ini" );
	
	my $src = File::Spec->rel2abs($manifest->val("build", "src"));
	my $dest = File::Spec->rel2abs($manifest->val("build", "dest"));
	my $tt_dir = $manifest->val("build", "templates_dir");
	my $watch = $manifest->val("build", "watch");
	say "Welcome!\nWorking in: $src\nDest: $dest";
	say "Layouts/Templates: $src/$tt_dir";
	say "Watch? $watch";
	# set template toolkit PATH 
	$tt_config->{INCLUDE_PATH} = "$src/$tt_dir";

	# server
	my $port = $manifest->val("server", "port");
	my $host = $manifest->val("server", "host");
	say "PORT: $port";
	say "HOST: $host";
	
	say "?";
	my $command = <STDIN>;
	if ($command =~ /build/i) {
		find(\&build, $src);
		# TODO: maybe a bad idea?
    		!system "rm -rf $dest && rsync -arv --exclude='*.md' --exclude='$tt_dir' $src $dest" or die "system error: $!";
		# rename src
		move "$dest/src", "$dest/www";
		exit;
	} elsif ($command =~ /server/i) {
		my $server = bss->new($port);
		$server->run();
	}
	pod2usage(1);
	say "\n\tRemember!\n\tDon't give in!\n\tNever, never, never give in.";
}

sub writehtml {
	my $markdown = $_;
	# create Template object
	my $template = Template->new($tt_config);

	my $title;
	my @body;

	my $tmpl;
	# TODO: log and die prints to screen twice? why...
	open my $line, $markdown or $log->log_and_die(level => "warning", message => "$!");
	$markdown =~ s/\.md$/\.html/;
	my $html = $markdown;
	# TODO: utf-8 file encoding...
	open my $FH, ">", $html or die "open error: $!";
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
	    site_modified => $site_modified
	};

	# process input template, substituting variables
	$template->process($tmpl, $vars, $FH)
		or die $template->error();
}

sub build {
    my $filename = $_;
    if (-d $filename) { 
	    # ignore certain dirs
	    if ($_ =~ /^_site/ or $_ =~ /^templates/) {
	    	    llog("Ignoring: $File::Find::name"); # directory name
		    $File::Find::prune = 1;
	    }
    } elsif ($_ =~ /.md$/) {
	    writehtml($_, $tt_config);
    } elsif ($_ =~ /.png|.jpg|.jpeg|.gif|.svg$/i) {
	    llog("TODO: move img files to _site/static/imgs!");
    }
}

=head1 NAME

boring static site generator - a simple static site generator 

=head1 SYNOPSIS

bss [options] [file ...]

     Options:
       --help     	 prints this help message
       --debug   	 DEBUG mode

    Commands:
    	build		 builds _site dir
	serve		 builds _site dir and serves it
