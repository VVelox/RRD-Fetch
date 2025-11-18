package RRD::Fetch::Helper::multi_daily_stat_simple;
use base 'Error::Helper';

use 5.006;
use strict;
use warnings;
use Time::Piece      ();
use Statistics::Lite qw(max mean median min mode sum);

=head1 NAME

RRD::Fetch - Fetch information from a RRD file.

=head1 VERSION

Version 0.0.1

=cut

our $VERSION = '0.0.1';

=head1 SYNOPSIS

    use RRD::Fetch::Helper::multi_daily_stat_simple;

=head1 METHODS

=head2 new

Initiates the object.

The required args are as below.

    - rrd_files[] :: The RRD file to operate on. It needs to exist at the time it is called.
        Default :: undef

The following are optional and will be passed to to 

    CF
    resolution
    backoff
    retries

=cut

sub new {
	my ( $empty, %opts ) = @_;

	my $self = {
		CF            => 'AVERAGE',
		retries       => 3,
		backoff       => 1,
		rrd_files     => [],
		perror        => undef,
		error         => undef,
		errorLine     => undef,
		errorFilename => undef,
		errorString   => "",
		errorExtra    => {
			all_errors_fatal => 0,
			flags            => {
				1 => 'rrd_files_undef',
				2 => 'wrong_ref_type',
			},
			fatal_flags => {
				'not_a_file'     => 1,
				'rrd_file_undef' => 1,
			},
			perror_not_fatal => 0,
		},
	};
	bless $self;

	if ( !defined( $opts{'rrd_files'} ) ) {
		$self->{perror}      = 1;
		$self->{error}       = 1;
		$self->{errorString} = '$opts{rrd_files} is undef';
		$self->warn;
		return $self;
	}

	if ( ref( $opts{'rrd_files'} ) ne 'ARRAY' ) {
		$self->{perror}      = 1;
		$self->{error}       = 2;
		$self->{errorString} = '$opts{rrd_files} is of ref type "' . ref( $opts{rrd_file} ) . '" and not "ARRAY"';
		$self->warn;
		return $self;
	}

	my @read_in = ( 'resolution', 'backoff', 'retries', 'CF' );
	foreach my $to_read_in (@read_in) {
		if ( defined( $opts{$to_read_in} ) ) {
			$self->{$to_read_in} = $opts{$to_read_in};
		}
	}

	my $rrd_files_int = 0;
	while ( defined( $opts{'rrd_files'}[$rrd_files_int] ) ) {
		if ( ref( $opts{'rrd_files'}[$rrd_files_int] ) ne '' ) {
			$self->{perror} = 1;
			$self->{error}  = 2;
			$self->{errorString}
				= '$opts{rrd_files}[' . $rrd_files_int . '] is of ref type "' . ref( $opts{rrd_file} ) . '" and not ""';
			$self->warn;
			return $self;
		}

		my $rrd_fetcher;
		eval {
			$rrd_fetcher = RRD::Fetch->new(
				'rrd_file'   => $opts{'rrd_files'}[$rrd_files_int],
				'CF'         => $self->{'CF'},
				'retries'    => $self->{'retries'},
				'backoff'    => $self->{'backoff'},
				'resolution' => $self->{'resolution'},
			);
			if ( !defined($rrd_fetcher) ) {
				die(      'RRD::Fetcher->new(rrd_file=>"'
						. $opts{'rrd_files'}[$rrd_files_int]
						. '", CF=>"'
						. $self->{'CF'}
						. '", retries=>"'
						. $self->{'retries'}
						. '", backoff=>"'
						. $self->{'backoff'}
						. '", resolution=>"'
						. $self->{'resolution'}
						. '") returned undef' );
			} ## end if ( !defined($rrd_fetcher) )
		};
		if ($@) {
			$self->{perror}      = 1;
			$self->{error}       = 3;
			$self->{errorString} = 'Failed to init RRD::Fetcher... ' . $@;
			$self->warn;
			return $self;
		}

		$rrd_files_int++;
	} ## end while ( defined( $opts{'rrd_files'}[$rrd_files_int...]))

	return $self;
} ## end sub new

