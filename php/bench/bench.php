<?php
// Performance bench for the PHP port. Emits one JSON line per
// build/bench/README.md; diagnostics go to stderr.
require_once __DIR__ . '/../src/Struct.php';

use Voxgig\Struct\Struct;

function envi($k, $d) {
    $v = getenv($k);
    return ($v !== false && ctype_digit($v)) ? intval($v) : $d;
}

$W = envi('BENCH_WIDTH', 5);
$D = envi('BENCH_DEPTH', 6);
$WARM = envi('BENCH_WARMUP', 3);
$RUNS = envi('BENCH_RUNS', 21);
$GP = envi('BENCH_GETPATH_ITERS', 50000);

function build($w, $d, $leaf) {
    if ($d == 0) return $leaf;
    $o = [];
    for ($i = 0; $i < $w; $i++) $o['k' . $i] = build($w, $d - 1, $leaf);
    return $o;
}

function nodecount($w, $d) {
    $n = 0; $p = 1;
    for ($i = 0; $i <= $d; $i++) { $n += $p; $p *= $w; }
    return $n;
}

$sink = 0;

function measure($warm, $runs, $fn) {
    for ($i = 0; $i < $warm; $i++) $fn();
    $t = [];
    for ($r = 0; $r < $runs; $r++) {
        $a = hrtime(true);
        $fn();
        $b = hrtime(true);
        $t[] = ($b - $a) / 1e6;
    }
    sort($t);
    return ['min_ms' => $t[0], 'median_ms' => $t[intdiv(count($t), 2)],
            'mean_ms' => array_sum($t) / count($t)];
}

$tree = build($W, $D, 0);
$nodes = nodecount($W, $D);
$treeA = build($W, $D, 1);
$treeB = build($W, $D, 2);
$path = implode('.', array_fill(0, $D, 'k0'));
$cb = function ($key, $val, $parent, $p) use (&$sink) { $sink += count($p); return $val; };

$specs = [
    ['clone', $nodes, function () use (&$sink, $tree) { $sink += Struct::clone($tree) ? 1 : 0; }],
    ['walk', $nodes, function () use ($tree, $cb) { Struct::walk($tree, $cb); }],
    ['merge', $nodes, function () use (&$sink, $treeA, $treeB) { $sink += Struct::merge([$treeA, $treeB]) ? 1 : 0; }],
    ['stringify', $nodes, function () use (&$sink, $tree) { $sink += strlen(Struct::stringify($tree)); }],
    ['getpath', $GP, function () use (&$sink, $tree, $path, $GP) {
        $s = 0;
        for ($i = 0; $i < $GP; $i++) $s += Struct::getpath($tree, $path) === 0 ? 1 : 0;
        $sink += $s;
    }],
];

$ops = [];
foreach ($specs as [$op, $uc, $fn]) {
    $ops[] = array_merge(['op' => $op, 'runs' => $RUNS, 'unit_count' => $uc],
                         measure($WARM, $RUNS, $fn));
}

fwrite(STDERR, "php: sink=$sink\n");
echo json_encode([
    'lang' => 'php',
    'runtime' => 'php ' . PHP_VERSION,
    'nodes' => $nodes,
    'params' => ['width' => $W, 'depth' => $D, 'warmup' => $WARM,
                 'runs' => $RUNS, 'getpath_iters' => $GP],
    'ops' => $ops,
]), "\n";
