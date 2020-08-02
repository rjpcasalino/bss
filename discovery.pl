#!/usr/bin/env perl

use strict;
use warnings;

use Cwd;
use File::Find;
use Text::Markdown 'markdown';
use Template;

my $root_dir = getcwd;
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
		printf "Working in: %s\n", getcwd;
		my $time = localtime();
		print "Local time: $time\n\n";
		# TODO: 
		# log format switch 
	} elsif ($mode eq "NORMAL") {
		printf "MODE: %s\n", $mode;
		printf "Working in: %s\n", getcwd;
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
		find(\&start, $root_dir);
	}
	print "Remember, don't give in!\nNever, never, never give in.\nGoodbye and good luck!";
	die;
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
	print "$file";

	open my $line, $file or die "open error: $!";
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
				$tmpl =~ s/^\s*(.*?)\s*$/$1/;
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
	$template->process($tmpl, $vars)
		or die $template->error();
}


sub start {
    # Name of the file (without path information)
    print "$_\n"; 
    if (-d $_) {
	    print "\$File::Find::dir   $File::Find::dir \n"; # directory containing file
	    print "\$File::Find::name  $File::Find::name\n"; # path of file
	    print "relative path      ". File::Spec -> abs2rel($File::Find::name, $root_dir), "\n";
    } elsif ($_ =~ /.md$/) {
	    writehtml($_);
    }
}
