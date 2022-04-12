# This is mostly Markdown.pm,v 1.3 2005/11/12 03:28:09 by naoya
# see: https://metacpan.org/release/NAOYA/Template-Plugin-Markdown-0.02
package Markdown;

use strict;
use Text::Markdown;
use base qw (Template::Plugin::Filter);

sub init {
    my $self = shift;
    $self->{_DYNAMIC} = 1;
    $self->install_filter($self->{_ARGS}->[0] || 'markdown');
    $self;
}

sub filter {
    my ($self, $text, $args, $config) = @_;
    my $m = Text::Markdown->new;
    return $m->markdown($text);
}

1;
