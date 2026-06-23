<?php

// Smoke test for the PHP test provider port. Prints summary stats that must
// match the canonical TS output documented in PROVIDER work.

declare(strict_types=1);

require_once __DIR__ . '/provider.php';

use function Voxgig\Struct\Proto\equal;
use function Voxgig\Struct\Proto\equal_strict;
use function Voxgig\Struct\Proto\error_matches;
use function Voxgig\Struct\Proto\struct_match;

use Voxgig\Struct\Proto\TestProvider;

function bool_str($b): string
{
    return $b ? 'true' : 'false';
}

function val_str($v): string
{
    if ($v === null) {
        return 'null';
    }
    if (is_bool($v)) {
        return bool_str($v);
    }
    if (is_string($v)) {
        return $v;
    }
    return json_encode($v);
}

$prov = TestProvider::load();

$fns = $prov->functions();
echo 'functions: ' . implode(', ', $fns) . "\n";

$total = 0;
$expectKinds = [];
$inputKinds = [];
foreach ($fns as $fn) {
    foreach ($prov->entries($fn) as $entry) {
        $total++;
        $ek = $entry['expect']['kind'];
        $ik = $entry['input']['kind'];
        $expectKinds[$ek] = ($expectKinds[$ek] ?? 0) + 1;
        $inputKinds[$ik] = ($inputKinds[$ik] ?? 0) + 1;
    }
}

echo 'total entries: ' . $total . "\n";

$ekParts = [];
$ekKeys = array_keys($expectKinds);
sort($ekKeys);
foreach ($ekKeys as $k) {
    $ekParts[] = "$k={$expectKinds[$k]}";
}
echo 'expect kinds: ' . implode(', ', $ekParts) . "\n";

$ikParts = [];
$ikKeys = array_keys($inputKinds);
sort($ikKeys);
foreach ($ikKeys as $k) {
    $ikParts[] = "$k={$inputKinds[$k]}";
}
echo 'input kinds: ' . implode(', ', $ikParts) . "\n";

$e = $prov->entries('getpath', 'basic')[0];
echo 'getpath/basic[0]: '
    . "id={$e['id']}, doc=" . bool_str($e['doc']) . ', '
    . "input.kind={$e['input']['kind']}, input.in=" . val_str($e['input']['in']) . ', '
    . "expect.kind={$e['expect']['kind']}, expect.value=" . val_str($e['expect']['value']) . "\n";

// ─── helper sanity checks ──────────────────────────────────────────────────
echo 'equal(null, missing) lenient: ' . bool_str(equal(null, null)) . "\n";
echo 'equal_strict distinguishes null vs __NULL__-collapse: '
    . bool_str(equal_strict(null, '__NULL__')) . ' / '
    . bool_str(equal_strict(null, 1)) . "\n";
echo 'error_matches substring case-insensitive: '
    . bool_str(error_matches(['any' => false, 'text' => 'Foo', 'regex' => false], 'a foobar error')) . "\n";
$sm = struct_match(['a' => ['b' => 2]], ['a' => ['b' => 3]]);
echo 'struct_match failure: ' . json_encode($sm) . "\n";
