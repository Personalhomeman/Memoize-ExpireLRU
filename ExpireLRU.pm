###########################################################################
# File    - ExpireLRU.pm
#	    Created 12 Feb, 2000, Brent B. Powers
#
# Purpose - This package implements LRU expiration. It does this by
#	    using a bunch of different data structures. Tuning
#	    support is included, but costs performance.
#
# ToDo    - Test the further tie stuff
#
# Copyright(c) 2000 Brent B. Powers and B2Pi LLC
#
# You may copy and distribute this program under the same terms as
# Perl itself.
#
###########################################################################
package Memoize::ExpireLRU;

use strict;
use Carp;
use vars qw($DEBUG $VERSION);

$DEBUG = 0;
$VERSION = '0.53';

# Usage:  memoize func ,
# 		TIE => [
# 			Memoize::ExpireLRU,
# 			CACHESIZE => n,
# 			TUNECACHESIZE => m,
#			INSTANCE => IDString
# 			TIE => [...]
# 		       ]

my(@AllTies);

1;

sub TIEHASH {
    my ($package, %args, %cache, @index, @Tune, @Stats);
    ($package, %args)= @_;
    $args{CACHESIZE} or croak "Memoize::ExpireLRU: CACHESIZE must be specified; aborting";
    $args{TUNECACHESIZE} ||= 0;
    $args{C} = \%cache;
    $args{I} = \@index;
    if ($args{TUNECACHESIZE}) {
	my($i);
	for ($i = 0; $i < $args{TUNECACHESIZE}; $i++) {
	    $Stats[$i] = 0;
	}
	$args{T} = \@Stats;
	$args{TI} = \@Tune;
	$args{cm} = $args{ch} = $args{th} = 0;
    }

    if ($args{TIE}) {
	my($module, $modulefile, @opts, $rc, %tcache);
	($module, @opts) = @{$args{TIE}};
	$modulefile = $module . '.pm';
	$modulefile =~ s{::}{/}g;
	eval { require $modulefile };
	if ($@) {
	    croak "Memoize::ExpireLRU: Couldn't load hash tie module `$module': $@; aborting";
	}
	$rc = (tie %tcache => $module, @opts);
	unless ($rc) {
	    croak "Memoize::ExpireLRU: Couldn't tie hash to `$module': $@; aborting";
	}

	## Preload our cache
	foreach (keys %tcache) {
	    $args{C}->{$_} = $tcache{$_}
	}
	$args{TC} = \%tcache;
    }
    push(@AllTies, \%args);
    bless \%args => $package;
}

sub EXISTS {
    my($self, $key) = @_;

    $DEBUG and print STDERR " >> Exists $key\n";

    if (exists $self->{C}->{$key}) {
	## Take care of tune stat's in the FETCH
	$self->{ch}++ if exists($self->{TUNECACHESIZE});
	return 1;
    } else {
	$DEBUG and print STDERR "    Not in underlying hash at all.\n";
	if (exists($self->{TUNECACHESIZE})) {
	    $self->{cm}++;
 	    ## Ughhh. A linear search
	    for (my $i = $self->{CACHESIZE}; $i < $#{$self->{T}}; $i++) {
		next unless defined($self->{TI}->[$i]->{k})
			&& $self->{TI}->[$i]->{k} == $key;
		$self->{T}->[$i]++;
		$self->{th}++;
		return 0;
	    }
	}
	return 0;
    }
}

sub FETCH {
    my($self, $key) = @_;
    my($value, $t, $i);
    $DEBUG and print STDERR " >> Fetch cached value for $key\n";

    $value = $self->{C}->{$key}->{v};

    ## Now, we need to
    ##    1. Find the old entry in the array (and do the stat's)
    $i = _find($self->{I}, $self->{C}->{$key}->{t}, $key);

    ##    2. Remove the old entry from the array
    $t = splice(@{$self->{I}}, $i, 1);
    ##    3. Update the timestamp of the new array
    $self->{C}->{$key}->{t} = $t->{t} = time;
    ##    4. Store the updated entry back in the array as the MRU
    unshift(@{$self->{I}}, $t);

    ## Deal with the Tuning stuff
    if (defined($self->{T})) {
	$self->{T}->[$i]++;
	splice(@{$self->{TI}}, $i, 1);
	unshift(@{$self->{TI}}, $t);
    }

    ## Finally, return the data
    return $value;
}

