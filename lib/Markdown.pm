#$Id: Markdown.pm,v 1.3 2005/11/12 03:28:09 naoya Exp $
package Template::Plugin::Markdown;
use strict;
use base qw (Template::Plugin::Filter);
use Text::Markdown;
 
our $VERSION = 0.02;
 
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
