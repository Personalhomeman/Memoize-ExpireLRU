#!/usr/local/bin/perl -w
###########################################################################
# File    - test.pl
#	    Created 12 Feb, 2000, Brent B. Powers
#
# Purpose - test for Memoize::ExpireLRU
#
# ToDo    - Test when tied to other module
#
#
###########################################################################
use strict;

use Memoize;

my $n = 0;
use vars qw($dbg);
$dbg = 0;
$| = 1;

print "1..25\n";

++$n;
print "ok $n\n";

my %CALLS = ();
sub routine ( $ ) {
    return shift;
}

sub show ( $ ) {
    print "not " unless shift;
    ++$n;
    print "ok $n\n";
}

memoize('routine',
	SCALAR_CACHE => ['TIE',
			 'Memoize::ExpireLRU',
			 CACHESIZE => 4,
			 TUNECACHESIZE => 8,
			 INSTANCE => 'TEST',
			],
	LIST_CACHE => 'FAULT');

# $Memoize::ExpireLRU::DEBUG = 1;
# $Memoize::ExpireLRU::DEBUG = 0;
show(1);

# 3--6
## Fill the cache
for (0,1,2,3) {
  show(routine($_) == $_);
  $CALLS{$_} = $_;
}

# 7--10
## Ensure that the return values were correct
for (keys %CALLS) {
     show($CALLS{$_} == (0,1,2,3)[$_]);
}

# 11--14
## Check returns from the cache
for (0,1,2,3) {
  show(routine($_) == $_);
}

# 15--18
## Make sure we can get each one of the array
for (0,2,0,0) {
    show(routine($_) == $_);
}

## Make sure we can get each one of the aray, where the timestamps are 
## different
my($i);
for (0,1,2,3) {
    sleep(1);
    $i = routine($_);
}

# 19
show(1);

# 20-23
for (0,2,0,0) {
    show(routine($_) == $_);
}

## Done to here....
## Check getting a new one
## Force the order
for (3,2,1,0) {
    $i = routine($_);
}

# 24--25
## Push off the last one, and ensure that the
## one we pushed off is really pushed off
for (4, 3) {
    show(routine($_) == $_);
}



