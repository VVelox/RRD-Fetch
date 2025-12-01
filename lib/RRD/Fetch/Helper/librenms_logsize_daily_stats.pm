package RRD::Fetch::Helper::librenms_logsize_daily_stats;
use base 'Error::Helper';

use 5.006;
use strict;
use warnings;
use String::ShellQuote qw( shell_quote );
use JSON               qw( decode_json );
use RRD::Fetch         ();
use Statistics::Lite   qw(max mean median min mode sum);

=head1 NAME

RRD::Fetch::Helper::librenms_logsize_daily_stats - Fetch information from a RRD file.

=head1 VERSION

Version 0.0.1

=cut

our $VERSION = '0.0.1';

=head1 SYNOPSIS

=head2 BASIC FLAGS

=head2 -s <start>

Start time to use.

=head2 -f <days>

How many days to fetch info for.

=head2 SELECTION FLAGS

=head2 --dev <dev spec>

A dev spec to use for when calling lnms report:devices.

default: undef

=head2 --dr <regex>

A regex to use for matching returned device names.

default: undef

=head2 --dri

Invert the matching for --dr.

=head2 --sr <regex>

A regex to use for matching logsize set names.

default: undef

=head2 --sri

Invert the matching for --sr.

=head1 CONFIG FLAGS

=head2 --command <command>

Command to use for accessing the LibreNMS user.

'%%%user%%%' will be replaced with the user in question.

default: sudo -u %%%user%%%

=head2 --ldir <dir>

The LibreNMS dir.

If not specified, then the first directory found in the order below is used.

    /home/librenms/librenms
    /usr/local/www/librenms
    /opt/librenms

=head2 --rdir <dir>

Path to the RRD dir for LibreNMS.

'%%%ldir%%%' will be replace with the path for the LibreNMS dir.

If not defined, 'lnms config:get rrd_dir' is used to fetch it.

=head2 --user <user>

The user to use for LibreNMS.

default: librenms

=cut

