<?php

// Test Provider (prototype) — PHP port of the canonical ts/provider.ts.
//
// Reads the shared corpus (build/test/test.json) and hands test code clean,
// normalized cases. It is NOT a test runner: it never calls the subject and
// never asserts. See ../PROVIDER.md for the model and ../AGENTS.md for usage.
//
// Zero runtime dependencies (stdlib only), matching repo policy.

declare(strict_types=1);

namespace Voxgig\Struct\Proto;

const NULLMARK   = '__NULL__';
const UNDEFMARK  = '__UNDEF__';
const EXISTSMARK = '__EXISTS__';

// Sentinel distinguishing "key absent" from "value is null" in getpath.
final class Missing
{
    private static ?Missing $instance = null;

    public static function get(): Missing
    {
        if (self::$instance === null) {
            self::$instance = new Missing();
        }
        return self::$instance;
    }
}

// Default corpus path: build/test/test.json relative to the repo root.
function default_test_file(): string
{
    return __DIR__ . '/../../../build/test/test.json';
}

final class TestProvider
{
    /** @var mixed */
    public $spec;

    /** @param mixed $spec */
    public function __construct($spec)
    {
        $this->spec = $spec;
    }

    public static function load(?string $testfile = null): TestProvider
    {
        $file = $testfile ?? default_test_file();
        $txt = file_get_contents($file);
        if ($txt === false) {
            throw new \Exception("Unable to read test file at $file");
        }
        // Decode objects as ordered assoc arrays (key order preserved).
        return new TestProvider(json_decode($txt, true));
    }

    /** @return mixed */
    public function raw()
    {
        return $this->spec;
    }

    /**
     * @return array<string,mixed>
     */
    private function fnNode(string $fn): array
    {
        $node = null;
        if (is_array($this->spec) && array_key_exists('struct', $this->spec)
            && is_array($this->spec['struct']) && array_key_exists($fn, $this->spec['struct'])) {
            $node = $this->spec['struct'][$fn];
        } elseif (is_array($this->spec) && array_key_exists($fn, $this->spec)) {
            $node = $this->spec[$fn];
        }
        if ($node === null) {
            throw new \Exception("Unknown function: $fn");
        }
        return $node;
    }

    /**
     * @return string[]
     */
    public function functions(): array
    {
        $root = (is_array($this->spec) && array_key_exists('struct', $this->spec))
            ? $this->spec['struct']
            : $this->spec;
        $out = [];
        foreach (array_keys($root) as $k) {
            if (is_group_bag($root[$k]) || has_groups($root[$k])) {
                $out[] = (string)$k;
            }
        }
        return $out;
    }

    /**
     * @return string[]
     */
    public function groups(string $fn): array
    {
        $node = $this->fnNode($fn);
        $out = [];
        foreach (array_keys($node) as $k) {
            if ($k !== 'name' && is_group_bag($node[$k])) {
                $out[] = (string)$k;
            }
        }
        return $out;
    }

    /**
     * @return array<int,array<string,mixed>>
     */
    public function entries(string $fn, ?string $group = null): array
    {
        $node = $this->fnNode($fn);
        $groups = $group !== null ? [$group] : $this->groups($fn);
        $out = [];
        foreach ($groups as $g) {
            $bag = $node[$g] ?? null;
            if (!is_group_bag($bag)) {
                continue;
            }
            $set = $bag['set'];
            $n = count($set);
            for ($i = 0; $i < $n; $i++) {
                $out[] = normalize($fn, $g, $i, $set[$i]);
            }
        }
        return $out;
    }
}

// A "list" array is one whose keys are 0..n-1 sequential. Otherwise (incl.
// empty assoc test we treat empties as lists) it is a map.
function is_list_array(array $v): bool
{
    if ($v === []) {
        return true;
    }
    return array_keys($v) === range(0, count($v) - 1);
}

// A group bag is a map with a `set` list.
/** @param mixed $v */
function is_group_bag($v): bool
{
    return is_array($v) && !is_list_array($v)
        && array_key_exists('set', $v) && is_array($v['set']) && is_list_array($v['set']);
}

