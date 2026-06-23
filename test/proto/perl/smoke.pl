#!/usr/bin/env perl
# Smoke test for the Perl test provider port. Prints summary stats that must
# match the canonical TS output documented in PROVIDER.md.

use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
require "$FindBin::Bin/Provider.pm";
Voxgig::Struct::Proto->import(qw(equal equal_strict error_matches struct_match));

sub main {
    my $prov = Voxgig::Struct::Proto->load;

    my $fns = $prov->functions;
    print 'functions: ', join(', ', @$fns), "\n";

    my $total = 0;
    my %expect_kinds;
    my %input_kinds;
    for my $fn (@$fns) {
        for my $entry (@{ $prov->entries($fn) }) {
            $total++;
            $expect_kinds{ $entry->{expect}{kind} }++;
            $input_kinds{ $entry->{input}{kind} }++;
        }
    }

    print "total entries: $total\n";

    # Fixed order to match the documented expected line.
    my @ek_order = qw(value absent match error);
    print 'expect kinds: ',
        join(', ', map { "$_=" . ($expect_kinds{$_} // 0) } @ek_order), "\n";

    my @ik_order = qw(in args ctx);
    print 'input kinds: ',
        join(', ', map { "$_=$input_kinds{$_}" } grep { $input_kinds{$_} } @ik_order),
        "\n";

    my $e = $prov->entries('getpath', 'basic')->[0];
    my $doc = $e->{doc} ? 'true(=1)' : 'false(=0)';
    printf
        "getpath/basic[0]: id=%s, doc=%s, input.kind=%s, expect.kind=%s, expect.value=%s\n",
        $e->{id}, $doc, $e->{input}{kind}, $e->{expect}{kind}, $e->{expect}{value};

    # ─── helper sanity checks ──────────────────────────────────────────────
    print 'equal(undef, missing) lenient: ', (equal(undef, undef) ? 'true' : 'false'), "\n";
    print 'equal_strict(undef, __NULL__): ',
        (equal_strict(undef, '__NULL__') ? 'true' : 'false'),
        ' / equal_strict(undef, 1): ',
        (equal_strict(undef, 1) ? 'true' : 'false'), "\n";
    print 'error_matches substring ci: ',
        (error_matches({ any => 0, text => 'Foo', regex => 0 }, 'a foobar error') ? 'true' : 'false'),
        "\n";
    my $sm = struct_match({ a => { b => 2 } }, { a => { b => 3 } });
    print 'struct_match failure: ',
        sprintf('{ok=%s, path=%s, expected=%s, actual=%s}',
            $sm->{ok} ? 1 : 0,
            join('/', @{ $sm->{path} // [] }),
            $sm->{expected} // '', $sm->{actual} // ''),
        "\n";
}

main();
