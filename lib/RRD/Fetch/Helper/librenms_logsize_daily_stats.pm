package RRD::Fetch::Helper::librenms_logsize_daily_stats;
use base 'Error::Helper';

use 5.006;
use strict;
use warnings;
use String::ShellQuote qw( shell_quote );
use JSON               qw( decode_json );

=head1 NAME

RRD::Fetch::Helper::librenms_logsize_daily_stats - Fetch information from a RRD file.

=head1 VERSION

Version 0.0.1

=cut

our $VERSION = '0.0.1';

=head1 SYNOPSIS

=head2 GENERAL FLAGS

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

default: %%%ldir%%%/rrd

=head2 --user <user>

The user to use for LibreNMS.

default: librenms

=cut

sub action {
	my ( $self, %opts ) = @_;

	if ( !defined( $opts{'user'} ) ) {
		$opts{'user'} = 'librenms';
	}

	if ( !defined( $opts{'command'} ) ) {
		$opts{'command'} = 'sudo -u %%%user%%%';
	}

	if ( !defined( $opts{'ldir'} ) ) {
		if ( -d '/home/librenms/librenms' ) {
			$opts{'ldir'} = '/home/librenms/librenms';
		} elsif ( -d '/usr/local/www/librenms' ) {
			$opts{'ldir'} = '/usr/local/www/librenms';
		} else {
			$opts{'ldir'} = '/opt/librenms';
		}
	}
	if ( !-d $opts{'ldir'} ) {
		die( '--ldir, "' . $opts{'ldir'} . '", is not a dir or does not exist' );
	}

	my $lnms = $opts{'ldir'} . '/lnms';
	if ( !-f $lnms ) {
		die( '"' . $lnms . '" is not a file or does not exist' );
	} elsif ( !-x $lnms ) {
		die( '"' . $lnms . '" is not executable' );
	}

	if ( !defined( $opts{'rdir'} ) ) {
		$opts{'rdir'} = '%%%ldir%%%/rrd';
	}
	$opts{'rdir'} =~ s/\%\%\%ldir\%\%\%/$opts{'ldir'}/g;

	my $command = $opts{'command'};
	$command =~ s/\%\%\%user\%\%\%/$opts{'user'}/g;
	$command = $command . ' ' . $lnms;

	my $report_devices_command = $command . ' report:devices -r applications';
	if ( defined( $opts{'dev'} ) ) {
		$report_devices_command = $report_devices_command . ' ' . shell_quote( $opts{'dev'} );
	}
	$report_devices_command = $report_devices_command . ' 2>&1';

	my $report_devices_output = `$report_devices_command`;
	if ( $? != 0 ) {
		die( '"' . $report_devices_command . '" exited non-zero with "' . $report_devices_output . '"' );
	}

	my @report_devices_output_split = split( /\n/, $report_devices_output );
	my $devices                     = {};
	foreach my $device_raw (@report_devices_output_split) {
		my $device = decode_json($device_raw);

		my $process_dev = 1;
		if ( defined( $opts{'dr'} ) ) {
			if ( $device->{'hostname'} =~ /$opts{'dr'}/ ) {
				if ( $opts{'dri'} ) {
					$process_dev = 0;
				}
			} else {
				if ( !$opts{'dri'} ) {
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
						if ( !defined( $opts{'sr'} ) ) {
							@sets = @found_sets;
						} else {
							foreach my $set (@found_sets) {
								my $add_set = 1;
								if ( $set =~ /$opts{'sr'}/ ) {
									if ( $opts{'sri'} ) {
										$add_set = 0;
									}
								} else {
									if ( !$opts{'sri'} ) {
										$add_set = 0;
									}
								}
								if ($add_set) {
									push( @sets, $set );
								}
							} ## end foreach my $set (@found_sets)

							if ( defined( $sets[0] ) ) {
								$devices->{ $device->{'hostname'} } = {
									'app_id' => $device->{'applications'}[$app_int]{'app_id'},
									'sets'   => \@sets,
								};
							}
						} ## end else [ if ( !defined( $opts{'sr'} ) ) ]

					} ## end if ( ( ref( $device->{'applications'}[$app_int...])))

					$app_int++;
				} ## end while ( defined( $device->{'applications'}[$app_int...]))
			} ## end if ( defined( $device->{'applications'} ) ...)
		} ## end if ($process_dev)
	} ## end foreach my $device_raw (@report_devices_output_split)

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
';
} ## end sub opts_data

1;    # End of RRD::Fetch