sub STORE {
    my ($self, $key, $value) = @_;
    $DEBUG and print STDERR " >> Store $key $value\n";

    my(%r, %t);
    $t{t} = $r{t} = time;
    $r{v} = $value;
    $t{k} = $key;

    # Store the value into the hash
    $self->{C}->{$key} = \%r;
    ## As well as the tied cache, if it exists
    $self->{TC}->{$key} = $value if defined($self->{TC});

    # By definition, this item is the MRU, so add it to the beginning
    # of the LRU queue. Since this is a STORE, we know it doesn't already
    # exist.
    unshift(@{$self->{I}}, \%t);

    ## Do we have too many entries?
    while (scalar(@{$self->{I}}) > $self->{CACHESIZE}) {
	## Chop off whatever is at the end
	## Get the key
	$key = pop(@{$self->{I}});
	delete($self->{C}->{$key->{k}});
	delete($self->{TC}->{$key->{k}}) if defined($self->{TC});
    }

    ## Now, what about the Tuning Index
    if (defined($self->{T})) {
	## Same as above.
	unshift(@{$self->{TI}}, \%t);
	if (scalar(@{$self->{TI}}) > $self->{TUNECACHESIZE}) {
	    $#{$self->{TI}} = $self->{TUNECACHESIZE} - 1;
	}
    }

    $value;
}

sub _find ( $$$ ) {
    my($Aref, $time, $key) = @_;
    my($t, $b, $n, $l);

    $t = $#{$Aref};
    $n = $b = 0;
    $l = -2;

    while ($time != $Aref->[$n]->{t}) {
	if ($time < $Aref->[$n]->{t}) {
	    $b = $n;
	} else {
	    $t = $n;
	}
	if ($t <= $b) {
	    ## Trouble, we're out.
	    if ($Aref->[$t]->{t} == $time) {
		$n = $t;
	    } elsif ($Aref->[$b]->{t} == $time) {
		$n = $b;
	    } else {
		## Really big trouble
		## Complain loudly
		print "Trouble\n";
		return undef;
	    }
	} else {
	    $n = $b + (($t - $b) >> 1);
	    $n++ if $l == $n;
	    $l = $n;
	}
    }
    ## Drop down in the array until the time isn't the time
    while (($n > 0) && ($time == $Aref->[$n-1]->{t})) {
	$n--;
    }
    while (($time == $Aref->[$n]->{t}) && ($key ne $Aref->[$n]->{k})) {
	$n++;
    }
    if ($key ne $Aref->[$n]->{k}) {
	## More big trouble
	print "More trouble\n";
	return undef;
    }
    $DEBUG and print STDERR " >> Returning $n value\n";
    return $n;
}

sub END {
    my($k) = 0;
    my($self);
    foreach $self (@AllTies) {
	next unless defined($self->{T});
	print STDERR "ExpireLRU Statistics:\n" unless $k;
	$k++;
	my($name) = $self->{INSTANCE} || $self;
	print STDERR <<EOS;

		   ExpireLRU instantiation: $name
				Cache Size: $self->{CACHESIZE}
		   Experimental Cache Size: $self->{TUNECACHESIZE}
				Cache Hits: $self->{ch}
			      Cache Misses: $self->{cm}
Additional Cache Hist at Experimental Size: $self->{th}
			     Distribution :
EOS
	for (my $i = 1; $i <= $self->{TUNECACHESIZE}; $i++) {
	    printf STDERR "				      %3d : %s\n",
		    $i, $self->{T}->[$i-1];
	}
    }
}

__END__

=head1 NAME

Memoize - Expiry plug-in for Memoize that adds LRU cache expiration

=head1 SYNOPSIS

    use Memoize;

    memoize('slow_function',
	    TIE => [Memoize::ExpireLRU,
		    CACHESIZE => n,
	           ]);

Note that one need not C<use> this module. It will be found by the
Memoize module.

The argument to CACHESIZE must be an integer. Normally, this is all
that is needed. Additional options are available:

	TUNECACHESIZE => m,
	INSTANCE => 'descriptive_name',
	TIE => '[DB_File, $filename, O_RDWR | O_CREATE, 0666]'

=head1 DESCRIPTION

For the theory of Memoization, please see the Memoize module
documentation. This module implements an expiry policy for Memoize
that follows LRU semantics, that is, the last n results, where n is
specified as the argument to the C<CACHESIZE> parameter, will be
cached.

=head1 PERFORMANCE TUNING

It is often quite difficult to determine what size cache will give
optimal results for a given function. To aid in determining this,
ExpireLRU includes cache tuning support. Enabling this causes a
definite performance hit, but it is often useful before code is
released to production.

To enable cache tuning support, simply specify the optional
C<TUNECACHESIZE> parameter with a size greater than that of the
C<CACHESIZE> parameter.

When the program exits, a set of statistics will be printed to
stderr. If multiple routines have been memoized, separate sets of
statistics are printed for each routine. The default names are
somewhat cryptic: this is the purpose of the C<INSTANCE>
parameter. The value of this parameter will be used as the identifier
within the statistics report.

=head1 AUTHOR

Brent B. Powers (B2Pi), Powers@B2Pi.com

Copyright(c) 1999 Brent B. Powers. All rights reserved. This program
is free software, you may redistribute it and/or modify it under the
same terms as Perl itself.

=head1 SEE ALSO

Memoize

=cut
