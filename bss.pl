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
use Data::Dumper;
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

GetOptions("help" => \$help) or pod2usage(2);
pod2usage(1) if $help;

my $manifest = "manifest.ini";
say "No manifest found!\n See README." and exit unless -e $manifest;

# ####################### #
# template toolkit config #
# ####################### #
my $tt_config = {
    INCLUDE_PATH => undef,  	     
    INTERPOLATE  => 0,
    POST_CHOMP   => 1,
    EVAL_PERL    => 1,
    RELATIVE => 1,		    
    ENCODING => undef
};

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
	PORT => $manifest->val("server", "port"),
	HOST => $manifest->val("server", "host")
);

sub main {
	mkdir($config{DEST}) unless -e $config{DEST};
	# set template toolkit options
	$config{TT_CONFIG}->{INCLUDE_PATH} = $config{TT_DIR};
	$config{TT_CONFIG}->{ENCODING} = $config{ENCODING};
	
	say "manifest:" if $Verbose;
	foreach $key (sort keys %config) {
		$value = $config{$key};
		say "$key => $value" if $Verbose;
	}

	$greetings = "Hello! Bonjour! Welcome! ひ";
	say "
		$greetings
		Working in: $config{SRC}
	     	Dest: $config{DEST}
	     	Encoding: $config{ENCODING}
		Server -
		 PORT:$config{PORT}
		 HOST:$config{HOST}
		 "
	if $Verbose;
	
	say "?";
	# TODO: everything I am doing here is bad...just bad.
	my @collections = split(/,/, @config{COLLECTIONS});
	for my $i (@collections) { 
		if (-e File::Spec->catfile($config{SRC}, $i)) { 
			find(\&collections, File::Spec->catfile($config{SRC}, $i)); 
		}
	}
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

# TODO: good God, clean this up
sub handleyamlblock {
	my $yaml;
	open $MD, $_;
	undef $/;
	my $data = <$MD>;
	if ($data =~ /---(.+)---/s) {
		$yaml = $1;
	}
	$yaml =~ s/^\s+|\s+$//g;
	@yaml = split /\n/, $yaml;
	writehtml($_, @yaml);
}

sub writehtml {
	my ($html, @yaml) = @_;
	$html =~ s/\.md$/\.html/;
	my $template = Template->new($config{TT_CONFIG});
	my $layout; 

	my $title;
	my @body;
	foreach my $opt (@yaml) {
		if ($opt =~ /title/i) {
			$opt =~ s/(title:)//;
			$title = $opt;
		} elsif ($opt =~ /layout/i) {
			$opt =~ s/(layout:)//;
			$opt =~ s/^\s+|\s+$//g;
			$layout = $opt;
		} elsif ($opt =~ /meta/i) {
			# TODO
		} else {
			say "Unknown option: $opt";
		}
	}
	
	open $MD, $_;
	while(<$MD>) {
		push(@body, markdown($_));
	}
	open my $HTML, ">", $html;
	
	my $site_modified = strftime '%c', localtime();
	# my $page_modified;
	
	my $vars = {
		title => $title,
		body => \@body,
		## note deref above but not below ##
		## see sub collections 
		collections => @config{COLLECTIONS},
		site_modified => $site_modified
	};

	$template->process("$layout.tmpl", $vars, $HTML)
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
	    handleyamlblock();
    } elsif ($_ =~ /.png|.jpg|.jpeg|.gif|.svg$/i) {
	    # TODO
    }
}

sub clean {
    if ($_ =~ /.html$/) {
    	unlink($_);
    }
}

sub collections {
	next if $_ eq "." or $_ eq "..";
	my $fn = basename $File::Find::name;
	# TODO: filter regex
	# i.e., allow option in config to 
	# apply filter to certain collection 
	push(@collections, $fn);
	@config{COLLECTIONS} = \@collections;
}

main();

=head1 NAME

boring static site generator - a simple static site generator 

=head1 SYNOPSIS

[env] bss [options] [command]

     Options:
       --help     	 prints this help message

    Commands:
    	build		 builds _site dir
	server		 builds _site dir and serves it
