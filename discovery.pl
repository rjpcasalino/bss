#!/usr/env perl

use strict;
use warnings;

use Cwd;
use Text::Markdown 'markdown';
my $dir = getcwd;
my $mode;
my $file;

init(@ARGV);
sub init {
	if (defined($ARGV[0]) && $ARGV[0] =~ /^--d/i) {
		$mode = "DEBUG";
	} else {
		$mode = "NORMAL";
	}

	if ($mode eq "DEBUG") {
		printf "MODE: %s\n", $mode;
		printf "Working in: %s\n", $dir;
		my $time = localtime();
		print "Local time: $time\n\n";
		start($dir)
	} elsif ($mode eq "NORMAL" && defined($ARGV[0]) && $ARGV[0] =~ /start/i) {
		start($dir)
	} else {
		printf "Welcome!\n Enter a command. (hint: H or h gives help)\n";
		my $answer = <STDIN>;
		if ($answer =~ /^h/i) {
			# TODO: create man page with troff and gzip it
			# and store in /usr/share/man
			open (MAN, "| man discovery");
			close MAN;
			return 0;
		} elsif ($answer =~ /^ping/i) {
			open (PING, "|ping boringtranquility.io");
			close PING;
		}
	}
	print "Goodbye!";
}

sub writehtml {
	my @file = @_;
	open my $info, $file[0] or die "Could not open: $!";
	while(my $line = <$info>)  {
		my $html = markdown($line);
		print $html;
	}
}

sub start {
	opendir my $dh, $_[0] or die "Failed to open $_[0]: $!";
	my @dirs;
	my @files = readdir $dh;
	foreach $file (<*>) {
		print "$file\n";
		if (-d $file && $file ne "." && $file ne "..") {
      			push(@dirs, $file);
    		} elsif ($file =~ /\.md$/) {
			writehtml($file);
		}
	}
	foreach $dir (@dirs) {
		chdir($dir);
		my @files = readdir $dh;
		foreach $file (<*>) {
			if (-d $file && $file ne "." && $file ne "..") {
				push(@dirs, $file);
			} elsif ($file =~ /\.md$/) {
				writehtml($file);
			}
		}
	}
}

format STDOUT_TOP = 
Discovery v0.01
Copyright Ryan Casalino, 2020
.
