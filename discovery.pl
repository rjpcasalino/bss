#!/usr/bin/env perl
# NOTES: 
# (on perl)
# getting tripped up regarding scope
# need to read more on `my` and `local`

use strict;
use warnings;

use Cwd;
use Text::Markdown 'markdown';

my $build;
my $dir = getcwd;
my $mode;

init(@ARGV);

sub init {
	if (defined $ARGV[0] && $ARGV[0] =~ /^--d/i) {
		$mode = "DEBUG";
	} else {
		$mode = "NORMAL";
	}

	if ($mode eq "DEBUG") {
		printf "MODE: %s\n", $mode;
		printf "Working in: %s\n", $dir;
		my $time = localtime();
		print "Local time: $time\n\n";
		# TODO: 
		# log format switch 
	} elsif ($mode eq "NORMAL") {
		printf "MODE: %s\n", $mode;
		printf "Working in: %s\n", $dir;
	} 
	
	printf "Welcome!\n Enter a command. (hint: H or h gives help)\n";
	my $answer = <STDIN>;
	if ($answer =~ /^h/i) {
		# TODO: 
		# create man page with troff and gzip it to store in /usr/share/man
		open (MAN, "| man discovery");
		close MAN;
		die;
	} elsif ($answer =~ /^s/i) {
		print "Starting Discovery...\n";
		start($dir);
	}
	print "Remember, don't give in!\nNever, never, never give in.\nGoodbye and good luck!";
	die;
}

sub writehtml {
	my @file = @_;
	# TODO:
	# understand diffs between these two open calls
	# is my $line really a line? It's a GLOB?
	open my $line, $file[0] or die "open error: $!";
	$file[0] =~ s/\.md$/\.html/;
	open my $fh, ">", $file[0] or die "open error: $!";
	while(<$line>) {
		if ($_ =~ /^:[tl]:/i) {
			if ($_ =~ /^:[tT]/) {
				print "Title is: $_";
			} elsif ($_ =~ /^:[lL]/) {
		   		print "Layout is: $_";
			} 
			$_ = join("", split(/:[tlTL]:/, $_));
			$_ =~ tr/:://d;
			# TODO: use title and layout in template...
	  	} else {
		  	my $html = markdown($_);
		  	print {$fh} $html;
	  	}
  	}
}

my @dirs;
sub survey {
	my $file = @_;
	foreach $file (<*>) {
		if (-d $file && $file ne "." && $file ne "..") {
      			push(@dirs, $file);
    		} elsif ($file =~ /\.md$/) {
			writehtml($file);
		}
	}
}

sub start {
	opendir my $dh, $_[0] or die "opendir error ($_[0]): $!";
	my @files = readdir $dh;
	survey();
	foreach $dir (@dirs) {
		chdir($dir);
		my @files = readdir $dh;
		survey();
		# important!
		chdir "..";
	}
}
