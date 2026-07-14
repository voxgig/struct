#!/usr/bin/env perl
# Performance bench for the Perl port. Emits one JSON line per
# build/bench/README.md; diagnostics go to stderr.
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Voxgig::Struct qw();
use Time::HiRes qw(clock_gettime CLOCK_MONOTONIC);
use JSON::PP;

sub envi {
    my ($k, $d) = @_;
    my $v = $ENV{$k};
    (defined $v && $v =~ /^\d+$/) ? $v + 0 : $d;
}

my $W    = envi('BENCH_WIDTH', 5);
my $D    = envi('BENCH_DEPTH', 6);
my $WARM = envi('BENCH_WARMUP', 3);
my $RUNS = envi('BENCH_RUNS', 21);
my $GP   = envi('BENCH_GETPATH_ITERS', 2000);

sub build {
    my ($w, $d, $leaf) = @_;
    return $leaf if $d == 0;
    my %h;
    $h{"k$_"} = build($w, $d - 1, $leaf) for (0 .. $w - 1);
    return \%h;
}

sub nodecount {
    my ($w, $d) = @_;
    my ($n, $p) = (0, 1);
    for (0 .. $d) { $n += $p; $p *= $w; }
    return $n;
}

my $sink = 0;

sub measure {
    my ($warm, $runs, $fn) = @_;
    $fn->() for (1 .. $warm);
    my @t;
    for (1 .. $runs) {
        my $a = clock_gettime(CLOCK_MONOTONIC);
        $fn->();
        my $b = clock_gettime(CLOCK_MONOTONIC);
        push @t, ($b - $a) * 1000;
    }
    @t = sort { $a <=> $b } @t;
    my $s = 0; $s += $_ for @t;
    return (min_ms => $t[0], median_ms => $t[int(@t / 2)], mean_ms => $s / @t);
}

my $tree  = build($W, $D, 0);
my $nodes = nodecount($W, $D);
my $treeA = build($W, $D, 1);
my $treeB = build($W, $D, 2);
my $path  = join('.', ('k0') x $D);
my $cb = sub { my ($key, $val, $parent, $p) = @_; $sink += scalar(@$p); return $val; };

my @ops;
push @ops, { op => 'clone', runs => $RUNS, unit_count => $nodes,
    measure($WARM, $RUNS, sub { $sink += Voxgig::Struct::clone($tree) ? 1 : 0 }) };
push @ops, { op => 'walk', runs => $RUNS, unit_count => $nodes,
    measure($WARM, $RUNS, sub { Voxgig::Struct::walk($tree, $cb, undef, undef) }) };
push @ops, { op => 'merge', runs => $RUNS, unit_count => $nodes,
    measure($WARM, $RUNS, sub { $sink += Voxgig::Struct::merge([$treeA, $treeB]) ? 1 : 0 }) };
push @ops, { op => 'stringify', runs => $RUNS, unit_count => $nodes,
    measure($WARM, $RUNS, sub { $sink += length(Voxgig::Struct::stringify($tree)) }) };
push @ops, { op => 'getpath', runs => $RUNS, unit_count => $GP,
    measure($WARM, $RUNS, sub {
        my $s = 0;
        for (1 .. $GP) {
            my $r = Voxgig::Struct::getpath($tree, $path, undef);
            $s += (defined $r && !ref($r) && $r eq '0') ? 1 : 0;
        }
        $sink += $s;
    }) };

print STDERR "perl: sink=$sink\n";
my $json = JSON::PP->new->canonical(0);
print $json->encode({
    lang    => 'perl',
    runtime => "perl $]",
    nodes   => $nodes,
    params  => { width => $W, depth => $D, warmup => $WARM,
                 runs => $RUNS, getpath_iters => $GP },
    ops     => \@ops,
}), "\n";
