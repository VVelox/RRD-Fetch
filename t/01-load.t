#!perl
use 5.006;
use strict;
use warnings;
use Test::More;

plan tests => 1;

BEGIN {
    use_ok( 'RRD::Fetch::Helper' ) || print "Bail out!\n";
}

diag( "Testing RRD::Fetch::Helper $RRD::Fetch::Helper::VERSION, Perl $], $^X" );
