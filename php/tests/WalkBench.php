<?php

// Walk benchmark. Gated on WALK_BENCH=1 env var.
// Run: WALK_BENCH=1 php tests/WalkBench.php

require_once __DIR__ . '/../src/Struct.php';

use Voxgig\Struct\Struct;

if ((getenv('WALK_BENCH') ?: '0') !== '1') {
    fwrite(STDERR, "Skipping walk benchmark (set WALK_BENCH=1 to run)\n");
    exit(0);
}

function buildTree(int $width, int $depth): array
{
    if ($depth === 0) {
        return ['leaf' => 1];
    }
    $node = [];
    for ($i = 0; $i < $width; $i++) {
        $node['c' . $i] = buildTree($width, $depth - 1);
    }
    return $node;
}

function countNodes(mixed $v): int
{
    if (is_array($v)) {
        $n = 1;
        foreach ($v as $child) {
            $n += countNodes($child);
        }
        return $n;
    }
    if (is_object($v)) {
        $n = 1;
        foreach (get_object_vars($v) as $child) {
            $n += countNodes($child);
        }
        return $n;
    }
    return 1;
}

function benchOne(string $label, int $width, int $depth, int $iters): void
{
    $tree = buildTree($width, $depth);
    $nodes = countNodes($tree);

    // Warmup
    for ($i = 0; $i < 2; $i++) {
        Struct::walk($tree, function ($_k, $v, $_p, $_path) {
            return $v;
        });
    }

    $t0 = hrtime(true);
    for ($i = 0; $i < $iters; $i++) {
        Struct::walk($tree, function ($_k, $v, $_p, $_path) {
            return $v;
        });
    }
    $t1 = hrtime(true);

    $elapsedNs = $t1 - $t0;
    $totalVisits = $iters * $nodes;
    $nsPerNode = $elapsedNs / $totalVisits;

    printf(
        "%-28s w=%-4d d=%-3d nodes=%-7d iters=%-5d total=%.2f ms  ns/node=%.1f\n",
        $label,
        $width,
        $depth,
        $nodes,
        $iters,
        $elapsedNs / 1e6,
        $nsPerNode
    );
}

// Iteration counts tuned so each scenario runs quickly while visiting enough
// nodes to make ns/node meaningful. Sizes are intentionally modest so the
// baseline (pre-optimization) fits in 512M memory while still producing
// enough total visits for ns/node to stabilize.
benchOne('wide+deep',   8,    6,  3);     // ~299k nodes
benchOne('very-wide',   1000, 2,  5);     // ~1.001m nodes
benchOne('very-deep',   2,    14, 30);    // ~32k nodes per tree, d=14