// A function node has at least one child group bag.
/** @param mixed $v */
function has_groups($v): bool
{
    if (!is_array($v) || is_list_array($v)) {
        return false;
    }
    foreach (array_keys($v) as $k) {
        if ($k !== 'name' && is_group_bag($v[$k])) {
            return true;
        }
    }
    return false;
}

/**
 * @param array<string,mixed> $raw
 * @return array<string,mixed>
 */
function normalize(string $fn, string $group, int $index, array $raw): array
{
    return [
        'function' => $fn,
        'group'    => $group,
        'index'    => $index,
        'id'       => (array_key_exists('id', $raw) && $raw['id'] !== null) ? (string)$raw['id'] : null,
        'doc'      => array_key_exists('doc', $raw) && $raw['doc'] === true,
        'client'   => (array_key_exists('client', $raw) && $raw['client'] !== null) ? (string)$raw['client'] : null,
        'input'    => resolve_input($raw),
        'expect'   => resolve_expect($raw),
        'raw'      => $raw,
    ];
}

/**
 * @param array<string,mixed> $raw
 * @return array<string,mixed>
 */
function resolve_input(array $raw): array
{
    if (array_key_exists('ctx', $raw)) {
        return ['kind' => 'ctx', 'ctx' => $raw['ctx']];
    }
    if (array_key_exists('args', $raw)) {
        return ['kind' => 'args', 'args' => $raw['args']];
    }
    return ['kind' => 'in', 'in' => array_key_exists('in', $raw) ? $raw['in'] : null];
}

/**
 * @param mixed $err
 * @return array<string,mixed>
 */
function parse_err($err): array
{
    if ($err === true) {
        return ['any' => true, 'text' => null, 'regex' => false];
    }
    if (is_string($err)) {
        if (preg_match('/^\/(.+)\/$/', $err, $m)) {
            return ['any' => false, 'text' => $m[1], 'regex' => true];
        }
        return ['any' => false, 'text' => $err, 'regex' => false];
    }
    // Non-true, non-string err spec: treat as "any error".
    return ['any' => true, 'text' => null, 'regex' => false];
}

/**
 * @param array<string,mixed> $raw
 * @return array<string,mixed>
 */
function resolve_expect(array $raw): array
{
    $hasMatch = array_key_exists('match', $raw);
    $matchPart = $hasMatch ? $raw['match'] : null;
    if (array_key_exists('err', $raw)) {
        $e = ['kind' => 'error', 'error' => parse_err($raw['err'])];
        if ($hasMatch) {
            $e['match'] = $matchPart;
        }
        return $e;
    }
    if (array_key_exists('out', $raw)) {
        $e = ['kind' => 'value', 'value' => $raw['out']];
        if ($hasMatch) {
            $e['match'] = $matchPart;
        }
        return $e;
    }
    if ($hasMatch) {
        return ['kind' => 'match', 'match' => $raw['match']];
    }
    return ['kind' => 'absent'];
}

// ─── pure comparison helpers ───────────────────────────────────────────────

/** @param mixed $x */
function stringify($x): string
{
    if (is_string($x)) {
        return $x;
    }
    return json_encode($x);
}

/**
 * @param mixed $x
 * @return mixed
 */
function norm_null($x)
{
    if ($x === NULLMARK || $x === null) {
        return null;
    }
    if (is_array($x)) {
        $o = [];
        foreach ($x as $k => $v) {
            $o[$k] = norm_null($v);
        }
        return $o;
    }
    return $x;
}

/**
 * @param mixed $x
 * @return mixed
 */
function norm_mark($x)
{
    if ($x === NULLMARK) {
        return null;
    }
    if (is_array($x)) {
        $o = [];
        foreach ($x as $k => $v) {
            $o[$k] = norm_mark($v);
        }
        return $o;
    }
    return $x;
}

/**
 * @param mixed $check
 * @param mixed $base
 */
function matchval($check, $base): bool
{
    if ($check === $base) {
        return true;
    }
    if (is_string($check)) {
        $basestr = stringify($base);
        if (preg_match('/^\/(.+)\/$/', $check, $m)) {
            return preg_match('/' . $m[1] . '/', $basestr) === 1;
        }
        return mb_stripos($basestr, $check) !== false;
    }
    if (is_callable($check)) {
        return true;
    }
    return false;
}