sub action {
	my ( $self, %opts ) = @_;

	if ( !defined( $opts{'opts'}{'s'} ) ) {
		die('-s is undef... this should be used for specify the start time');
	}

	if ( !defined( $opts{'opts'}{'f'} ) ) {
		$opts{'opts'}{'f'} = '7';
	}

	if ( !defined( $opts{'opts'}{'user'} ) ) {
		$opts{'opts'}{'user'} = 'librenms';
	}

	if ( !defined( $opts{'opts'}{'command'} ) ) {
		$opts{'opts'}{'command'} = 'sudo -u %%%user%%%';
	}

	if ( !defined( $opts{'opts'}{'ldir'} ) ) {
		if ( -d '/home/librenms/librenms' ) {
			$opts{'opts'}{'ldir'} = '/home/librenms/librenms';
		} elsif ( -d '/usr/local/www/librenms' ) {
			$opts{'opts'}{'ldir'} = '/usr/local/www/librenms';
		} else {
			$opts{'opts'}{'ldir'} = '/opt/librenms';
		}
	}
	if ( !-d $opts{'opts'}{'ldir'} ) {
		die( '--ldir, "' . $opts{'opts'}{'ldir'} . '", is not a dir or does not exist' );
	}

	my $lnms = $opts{'opts'}{'ldir'} . '/lnms';
	if ( !-f $lnms ) {
		die( '"' . $lnms . '" is not a file or does not exist' );
	} elsif ( !-x $lnms ) {
		die( '"' . $lnms . '" is not executable' );
	}

	my $command = $opts{'opts'}{'command'};
	$command =~ s/\%\%\%user\%\%\%/$opts{'opts'}{'user'}/g;
	$command = $command . ' ' . $lnms;

	if ( !defined( $opts{'opts'}{'rdir'} ) ) {
		$opts{'opts'}{'rdir'} = `$command config:get rrd_dir`;
		if ( $? != 0 ) {
			die( '"' . $command . ' config:get rrd_dir" exited non-zero with "' . $opts{'opts'}{'rdir'} . '"' );
		}
		chomp( $opts{'opts'}{'rdir'} );
	} else {
		$opts{'opts'}{'rdir'} =~ s/\%\%\%ldir\%\%\%/$opts{'opts'}{'ldir'}/g;
	}

	my $report_devices_command = $command . ' report:devices -o json -r applications';
	if ( defined( $opts{'opts'}{'dev'} ) ) {
		$report_devices_command = $report_devices_command . ' ' . shell_quote( $opts{'opts'}{'dev'} );
	}
	$report_devices_command = $report_devices_command . ' 2>&1';

	my $report_devices_output = `$report_devices_command`;
	if ( $? != 0 ) {
		die( '"' . $report_devices_command . '" exited non-zero with "' . $report_devices_output . '"' );
	}

	my @report_devices_output_split = split( /\n/, $report_devices_output );
	my $devices                     = {};
	foreach my $device_raw (@report_devices_output_split) {
		my $device;
		eval { $device = decode_json($device_raw); };
		if ($@) {
			die(      'Got bad JSON... "'
					. $report_devices_output
					. '" from the command "'
					. $report_devices_command
					. '"' );
		}

		my $process_dev = 1;
		if ( defined( $opts{'opts'}{'dr'} ) ) {
			if ( $device->{'hostname'} =~ /$opts{'opts'}{'dr'}/ ) {
				if ( $opts{'opts'}{'dri'} ) {
					$process_dev = 0;
				}
			} else {
				if ( !$opts{'opts'}{'dri'} ) {
					$process_dev = 0;
				}
			}
		} ## end if ( defined( $opts{'opts'}{'dr'} ) )

		if ($process_dev) {
			if ( defined( $device->{'applications'} ) && ( ref( $device->{'applications'} ) eq 'ARRAY' ) ) {
				my $app_int    = 0;
				my $app_search = 1;
				while ( defined( $device->{'applications'}[$app_int] ) && $app_search ) {
					if (   ( ref( $device->{'applications'}[$app_int] ) eq 'HASH' )
						&& defined( $device->{'applications'}[$app_int]{'app_id'} )
						&& ( ref( $device->{'applications'}[$app_int]{'app_id'} ) eq '' )
						&& defined( $device->{'applications'}[$app_int]{'app_type'} )
						&& ( $device->{'applications'}[$app_int]{'app_type'} eq 'logsize' )
						&& ( ref( $device->{'applications'}[$app_int]{'app_type'} ) eq '' )
						&& defined( $device->{'applications'}[$app_int]{'data'} )
						&& ( ref( $device->{'applications'}[$app_int]{'data'} ) eq 'HASH' )
						&& defined( $device->{'applications'}[$app_int]{'data'}{'sets'} )
						&& ( ref( $device->{'applications'}[$app_int]{'data'}{'sets'} ) eq 'HASH' ) )
					{
						my @found_sets = keys( %{ $device->{'applications'}[$app_int]{'data'}{'sets'} } );

						my @sets;
						if ( !defined( $opts{'opts'}{'sr'} ) ) {
							@sets = @found_sets;
						} else {
							foreach my $set (@found_sets) {
								my $add_set = 1;
								if ( $set =~ /$opts{'opts'}{'sr'}/ ) {
									if ( $opts{'opts'}{'sri'} ) {
										$add_set = 0;
									}
								} else {
									if ( !$opts{'opts'}{'sri'} ) {
										$add_set = 0;
									}
								}
								if ($add_set) {
									push( @sets, $set );
								}
							} ## end foreach my $set (@found_sets)
						} ## end else [ if ( !defined( $opts{'opts'}{'sr'} ) ) ]

						if ( defined( $sets[0] ) ) {
							$devices->{ $device->{'hostname'} } = {
								'app_id' => $device->{'applications'}[$app_int]{'app_id'},
								'sets'   => \@sets,
							};
						}

					} ## end if ( ( ref( $device->{'applications'}[$app_int...])))

					$app_int++;
				} ## end while ( defined( $device->{'applications'}[$app_int...]))
			} ## end if ( defined( $device->{'applications'} ) ...)
		} ## end if ($process_dev)
	} ## end foreach my $device_raw (@report_devices_output_split)

	my $to_return = {
		'dev-sets'   => [],
		'data'       => {},
		'stat_stats' => {},
	};

	my %dates;
	my @device_keys = sort( keys( %{$devices} ) );
	foreach my $device (@device_keys) {
		my $base_dir = $opts{'opts'}{'rdir'} . '/' . $device;
		foreach my $set ( sort @{ $devices->{$device}{'sets'} } ) {
			my $set_filename_part=$set;
			$set_filename_part=~s/[\\\/\ \+]/\_/g;
			my $rrd         = $base_dir . '/app-logsize-' . $devices->{$device}{'app_id'} . '-' . $set_filename_part . '.rrd';
			my $rrd_fetch   = RRD::Fetch->new( 'CF' => 'MAX', 'rrd_file' => $rrd );
			my $daily_stats = $rrd_fetch->daily_stats( 'start' => $opts{'opts'}{'s'}, 'for' => $opts{'opts'}{'f'} );

			my $devset = $device . ' ' . $set;

			push( @{ $to_return->{'dev-sets'} }, $devset );

			foreach my $date ( @{ $daily_stats->{'dates'} } ) {
				$dates{$date} = 1;
				if ( !defined( $to_return->{'data'}{$date} ) ) {
					$to_return->{'data'}{$date} = {};
				}

				$to_return->{'data'}{$date}{$devset} = $daily_stats->{'max'}{$date}{'max_size'};
				# can't be less than a byte, so just loss anything after the decimal place for simplicity purposes
				$to_return->{'data'}{$date}{$devset}=~s/\..*$//g;
			}
		} ## end foreach my $set ( sort @{ $devices->{$device}{'sets'...}})
	} ## end foreach my $device (@device_keys)
	my @dates_keys = sort( keys(%dates) );
	$to_return->{'dates'} = \@dates_keys;

	$to_return->{'output'} = 'dates';
	foreach my $devset ( @{ $to_return->{'dev-sets'} } ) {
		$to_return->{'output'} = $to_return->{'output'} . ',' . $devset;
	}
	$to_return->{'output'} = $to_return->{'output'} . ",-,sum,min,max,mean,median,mode\n";
	my @sums;
	my @mins;
	my @maxs;
	my @means;
	my @medians;
	my @modes;

	foreach my $date ( @{ $to_return->{'dates'} } ) {
		my @day_values;

		$to_return->{'output'} = $to_return->{'output'} . $date;
		foreach my $devset ( @{ $to_return->{'dev-sets'} } ) {
			$to_return->{'output'} = $to_return->{'output'} . ',' . $to_return->{'data'}{$date}{$devset};
			push( @day_values, $to_return->{'data'}{$date}{$devset} );

		}
		$to_return->{'output'} = $to_return->{'output'} . ',-';

		my $sum    = 0;
		my $min    = 0;
		my $max    = 0;
		my $mean   = 0;
		my $median = 0;
		my $mode   = 0;
		if ( defined( $day_values[0] ) ) {
			$sum    = sum(@day_values);
			$min    = min(@day_values);
			$max    = max(@day_values);
			$mean   = mean(@day_values);
			$median = median(@day_values);
			$mode   = mode(@day_values);
		}
		$to_return->{'output'}
			= $to_return->{'output'} . ','
			. $sum . ','
			. $min . ','
			. $max . ','
			. $mean . ','
			. $median . ','
			. $mode . "\n";

		push( @sums,    $sum );
		push( @mins,    $min );
		push( @maxs,    $max );
		push( @means,   $mean );
		push( @medians, $median );
		push( @modes,   $mode );
	} ## end foreach my $date ( @{ $to_return->{'dates'} } )

	my $blank_space = '';
	foreach ( @{ $to_return->{'dev-sets'} } ) {
		$blank_space = $blank_space . ',';
	}

	my $sum_sum       = 0;
	my $sum_min       = 0;
	my $sum_max       = 0;
	my $sum_mean      = 0;
	my $sum_median    = 0;
	my $sum_mode      = 0;
	my $min_sum       = 0;
	my $min_min       = 0;
	my $min_max       = 0;
	my $min_mean      = 0;
	my $min_median    = 0;
	my $min_mode      = 0;
	my $max_sum       = 0;
	my $max_min       = 0;
	my $max_max       = 0;
	my $max_mean      = 0;
	my $max_median    = 0;
	my $max_mode      = 0;
	my $mean_sum      = 0;
	my $mean_min      = 0;
	my $mean_max      = 0;
	my $mean_mean     = 0;
	my $mean_median   = 0;
	my $mean_mode     = 0;
	my $median_sum    = 0;
	my $median_min    = 0;
	my $median_max    = 0;
	my $median_mean   = 0;
	my $median_median = 0;
	my $median_mode   = 0;
	my $mode_sum      = 0;
	my $mode_min      = 0;
	my $mode_max      = 0;
	my $mode_mean     = 0;
	my $mode_median   = 0;
	my $mode_mode     = 0;

	if ( defined( $sums[0] ) ) {
		$sum_sum       = sum(@sums);
		$sum_min       = min(@sums);
		$sum_max       = max(@sums);
		$sum_mean      = mean(@sums);
		$sum_median    = median(@sums);
		$sum_mode      = mode(@sums);
		$min_sum       = sum(@mins);
		$min_min       = min(@mins);
		$min_max       = max(@mins);
		$min_mean      = mean(@mins);
		$min_median    = median(@mins);
		$min_mode      = mode(@mins);
		$max_sum       = sum(@maxs);
		$max_min       = min(@maxs);
		$max_max       = max(@maxs);
		$max_mean      = mean(@maxs);
		$max_median    = median(@maxs);
		$max_mode      = mode(@maxs);
		$mean_sum      = sum(@means);
		$mean_min      = min(@means);
		$mean_max      = max(@means);
		$mean_mean     = mean(@means);
		$mean_median   = median(@means);
		$mean_mode     = mode(@means);
		$median_sum    = sum(@medians);
		$median_min    = min(@medians);
		$median_max    = max(@medians);
		$median_mean   = mean(@medians);
		$median_median = median(@medians);
		$median_mode   = mode(@medians);
		$mode_sum      = sum(@modes);
		$mode_min      = min(@modes);
		$mode_max      = max(@modes);
		$mode_mean     = mean(@modes);
		$mode_median   = median(@modes);
		$mode_mode     = mode(@modes);
	} ## end if ( defined( $sums[0] ) )
	$to_return->{'output'}
		= $to_return->{'output'}
		. $blank_space
		. ',sums,'
		. $sum_sum . ','
		. $min_sum . ','
		. $max_sum . ','
		. $mean_sum . ','
		. $median_sum . ','
		. $mode_sum . "\n";
	$to_return->{'output'}
		= $to_return->{'output'}
		. $blank_space . ',min,'
		. $sum_min . ','
		. $min_min . ','
		. $max_min . ','
		. $mean_min . ','
		. $median_min . ','
		. $mode_min . "\n";
	$to_return->{'output'}
		= $to_return->{'output'}
		. $blank_space . ',max,'
		. $sum_max . ','
		. $min_max . ','
		. $max_max . ','
		. $mean_max . ','
		. $median_max . ','
		. $mode_max . "\n";
	$to_return->{'output'}
		= $to_return->{'output'}
		. $blank_space
		. ',mean,'
		. $sum_mean . ','
		. $min_mean . ','
		. $max_mean . ','
		. $mean_mean . ','
		. $median_mean . ','
		. $mode_mean . "\n";
	$to_return->{'output'}
		= $to_return->{'output'}
		. $blank_space
		. ',median,'
		. $sum_median . ','
		. $min_median . ','
		. $max_median . ','
		. $mean_median . ','
		. $median_median . ','
		. $mode_median . "\n";
	$to_return->{'output'}
		= $to_return->{'output'}
		. $blank_space
		. ',mode,'
		. $sum_mode . ','
		. $min_mode . ','
		. $max_mode . ','
		. $mean_mode . ','
		. $median_mode . ','
		. $mode_mode . "\n";

	$to_return->{'stat_stats'}{'sum_sum'}       = $sum_sum;
	$to_return->{'stat_stats'}{'sum_min'}       = $sum_min;
	$to_return->{'stat_stats'}{'sum_max'}       = $sum_max;
	$to_return->{'stat_stats'}{'sum_mean'}      = $sum_mean;
	$to_return->{'stat_stats'}{'sum_median'}    = $sum_median;
	$to_return->{'stat_stats'}{'sum_mode'}      = $sum_mode;
	$to_return->{'stat_stats'}{'min_sum'}       = $min_sum;
	$to_return->{'stat_stats'}{'min_min'}       = $min_min;
	$to_return->{'stat_stats'}{'min_max'}       = $min_max;
	$to_return->{'stat_stats'}{'min_mean'}      = $min_mean;
	$to_return->{'stat_stats'}{'min_median'}    = $min_median;
	$to_return->{'stat_stats'}{'min_mode'}      = $min_mode;
	$to_return->{'stat_stats'}{'max_sum'}       = $max_sum;
	$to_return->{'stat_stats'}{'max_min'}       = $max_min;
	$to_return->{'stat_stats'}{'max_max'}       = $max_max;
	$to_return->{'stat_stats'}{'max_mean'}      = $max_mean;
	$to_return->{'stat_stats'}{'max_median'}    = $max_median;
	$to_return->{'stat_stats'}{'max_mode'}      = $max_mode;
	$to_return->{'stat_stats'}{'mean_sum'}      = $mean_sum;
	$to_return->{'stat_stats'}{'mean_min'}      = $mean_min;
	$to_return->{'stat_stats'}{'mean_max'}      = $mean_max;
	$to_return->{'stat_stats'}{'mean_mean'}     = $mean_mean;
	$to_return->{'stat_stats'}{'mean_median'}   = $mean_median;
	$to_return->{'stat_stats'}{'mean_mode'}     = $mean_mode;
	$to_return->{'stat_stats'}{'median_sum'}    = $median_sum;
	$to_return->{'stat_stats'}{'median_min'}    = $median_min;
	$to_return->{'stat_stats'}{'median_max'}    = $median_max;
	$to_return->{'stat_stats'}{'median_mean'}   = $median_mean;
	$to_return->{'stat_stats'}{'median_median'} = $median_median;
	$to_return->{'stat_stats'}{'median_mode'}   = $median_mode;
	$to_return->{'stat_stats'}{'mode_sum'}      = $mode_sum;
	$to_return->{'stat_stats'}{'mode_min'}      = $mode_min;
	$to_return->{'stat_stats'}{'mode_max'}      = $mode_max;
	$to_return->{'stat_stats'}{'mode_mean'}     = $mode_mean;
	$to_return->{'stat_stats'}{'mode_median'}   = $mode_median;
	$to_return->{'stat_stats'}{'mode_mode'}     = $mode_mode;

	return $to_return;
} ## end sub action

sub opts_data {
	return '
user=s
command=s
ldir=s
rdir=s
dri
dr=s
sri
sr=s
dev=s
s=s
f=s
';
} ## end sub opts_data

1;    # End of RRD::Fetch
