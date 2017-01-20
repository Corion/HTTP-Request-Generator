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

=head1 SYNOPSIS


    @requests = generate_requests(
        method => 'POST',
        url    => '/profiles/:name',
        url_params => {
            name => ['Corion','Co-Rion'],
        },
        get_params => {
            stars => [2,3],
        },
        post_params => {
            comment => ['Some comment', 'Another comment, A++'],
        },
        headers => [
            {
                "Content-Type" => 'text/plain; encoding=UTF-8',
                Cookie => 'my_session_id',
            },
            {
                "Content-Type" => 'text/plain; encoding=Latin-1',
                Cookie => 'my_session_id',
            },
        ],
    );
    # Generates 16 requests out of the combinations

    for my $req (@requests) {
        $ua->request( $req );
    };

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

# Convert nonref arguments to arrayrefs
sub _makeref {
    map {
        ref $_ ne 'ARRAY' ? [$_] : $_
    } @_
}

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

    my @loops = _makeref @args{ @keys };

    # Turn all get_params into additional loops for each entry in keys %$get_params
    # Turn all post_params into additional loops over keys %$post_params
    my @get_params = keys %$get_params;
    push @loops, _makeref values %$get_params;
    my @post_params = keys %$post_params;
    push @loops, _makeref values %$post_params;
    my @url_params = keys %$url_params;
    push @loops, _makeref values %$url_params;

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

=head2 generate_requests( %options )

  generate_requests(
      url => '/profiles/:name',
      url_params => ['Mark','John'],
      wrap => sub {
          my( $req ) = @_;
          # Fix up some values
          $req->{headers}->{'Content-Length'} = 666;
      },
  );

This function creates data structures that are suitable for sending off
a mass of similar but different HTTP requests. All array references are expanded
into the cartesian product of their contents. The above example would create
two requests:

      url => '/profiles/Mark,
      url => '/profiles/John',

There are helper functions
that will turn that data into a data structure suitable for your HTTP framework
of choice.

  {
    method => 'GET',
    url => '/profiles/Mark',
    protocol => 'http',
    port => 80,
    headers => {},
    post_params => {},
    get_params => {},
  }

=cut

sub generate_requests(%options) {
    my $i = _generate_requests_iter(%options);
    if( wantarray ) {
        return fetch_all($i);
    } else {
        return $i
    }
}

sub as_dancer($req) {
    require Dancer::Request;
    # Also, HTTP::Message 6+ for ->flatten()

    my $body = '';
    my $headers;
    my $form_ct;
    if( keys %{$req->{post_params}}) {
        require HTTP::Request::Common;
        my $r = HTTP::Request::Common::POST( $req->{url},
            [ %{ $req->{post_params} }],
        );
        $headers = HTTP::Headers->new( %{ $req->{headers} }, $r->headers->flatten );
        $body = $r->content;
        $form_ct = $r->content_type;
    } else {
        $headers = HTTP::Headers->new( %$headers );
    };

    # Store metadata / generate "signature" for later inspection/isolation?
    local %ENV; # wipe out non-overridable default variables of Dancer::Request
    my $res = Dancer::Request->new_for_request(
        $req->{method},
        $req->{url},
        $req->{get_params},
        $body,
        $headers,
        { CONTENT_LENGTH => length($body),
          CONTENT_TYPE => $form_ct },
    );
    use Data::Dumper;
    warn Dumper $res->{_http_body};
    $res->{_http_body}->add($body);
    warn Dumper $res->{_http_body};
    $res
}

1;

=head1 SEE ALSO

=cut