/**
 * @param mixed $expected
 * @param mixed $actual
 */
function equal($expected, $actual): bool
{
    return deep_eq(norm_null($expected), norm_null($actual));
}

// Strict variant for the runner's `{ null: false }` functions, where an absent
// value is distinct from JSON null. Only __NULL__ is normalized.
/**
 * @param mixed $expected
 * @param mixed $actual
 */
function equal_strict($expected, $actual): bool
{
    return deep_eq(norm_mark($expected), norm_mark($actual));
}

/**
 * @param mixed $a
 * @param mixed $b
 */
function deep_eq($a, $b): bool
{
    if ($a === $b) {
        return true;
    }
    if (is_array($a) && is_array($b)) {
        $al = is_list_array($a);
        $bl = is_list_array($b);
        if ($al !== $bl) {
            return false;
        }
        if ($al) {
            if (count($a) !== count($b)) {
                return false;
            }
            for ($i = 0; $i < count($a); $i++) {
                if (!array_key_exists($i, $b) || !deep_eq($a[$i], $b[$i])) {
                    return false;
                }
            }
            return true;
        }
        $ak = array_keys($a);
        $bk = array_keys($b);
        if (count($ak) !== count($bk)) {
            return false;
        }
        foreach ($ak as $k) {
            if (!array_key_exists($k, $b) || !deep_eq($a[$k], $b[$k])) {
                return false;
            }
        }
        return true;
    }
    return false;
}

/**
 * @param array<string,mixed> $check ErrorCheck {any,text,regex}
 */
function error_matches(array $check, string $message): bool
{
    if ($check['any']) {
        return true;
    }
    if ($check['text'] === null) {
        return false;
    }
    if ($check['regex']) {
        return preg_match('/' . $check['text'] . '/', $message) === 1;
    }
    return mb_stripos(mb_strtolower($message), mb_strtolower((string)$check['text'])) !== false;
}

// Partial structural match: every leaf of `check` must match `base` at its path.
/**
 * @param mixed $check
 * @param mixed $base
 * @return array<string,mixed>
 */
function struct_match($check, $base): array
{
    $result = ['ok' => true];
    walk_leaves($check, [], function ($val, $path) use (&$result, $base) {
        if (!$result['ok']) {
            return;
        }
        $baseval = sm_getpath($base, $path);
        if ($baseval === $val) {
            return;
        }
        if ($val === UNDEFMARK && $baseval === Missing::get()) {
            return;
        }
        if ($val === EXISTSMARK && $baseval !== Missing::get() && $baseval !== null) {
            return;
        }
        if (!matchval($val, $baseval === Missing::get() ? null : $baseval)) {
            $result = [
                'ok'       => false,
                'path'     => $path,
                'expected' => $val,
                'actual'   => $baseval === Missing::get() ? null : $baseval,
            ];
        }
    });
    return $result;
}

/** @param mixed $v */
function is_node($v): bool
{
    return is_array($v);
}

/**
 * @param mixed $node
 * @param string[] $path
 */
function walk_leaves($node, array $path, callable $fn): void
{
    if (is_array($node) && is_list_array($node)) {
        foreach ($node as $i => $v) {
            walk_leaves($v, array_merge($path, [(string)$i]), $fn);
        }
    } elseif (is_node($node)) {
        foreach ($node as $k => $v) {
            walk_leaves($v, array_merge($path, [(string)$k]), $fn);
        }
    } else {
        $fn($node, $path);
    }
}

/**
 * @param mixed $store
 * @param string[] $path
 * @return mixed Missing sentinel if absent.
 */
function sm_getpath($store, array $path)
{
    $cur = $store;
    foreach ($path as $key) {
        if ($cur === null) {
            return Missing::get();
        }
        if (is_array($cur)) {
            if (is_list_array($cur)) {
                $idx = (int)$key;
                if (!array_key_exists($idx, $cur)) {
                    return Missing::get();
                }
                $cur = $cur[$idx];
            } else {
                if (!array_key_exists($key, $cur)) {
                    return Missing::get();
                }
                $cur = $cur[$key];
            }
        } else {
            return Missing::get();
        }
    }
    return $cur;
}
