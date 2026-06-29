#!/usr/bin/env perl
# Universal struct smoke: getpath({ db => { host => 'localhost' } }, 'db.host').
# Run against the lib/ of the LIVE dist downloaded from CPAN (see verify-perl).
use strict;
use warnings;
use Voxgig::Struct qw();

my $store = { db => { host => 'localhost' } };
my $got = Voxgig::Struct::getpath($store, 'db.host');

if (defined $got && $got eq 'localhost') {
    print "OK perl: getpath(db.host) = localhost\n";
    exit 0;
}

printf "FAIL perl: getpath(db.host) = %s (want localhost)\n",
    defined $got ? $got : 'undef';
exit 1;
