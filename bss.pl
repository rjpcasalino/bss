#!/usr/bin/env perl

# bss - boring static site generator 
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

use v5.10;

use autodie;
use Config::IniFiles;
use Cwd qw(abs_path realpath);
use Data::Dumper;
use File::Copy qw(move);
use File::Find;
use File::Basename;
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

$manifest = Config::IniFiles->new(-file => "manifest.ini");
my %config = (
	TT_CONFIG => \%tt_config,
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

# TEMPLATE TOOLKIT #
my $tt_config = {
	INCLUDE_PATH => undef,
	INTERPOLATE  => 0,
	POST_CHOMP   => 1,
	EVAL_PERL    => 1,
	RELATIVE => 1,		    
	ENCODING => undef
};

mkdir($config{DEST}) unless -e $config{DEST};
# set template toolkit options
$config{TT_CONFIG}->{INCLUDE_PATH} = $config{TT_DIR};
$config{TT_CONFIG}->{ENCODING} = $config{ENCODING};

say "manifest:" if $Verbose;
foreach $key (sort keys %config) {
	$value = $config{$key};
	say "$key: $value" if $Verbose;
}

$greetings = "Hello! Bonjour! Welcome! ひ";
say "
	$greetings
	Working in: $config{SRC}
	Dest: $config{DEST}
	Excluding: $config{EXCLUDE}
	Encoding: $config{ENCODING}
	Server -
	 PORT:$config{PORT}
	 HOST:$config{HOST}
	 "
if $Verbose;

say "?"; # what should we do?
my $command = <STDIN>;

# TODO: see sub with same name below
my @collections = split(/,/, @config{COLLECTIONS});
for my $i (@collections) { 
	if (-e File::Spec->catfile($config{SRC}, $i)) { 
		find(\&collections, File::Spec->catfile($config{SRC}, $i)); 
	}
}

if ($command =~ /build/i) {
	find(\&build, $config{SRC});
	system "rm", "-rf", $config{DEST};
	open my $exclude_fh, ">", "exclude.txt";
	@excludes = split /,/, $config{EXCLUDE};
	for $line (@excludes) {
		say $exclude_fh "$line";
	}
	system "rsync", "-avm", "--exclude-from=exclude.txt", $config{SRC}, $config{DEST};
	# house cleaning
	unlink("exclude.txt");
	move "$config{DEST}/src", "$config{DEST}/build";
	find(sub {if ($_=~ /.html$/) { unlink($_)}}, $config{SRC});
	# thanks for stopping by!
	say "Site created in $config{DEST}!";
	exit;
} elsif ($command =~ /server/i) {
	# TODO
}
pod2usage(1);

sub handleYAML {
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
		# remove YAML block
		if ($_ =~ /(---(.+)---)/s) {
			s/$1//g;
		}
		push(@body, markdown($_));
	}
	open my $HTML, ">", $html;
	
	my $site_modified = strftime '%c', localtime();
	# my $page_modified;
	
	my $vars = {
		title => $title,
		body => \@body,
		collections => @config{COLLECTIONS},
		site_modified => $site_modified
	};

	$template->process("$layout.tmpl", $vars, $HTML)
		or die $template->error();
	say "$title processed." if $Verbose;
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
	    handleYAML();
    } elsif ($_ =~ /.png|.jpg|.jpeg|.gif|.svg$/i) {
	    # TODO
    }
}

# TODO: needs to become a hash of arrays  
sub collections {
	my @temp;
	next if $_ eq "." or $_ eq "..";
	my $fn = basename $File::Find::name;
	push(@temp, $fn);
	@config{COLLECTIONS} = \@temp;
}

=head1 NAME

boring static site generator

=head1 SYNOPSIS

[env] bss [options] [command]

     Options:
       --help     	 prints this help message

    Commands:
    	build		 builds _site dir
	server		 builds _site dir and serves it
