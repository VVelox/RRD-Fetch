#!perl
use 5.006;
use strict;
use warnings;
use Test::More;

plan tests => 1;

BEGIN {
    use_ok( 'RRD::Fetch::Helper::librenms_logsize_daily_stats' ) || print "Bail out!\n";
}

diag( "Testing RRD::Fetch::Helper::librenms_logsize_daily_stats $RRD::Fetch::Helper::librenms_logsize_daily_stats::VERSION, Perl $], $^X" );
