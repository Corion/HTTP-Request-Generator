#!perl -w
use strict;
use HTTP::Generator qw(generate_requests);
use Data::Dumper;

use Test::More tests => 10;

my @requests = generate_requests();
is 0+@requests, 1;

@requests = generate_requests(
    method => 'GET',
    url    => ['/','/index.html'],
);
is 0+@requests, 2;


@requests = generate_requests(
    method => ['POST','GET'],
    url    => ['/','/index.html'],
    #get_params => ['foo','bar','baz'],
    get_params => {
        foo => [1,2,3],
        bar => [4,5,6],
        baz => [7,8,9],
    },
    fixed_get_params => {
        session => 'my_session_id',
    },
);
is 0+@requests, 2*2*3*3*3;
#diag Dumper $requests[0];
ok exists $requests[0]->{get_params}, 'Fixed get parameters get added';
is $requests[0]->{get_params}->{session}, 'my_session_id';
#warn Dumper \@requests;

@requests = generate_requests(
    method => 'GET',
    url    => '/profiles/:name/:id',
    url_params => {
        name => ['Corion','Co-Rion'],
        id   => [1,2],
    },
    get_params => {
        foo => [2,3],
    },
    fixed_get_params => {
        session => 'my_session_id',
    },
);
is 0+@requests, 8;
is $requests[0]->{url}, '/profiles/Corion/1'
    or diag Dumper $requests[0];
is $requests[0]->{get_params}->{foo}, 2
    or diag Dumper \@requests;
is $requests[0]->{get_params}->{session}, 'my_session_id'
    or diag Dumper $requests[0];
is_deeply $requests[0], {
    method => 'GET',
    url => '/profiles/Corion/1',
    protocol => 'http',
    port => 80,
    headers => {},
    post_params => {},
    get_params => {
        session => 'my_session_id',
        foo => 2,
    },
}, "The structure is as we expect";
