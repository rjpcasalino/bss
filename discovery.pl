#!/usr/bin/env perl

use strict;
use warnings;

use Cwd;
use File::Find;
use Text::Markdown 'markdown';
use Template;
use Log::Dispatch;
use Log::Dispatch::File;
use Log::Dispatch::Screen;

my $root_dir = getcwd;
my $mode;

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

init(@ARGV);

sub init {
	if (defined $ARGV[0] && $ARGV[0] =~ /^--d/i) {
		$mode = "DEBUG";
	} else {
		$mode = "NORMAL";
	}
	if ($mode eq "DEBUG") {
		my $time = localtime();
		$log->debug("DEBUG: $time\n");
		$log->info("DEBUG: $time\n");
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
		my $time = localtime();
		$log->info("Build started: $time\n");
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
	$template->process($tmpl, $vars, $fh)
		or die $template->error();
}


sub start {
    # Name of the file (without path information)
    print "$_\n"; 
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
