package RRD::Fetch::Helper::librenms_logsize_daily_stats;
use base 'Error::Helper';

use 5.006;
use strict;
use warnings;
use String::ShellQuote qw( shell_quote );
use JSON               qw( decode_json );
use RRD::Fetch;

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
		if ($? != 0){
			die( '"' . $command . ' config:get rrd_dir" exited non-zero with "' . $opts{'opts'}{'rdir'} . '"' );
		}
		chomp($opts{'opts'}{'rdir'});
	}else{
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
		} ## end if ( defined( $opts{'dr'} ) )

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
						} ## end else [ if ( !defined( $opts{'sr'} ) ) ]

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

	my $to_return={
		'dev-sets'=>[],
			'data'=>{},
	};

	my %dates;
	my @device_keys =keys(%{ $devices });
	foreach my $device (@device_keys){
		my $base_dir = $opts{'opts'}{'rdir'}.'/'.$device;
		foreach my $set (@{ $devices->{$device}{'sets'} }){
			my $rrd = $base_dir.'/app-logsize-'.$devices->{$device}{'app_id'}.'-'.$set.'.rrd';
			my $rrd_fetch = RRD::Fetch->new('CF'=>'MAX', 'rrd_file' => $rrd);
			my $daily_stats = $rrd_fetch->daily_stats('start' => $opts{'opts'}{'s'}, 'for' => $opts{'opts'}{'f'});

			my $devset=$device.' '.$set;

			push(@{ $to_return->{'dev-sets'} }, $devset);
			
			foreach my $date (@{ $daily_stats->{'dates'} }){
				$dates{$date}=1;
				if (!defined($to_return->{'data'}{$date})){
					$to_return->{'data'}{$date}={};
				};

				$to_return->{'data'}{$date}{$devset}=$daily_stats->{'max'}{$date}{'max_size'};
			}
		}
	}
	my @dates_keys=sort(keys(%dates));
	$to_return->{'dates'}=\@dates_keys;

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