sub run {
	my ( $self, %opts ) = @_;

	if ( !$self->errorblank ) {
		return undef;
	}

	if ( !defined( $opts{start} ) ) {
		$self->{error}       = 8;
		$self->{errorString} = '$opts{start} is undef';
		$self->warn;
	} elsif ( ref( $opts{start} ) ne '' ) {
		$self->{error}       = 4;
		$self->{errorString} = '$opts{start} is of ref type "' . ref( $opts{start} ) . '" and not ""';
		$self->warn;
	} elsif ( $opts{start} !~ /\d\d\d\d[01]\d[0123]\d/ ) {
		$self->{error} = 12;
		$self->{errorString}
			= '$opts{start} set to "'
			. $opts{start}
			. '" which does not appear to be %Y%m%d or /\d\d\d\d[01]\d[0123]\d/';
		$self->warn;
	}

	if ( !defined( $opts{for} ) ) {
		$opts{for} = 7;
	} elsif ( ref( $opts{for} ) ne '' ) {
		$self->{error}       = 4;
		$self->{errorString} = '$opts{for} is of ref type "' . ref( $opts{for} ) . '" and not ""';
		$self->warn;
	} elsif ( $opts{for} !~ /\d+/ ) {
		$self->{error}       = 5;
		$self->{errorString} = '$opts{for}, "' . $opts{for} . '", does not appear to be a int';
		$self->warn;
	}

	my $t;
	eval {
		$t = Time::Piece->strptime( $opts{start}, '%Y%m%d' );
		if ( !defined($t) ) {
			die('Time::Piece->strptime returned undef');
		}
	};
	if ($@) {
		$self->{error}       = 13;
		$self->{errorString} = '$opts{start}, "' . $opts{start} . '", failed parsing... ' . $@;
		$self->warn;
	}

	my $to_return = {
		'columns' => [],
		'dates'   => [],
		'max'     => {},
	};

	my $day = 1;
	while ( $day <= $opts{for} ) {
		my $current_day = $t->strftime('%Y%m%d');
		push( @{ $to_return->{'dates'} }, $current_day );

		my $day_results = $self->fetch_joined( 'start' => $current_day, 'end' => '+1day' );

		if ( !$day_results->{'success'} ) {
			$self->{error} = 14;
			$self->{errorString}
				= '$day_results->{success} is false... called "$self->(start=>"'
				. $current_day
				. '", end=>\'+1day\');"...';
			$self->warn;
		}

		if ( $day == 1 ) {
			$to_return->{'columns'} = $day_results->{'columns'};
		}

		$to_return->{'max'}{$current_day}    = {};
		$to_return->{'min'}{$current_day}    = {};
		$to_return->{'mean'}{$current_day}   = {};
		$to_return->{'mode'}{$current_day}   = {};
		$to_return->{'median'}{$current_day} = {};
		$to_return->{'sum'}{$current_day}    = {};
		foreach my $column ( @{ $to_return->{'columns'} } ) {
			my @values;
			foreach my $current_value ( @{ $day_results->{'data'}{$column} } ) {
				if ( defined($current_value) && $current_value !~ /[Nn][Aa][Nn]/ ) {
					push( @values, $current_value );
				}
			}
			$to_return->{'max'}{$current_day}{$column}    = sprintf( '%.12f', max(@values) );
			$to_return->{'min'}{$current_day}{$column}    = sprintf( '%.12f', min(@values) );
			$to_return->{'sum'}{$current_day}{$column}    = sprintf( '%.12f', sum(@values) );
			$to_return->{'mean'}{$current_day}{$column}   = sprintf( '%.12f', mean(@values) );
			$to_return->{'mode'}{$current_day}{$column}   = sprintf( '%.12f', mode(@values) );
			$to_return->{'median'}{$current_day}{$column} = sprintf( '%.12f', median(@values) );
		} ## end foreach my $column ( @{ $to_return->{'columns'}...})

		$t += 86400;
		$day++;
	} ## end while ( $day <= $opts{for} )

	return $to_return;
} ## end sub run

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
