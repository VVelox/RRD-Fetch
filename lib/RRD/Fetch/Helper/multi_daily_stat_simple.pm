package RRD::Fetch::Helper::multi_daily_stat_simple;
use base 'Error::Helper';

use 5.006;
use strict;
use warnings;
use String::ShellQuote qw( shell_quote );
use JSON;

=head1 NAME

RRD::Fetch::Helper::multi_daily_stats_simple - Fetch information from a RRD file.

=head1 VERSION

Version 0.0.1

=cut

our $VERSION = '0.0.1';

=head1 SYNOPSIS



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
					$devices->{ $device->{'hostname'} }
						= { 'app_id' => $device->{'applications'}[$app_int]{'app_id'}, };
				} ## end if ( ( ref( $device->{'applications'}[$app_int...])))

				$app_int++;
			} ## end while ( defined( $device->{'applications'}[$app_int...]))
		} ## end if ( defined( $device->{'applications'} ) ...)
	} ## end foreach my $device_raw (@report_devices_output_split)

} ## end sub action

sub opts_data {
	return '
user=s
command=s
ldir=s
rdir=s
mri
mr=s
sri
sr=s
dev=s
';
} ## end sub opts_data

=head2

=head1 ERROR CODES/FLAGS

=head2 1/rrd_file_undef

The value given for rrd_file is undef.

=head2 2/wrong_ref_type

The specified variable is of the wrong ref type.

=head2 3/rrd_fetcher_init_error

Failed to init RRD::Fetcher for a file.

=head1 AUTHOR

Zane C. Bowers-Hadley, C<< <vvelox at vvelox.net> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-rrd-fetch at rt.cpan.org>, or through
the web interface at L<https://rt.cpan.org/NoAuth/ReportBug.html?Queue=RRD-Fetch>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc RRD::Fetch


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker (report bugs here)

L<https://rt.cpan.org/NoAuth/Bugs.html?Dist=RRD-Fetch>

=item * CPAN Ratings

L<https://cpanratings.perl.org/d/RRD-Fetch>

=item * Search CPAN

L<https://metacpan.org/release/RRD-Fetch>

=back

=head1 LICENSE AND COPYRIGHT

This software is Copyright (c) 2025 by Zane C. Bowers-Hadley.

This is free software, licensed under:

  The GNU General Public License, Version 2, June 1991


=cut

1;    # End of RRD::Fetch
