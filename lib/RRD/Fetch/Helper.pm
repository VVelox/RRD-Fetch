package RRD::Fetch::Helper;
use base 'Error::Helper';

use 5.006;
use strict;
use warnings;
use Getopt::Long qw( GetOptions );

=head1 NAME

RRD::Fetch - Fetch information from a RRD file.

=head1 VERSION

Version 0.0.1

=cut

our $VERSION = '0.0.1';

=head1 SYNOPSIS

    use RRD::Fetch::Helper;

=head1 METHODS

=head2 new

Initiates the object.

=cut

sub new {
	my ( $empty, %opts ) = @_;

	my $self = {
		perror        => undef,
		error         => undef,
		errorLine     => undef,
		errorFilename => undef,
		errorString   => "",
		errorExtra    => {
			all_errors_fatal => 0,
			flags            => {
				'1' => 'no_action',
				'2' => 'wrong_ref_type',
				'3' => 'opts_data_eval',
				'4' => 'action_eval',
			},
			fatal_flags => {
				'no_action'      => 1,
				'wrong_ref_type' => 1,
				'opts_data_eval' => 1,
				'action_eval'    => 1,
			},
			perror_not_fatal => 0,
		},
	};
	bless $self;

	return $self;
} ## end sub new

sub run {
	my ( $self, %opts ) = @_;

	if ( !$self->errorblank ) {
		return undef;
	}

	if ( !defined( $opts{'action'} ) ) {
		$self->{error}       = 1;
		$self->{errorString} = '$opts{action} is not defiend';
		$self->warn;
	} elsif ( ref( $opts{'action'} ) ne '' ) {
		$self->{error}       = 2;
		$self->{errorString} = 'ref $opts{action} is not "" but "' . ref( $opts{'action'} ) . '"';
		$self->warn;
	}
	my $action = $opts{action};

	# if custom opts are not defined, read the commandline args and fetch what we should use
	my $opts_to_use;
	if ( !defined( $opts{opts} ) ) {
		my %parsed_options;
		# split it appart and remove comments and blank lines
		my $opts_data;
		my $to_eval
			= 'use RRD::Fetch::Helper::' . $action . '; $opts_data=RRD::Fetch::Helper::' . $action . '->opts_data;';
		eval($to_eval);
		if ($@) {
			$self->{error}       = 3;
			$self->{errorString} = 'eval failed for getting opts... "' . $to_eval . '"... ' . $@;
			$self->warn;
		}
		if ( defined($opts_data) ) {
			my @options = split( /\n/, $opts_data );
			@options = grep( !/^#/, @options );
			@options = grep( !/^$/, @options );
			GetOptions( \%parsed_options, @options );
		}
		$opts_to_use = \%parsed_options;
	} else {
		$opts_to_use = $opts{opts};
	}

	# if custom ARGV is specified, use taht
	my $argv_to_use;
	if ( defined( $opts{ARGV} ) ) {
		$argv_to_use = $opts{ARGV};
	} else {
		$argv_to_use = \@ARGV;
	}

	my $action_return;
	my $to_eval
		= 'use RRD::Fetch::Helper::'
		. $action
		. '; $action_return=RRD::Fetch::Helper::'
		. $action
		. '->action(opts=>$opts_to_use, argv=>$argv_to_use);';
	eval($to_eval);
	if ($@) {
		$self->{error}       = 4;
		$self->{errorString} = 'eval failed for action... "' . $to_eval . '"... ' . $@;
		$self->warn;
	}

	return $action_return;
} ## end sub run

=head2

=head1 ERROR CODES/FLAGS

=head2 1/no_action

No action specified.

=head2 2/wrong_ref_type

Wrong ref type supplied for the specified arg.

=head2 3/opts_data_eval

The opts data eval died or errored.

=head2 4/action_eval

The action eval died or errored.

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
