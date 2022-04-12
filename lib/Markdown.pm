# TODO:
# give credit to OG author
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
