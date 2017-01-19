package HTTP::Generator;
use strict;
use Filter::signatures;
use feature 'signatures';
no warnings 'experimental::signatures';
use Algorithm::Loops 'NestedLoops';
use List::MoreUtils 'zip';
use URI::Escape;
use Exporter 'import';

=head1 NAME

HTTP::Generator - generate HTTP requests

=cut

use vars qw($VERSION %defaults @EXPORT_OK);
$VERSION = '0.01';
@EXPORT_OK = qw( generate_requests );

sub unwrap($item,$default) {
    defined $item
    ? (ref $item ? $item : [$item])
    : $default
}

sub fetch_all( $iterator ) {
    my @res;
    while( my @r = $iterator->()) {
        push @res, @r
    };
    return @res
};

%defaults = (
    method       => ['GET'],
    url          => ['/'],
    port         => [80],
    protocol     => ['http'],
    # How can we specify various values for the headers?
    headers      => [{}],
    #get_params   => [],
    #post_params  => [],
    #url_params   => [],
    #values       => [[]], # the list over which to iterate for *_params
);

# We want to skip a set of values if they make a test fail
# if a value appears anywhere with a failing test, skip it elsewhere
# or look at the history to see whether that value has passing tests somewhere
# and then keep it?!

sub fill_url( $url, $values ) {
    if( $values ) {
        $url =~ s!/:(\w+)!'/' . uri_escape($values->{$1})!ge;
    };
    $url
};

sub _generate_requests_iter(%options) {
    my $wrapper = delete $options{ wrap } || sub {@_};
    my @keys = sort keys %defaults;
    
    my $get_params = $options{ get_params } || {};
    my $post_params = $options{ post_params } || {};
    my $url_params = $options{ url_params } || {};

    $options{ "fixed_$_" } ||= {}
        for @keys;

    # Now only iterate over the non-empty lists
    my %args = map { my @v = unwrap($options{ $_ }, [@{$defaults{ $_ }}]);
                     @v ? ($_ => @v) : () }
               @keys;
    @keys = sort keys %args; # somewhat predictable
    $args{ $_ } ||= {}
        for qw(get_params post_params url_params);
    
    my @loops = map { ref $_ ne 'ARRAY' ? [$_] : $_ } @args{ @keys };
    
    # Turn all get_params into additional loops for each entry in keys %$get_params
    # Turn all post_params into additional loops over keys %$post_params
    my @get_params = keys %$get_params;
    push @loops, values %$get_params;
    my @post_params = keys %$post_params;
    push @loops, values %$post_params;
    my @url_params = keys %$url_params;
    push @loops, values %$url_params;
    
    #warn "Looping over " . Dumper \@loops;
    
    my $iter = NestedLoops(\@loops,{});
    
    # Set up the fixed parts
    my %template;
    
    for(qw(get_params post_params headers)) {
        $template{ $_ } = $options{ "fixed_$_" } || {};
    };
    #warn "Template setup: " . Dumper \%template;

    return sub {
        my @v = $iter->();
        return unless @v;
        #warn Dumper \@v;

        # Patch in the new values
        my %values = %template;
        my @vv = splice @v, 0, 0+@keys;
        @values{ @keys } = @vv;
        
        # Now add the get_params, if any
        if(@get_params) {
            my @get_values = splice @v, 0, 0+@get_params;
            $values{ get_params } = { (%{ $values{ get_params } }, zip( @get_params, @get_values )) };
        };
        # Now add the post_params, if any
        if(@post_params) {
            my @values = splice @v, 0, 0+@post_params;
            $values{ post_params } = { %{ $values{ post_params } }, zip @post_params, @values };
        };

        # Recreate the URL with the substituted values
        if( @url_params ) {
            my %v;
            @v{ @url_params } = splice @v, 0, 0+@url_params;
            $values{ url } = fill_url($values{ url }, \%v);
        };
        
        # Merge the headers as well
        #warn "Merging headers: " . Dumper($values{headers}). " + " . (Dumper $template{headers});
        %{$values{headers}} = (%{$template{headers}}, %{$values{headers} || {}});
        
        return $wrapper->(\%values);
    };
}

sub generate_requests(%options) {
    my $i = _generate_requests_iter(%options);
    if( wantarray ) {
        return fetch_all($i);
    } else {
        return $i
    }
}

sub as_dancer($req) {
    # Store metadata / generate "signature" for later inspection/isolation?
    warn Dumper $req
}

1;