<?php

require_once __DIR__ . '/../src/Struct.php';
require_once __DIR__ . '/omni.php';
require_once __DIR__ . '/SDK.php';

use PHPUnit\Framework\TestCase;
use Voxgig\Struct\Struct;
use Voxgig\Struct\ListRef;
use Voxgig\Struct\Runner;
use Voxgig\Struct\SDK;

/**
 * The corpus is driven by voxgig/omni, via its struct compat shim - see
 * tests/omni.php. Before this, these tests hand-rolled their own loop over
 * `$tests->set`, which understood `in`, `args`, `err` and `out` and nothing
 * else: no `ctx`, no `match`, no `client`, no NULL/UNDEF marks, no `null`
 * flag. Groups needing any of those simply had no test method, so **350 of
 * 1395 corpus entries never ran here**.
 *
 * The group list and per-group flags below mirror javascript/test/struct.test.js,
 * which is the reference usage of this corpus.
 */
class StructTest extends TestCase
{
    private const CORPUS = '../../build/test/test.json';

    /** @var array{spec:mixed,runset:callable,runsetflags:callable,subject:mixed,client:mixed} */
    private array $pack;

    /** The `struct` subtree, navigable as `$this->testSpec->minor->isnode`. */
    private stdClass|array $testSpec;

    protected function setUp(): void
    {
        $runner = Runner::makeRunner(self::CORPUS, SDK::test());
        $this->pack = $runner('struct');
        $this->testSpec = self::specview($this->pack['spec']);
    }

    /**
     * omni hands back the spec as nested arrays. The test methods below read
     * it as `$this->testSpec->minor->isnode`, so intermediate levels become
     * objects - but a GROUP node (the thing carrying `set`) is left as the
     * array omni's runner expects to be handed back.
     */
    private static function specview(mixed $node): mixed
    {
        if (!is_array($node)) {
            return $node;
        }
        // A GROUP node is one carrying a NON-EMPTY `set`. The intermediate
        // levels (`struct.minor`, `struct.validate`, ...) each carry an empty
        // `set` of their own, so testing for the key alone stops the walk one
        // level too high and the group nodes never become reachable.
        if (isset($node['set']) && is_array($node['set']) && [] !== $node['set']) {
            return $node;
        }
        // A LIST stays a list. Only maps become objects - turning `[a, b]` into
        // an object with keys 0 and 1 stops it being a list, and anything the
        // bespoke tests then hand to `merge`/`walk` is no longer what the
        // corpus authored.
        if (array_is_list($node)) {
            return array_map([self::class, 'specview'], $node);
        }
        $out = new stdClass();
        foreach ($node as $key => $val) {
            $out->{$key} = self::specview($val);
        }
        return $out;
    }

    /**
     * Run one corpus group through omni.
     *
     * `$flags` was a `bool $forceEquals` before the swap - omni always deep
     * equals, so a bool is accepted and ignored rather than editing every
     * call site to drop it.
     */
    private function testSet(mixed $tests, callable $apply, array|bool $flags = []): void
    {
        $this->assertIsArray($tests, 'corpus group missing or not a group node');
        $useflags = is_array($flags) ? $flags : [];

        try {
            ($this->pack['runsetflags'])($tests, $useflags, $apply);
        } catch (\Throwable $err) {
            // omni raises with the entry, the expectation and what it got.
            $this->fail($err->getMessage());
        }

        // Reaching here means every entry in the group matched.
        $this->assertTrue(true);
    }


    /**
     * Compare on a common representation: map values may be a stdClass or an
     * associative array depending on which side produced them. Used only by
     * the bespoke tests below - corpus groups go through omni, which does its
     * own deep equality.
     */
    private static function normalizeMaps(mixed $val, int $depth = 0): mixed
    {
        if ($depth > 64) {
            return $val;
        }
        if ($val instanceof \stdClass) {
            $out = [];
            foreach (get_object_vars($val) as $k => $v) {
                $out[$k] = self::normalizeMaps($v, $depth + 1);
            }
            return $out;
        }
        if ($val instanceof ListRef) {
            $val = $val->list;
        }
        if (is_array($val)) {
            $out = [];
            foreach ($val as $k => $v) {
                $out[$k] = self::normalizeMaps($v, $depth + 1);
            }
            return $out;
        }
        return $val;
    }

    /** Read a field from an entry's `in`, which may be a map or an object. */
    private static function vin(mixed $v, string $key, mixed $alt = null): mixed
    {
        if (is_array($v)) {
            return array_key_exists($key, $v) ? $v[$key] : $alt;
        }
        if (is_object($v)) {
            return property_exists($v, $key) ? $v->{$key} : $alt;
        }
        return $alt;
    }

    public function testExists(): void
    {
        $this->assertEquals('string', gettype([Struct::class, 'clone'][0]));
        $this->assertEquals('string', gettype([Struct::class, 'delprop'][0]));
        $this->assertEquals('string', gettype([Struct::class, 'escre'][0]));
        $this->assertEquals('string', gettype([Struct::class, 'escurl'][0]));
        $this->assertEquals('string', gettype([Struct::class, 'getelem'][0]));
        $this->assertEquals('string', gettype([Struct::class, 'getprop'][0]));

        $this->assertEquals('string', gettype([Struct::class, 'getpath'][0]));
        $this->assertEquals('string', gettype([Struct::class, 'haskey'][0]));
        $this->assertEquals('string', gettype([Struct::class, 'inject'][0]));
        $this->assertEquals('string', gettype([Struct::class, 'isempty'][0]));
        $this->assertEquals('string', gettype([Struct::class, 'isfunc'][0]));

        $this->assertEquals('string', gettype([Struct::class, 'iskey'][0]));
        $this->assertEquals('string', gettype([Struct::class, 'islist'][0]));
        $this->assertEquals('string', gettype([Struct::class, 'ismap'][0]));
        $this->assertEquals('string', gettype([Struct::class, 'isnode'][0]));
        $this->assertEquals('string', gettype([Struct::class, 'items'][0]));

        $this->assertEquals('string', gettype([Struct::class, 'joinurl'][0]));
        $this->assertEquals('string', gettype([Struct::class, 'jsonify'][0]));
        $this->assertEquals('string', gettype([Struct::class, 'keysof'][0]));
        $this->assertEquals('string', gettype([Struct::class, 'merge'][0]));
        $this->assertEquals('string', gettype([Struct::class, 'pad'][0]));
        $this->assertEquals('string', gettype([Struct::class, 'pathify'][0]));

        $this->assertEquals('string', gettype([Struct::class, 'select'][0]));
        $this->assertEquals('string', gettype([Struct::class, 'size'][0]));
        $this->assertEquals('string', gettype([Struct::class, 'slice'][0]));
        $this->assertEquals('string', gettype([Struct::class, 'setprop'][0]));

        $this->assertEquals('string', gettype([Struct::class, 'strkey'][0]));
        $this->assertEquals('string', gettype([Struct::class, 'stringify'][0]));
        $this->assertEquals('string', gettype([Struct::class, 'transform'][0]));
        $this->assertEquals('string', gettype([Struct::class, 'typify'][0]));
        $this->assertEquals('string', gettype([Struct::class, 'validate'][0]));

        $this->assertEquals('string', gettype([Struct::class, 'walk'][0]));
    }

    // ——— Minor/simple tests ———
    public function testIsnode()
    {
        $this->testSet($this->testSpec->minor->isnode, [Struct::class, 'isnode']);
    }
    public function testIsmap()
    {
        $this->testSet($this->testSpec->minor->ismap, [Struct::class, 'ismap']);
    }
    public function testIslist()
    {
        $this->testSet($this->testSpec->minor->islist, [Struct::class, 'islist']);
    }
    public function testIskey()
    {
        $this->testSet($this->testSpec->minor->iskey, [Struct::class, 'iskey'],
            ['null' => false]
        );
    }
    public function testIsempty()
    {
        $this->testSet($this->testSpec->minor->isempty, [Struct::class, 'isempty'],
            ['null' => false]
        );
    }
    public function testIsfunc()
    {
        $this->testSet($this->testSpec->minor->isfunc, [Struct::class, 'isfunc']);
    }
    public function testTypify()
    {
        $this->testSet($this->testSpec->minor->typify, [Struct::class, 'typify'],
            ['null' => false]
        );
    }

    // ——— getprop needs to extract stdClass props ———
    public function testGetprop(): void
    {
        $this->testSet(
            $this->testSpec->minor->getprop,
            function ($input) {
                $val = self::vin($input, 'val', Struct::undef());
                $key = self::vin($input, 'key', Struct::undef());
                $alt = self::vin($input, 'alt', Struct::undef());
                return Struct::getprop($val, $key, $alt);
            },
            ['null' => false]
        );
    }

    public function testGetelem(): void
    {
        $this->testSet(
            $this->testSpec->minor->getelem,
            function ($input) {
                $val = self::vin($input, 'val', Struct::undef());
                $key = self::vin($input, 'key', Struct::undef());
                $alt = self::vin($input, 'alt', Struct::undef());
                return $alt === Struct::undef() ?
                    Struct::getelem($val, $key) :
                    Struct::getelem($val, $key, $alt);
            },
            ['null' => false]
        );
    }

    // ——— Simple again ———
    public function testStrkey()
    {
        $this->testSet($this->testSpec->minor->strkey, [Struct::class, 'strkey'],
            ['null' => false]
        );
    }
    public function testHaskey()
    {
        $this->testSet(
            $this->testSpec->minor->haskey,
            function ($input) {
                $src = self::vin($input, 'src', Struct::undef());
                $key = self::vin($input, 'key', Struct::undef());
                return Struct::haskey($src, $key);
            },
            ['null' => false]
        );
    }

    public function testKeysof()
    {
        $this->testSet($this->testSpec->minor->keysof, [Struct::class, 'keysof']);
    }

    // ——— items returns array of [key, stdClass/array], so deep-equal ———
    public function testItems(): void
    {
        $this->testSet(
            $this->testSpec->minor->items,
            fn($in) => Struct::items($in),
            /*forceEquals=*/ true
        );
    }

    public function testEscre()
    {
        $this->testSet($this->testSpec->minor->escre, [Struct::class, 'escre']);
    }
    public function testEscurl()
    {
        $this->testSet($this->testSpec->minor->escurl, [Struct::class, 'escurl']);
    }

    public function testDelprop()
    {
        $this->testSet(
            $this->testSpec->minor->delprop,
            function ($input) {
                $parent = self::vin($input, 'parent', Struct::undef());
                $key = self::vin($input, 'key', null);
                return Struct::delprop($parent, $key);
            },
            true
        );
    }
    public function testJoinurl()
    {
        $this->testSet(
            $this->testSpec->minor->join,
            function ($input) {
                $val = self::vin($input, 'val', Struct::undef());
                $sep = self::vin($input, 'sep', null);
                $url = (self::vin($input, 'url', Struct::undef()) !== Struct::undef()) ? self::vin($input, 'url') : false;
                return Struct::join($val, $sep, $url);
            },
            ['null' => false]
        );
    }

    public function testJsonify()
    {
        $this->testSet(
            $this->testSpec->minor->jsonify,
            function ($input) {
                $val = self::vin($input, 'val', Struct::undef());
                $flags = self::vin($input, 'flags', null);
                return Struct::jsonify($val, $flags);
            },
            ['null' => false]
        );
    }

    public function testSize()
    {
        $this->testSet($this->testSpec->minor->size, [Struct::class, 'size'],
            ['null' => false]
        );
    }

    public function testSlice()
    {
        $this->testSet(
            $this->testSpec->minor->slice,
            function ($input) {
                $val = self::vin($input, 'val', Struct::undef());
                $start = self::vin($input, 'start', null);
                $end = self::vin($input, 'end', null);
                return Struct::slice($val, $start, $end);
            },
            ['null' => false]
        );
    }

    public function testPad()
    {
        $this->testSet(
            $this->testSpec->minor->pad,
            function ($input) {
                $val = self::vin($input, 'val', Struct::undef());
                $pad = self::vin($input, 'pad', null);
                $char = self::vin($input, 'char', null);
                return Struct::pad($val, $pad, $char);
            },
            ['null' => false]
        );
    }

    // ——— stringify returns strings but built from objects, so deep-equal ———
    public function testStringify(): void
    {
        $this->testSet(
            $this->testSpec->minor->stringify,
            fn($vin) => Struct::stringify(
                Runner::NULLMARK === self::vin($vin, 'val', Struct::undef())
                    ? 'null'
                    : self::vin($vin, 'val', Struct::undef()),
                self::vin($vin, 'max')
            )
        );
    }

    // ——— pathify returns strings but tests include null-marker tweaks ———
    public function testPathify(): void
    {
        $this->testSet(
            $this->testSpec->minor->pathify,
            function ($vin) {
                $raw = self::vin($vin, 'path', Struct::undef());
                $path = Runner::NULLMARK === $raw ? Struct::undef() : $raw;
                $pathstr = str_replace('__NULL__.', '', Struct::pathify($path, self::vin($vin, 'from')));
                if (Runner::NULLMARK === $raw) {
                    $pathstr = str_replace('>', ':null>', $pathstr);
                }
                return $pathstr;
            },
            ['null' => true]
        );
    }

    // ——— sentinels: Group A null-unification and stringify(null) ———
    // regex (parity floor: Go stdlib regexp — see design/REGEX_API.md)
    public function testRegexTest(): void
    {
        $this->testSet(
            $this->testSpec->regex->test,
            function ($input) {
                return Struct::re_test(self::vin($input, 'pattern'), self::vin($input, 'input'));
            }
        );
    }

    public function testRegexFind(): void
    {
        $this->testSet(
            $this->testSpec->regex->find,
            function ($input) {
                $m = Struct::re_find(self::vin($input, 'pattern'), self::vin($input, 'input'));
                return $m === null ? null : $m;
            }
        );
    }

    public function testRegexFindAll(): void
    {
        $this->testSet(
            $this->testSpec->regex->find_all,
            function ($input) {
                return Struct::re_find_all(self::vin($input, 'pattern'), self::vin($input, 'input'));
            }
        );
    }

    public function testRegexReplace(): void
    {
        $this->testSet(
            $this->testSpec->regex->replace,
            function ($input) {
                return Struct::re_replace(self::vin($input, 'pattern'), self::vin($input, 'input'), self::vin($input, 'replacement'));
            }
        );
    }

    public function testRegexEscape(): void
    {
        $this->testSet(
            $this->testSpec->regex->escape,
            function ($input) {
                return Struct::re_escape(self::vin($input, 'val'));
            }
        );
    }

    // Mirrors perl/t/struct.t sentinels dispatch. These groups exercise the
    // canonical absent-vs-null rule: a stored JSON null counts as "no value"
    // for getprop/getelem/haskey/isempty/isnode, while stringify renders it.
    public function testSentinelsGetpropUnify(): void
    {
        $this->testSet(
            $this->testSpec->sentinels->getprop_unify,
            function ($input) {
                $val = self::vin($input, 'val', Struct::undef());
                $key = self::vin($input, 'key', Struct::undef());
                $alt = self::vin($input, 'alt', Struct::undef());
                return Struct::getprop($val, $key, $alt);
            },
            ['null' => false]
        );
    }

    public function testSentinelsGetelemAbsent(): void
    {
        $this->testSet(
            $this->testSpec->sentinels->getelem_absent,
            function ($input) {
                $val = self::vin($input, 'val', Struct::undef());
                $key = self::vin($input, 'key', Struct::undef());
                $alt = self::vin($input, 'alt', Struct::undef());
                return $alt === Struct::undef()
                    ? Struct::getelem($val, $key)
                    : Struct::getelem($val, $key, $alt);
            },
            ['null' => false]
        );
    }

    public function testSentinelsHaskeyUnify(): void
    {
        $this->testSet(
            $this->testSpec->sentinels->haskey_unify,
            function ($input) {
                $val = self::vin($input, 'val', Struct::undef());
                $key = self::vin($input, 'key', Struct::undef());
                return Struct::haskey($val, $key);
            },
            ['null' => false]
        );
    }

    public function testSentinelsIsemptyUnify(): void
    {
        $this->testSet(
            $this->testSpec->sentinels->isempty_unify,
            fn($in) => Struct::isempty($in),
            ['null' => false]
        );
    }

    public function testSentinelsIsnodeUnify(): void
    {
        $this->testSet(
            $this->testSpec->sentinels->isnode_unify,
            fn($in) => Struct::isnode($in),
            ['null' => false]
        );
    }

    public function testSentinelsStringifyNull(): void
    {
        $this->testSet(
            $this->testSpec->sentinels->stringify_null,
            fn($in) => Struct::stringify($in),
            ['null' => false]
        );
    }

    public function testGetpropEdge(): void
    {
        // Test string array access
        $strarr = ['a', 'b', 'c', 'd', 'e'];
        $this->assertEquals('c', Struct::getprop($strarr, 2));
        $this->assertEquals('c', Struct::getprop($strarr, '2'));

        // Test integer array access
        $intarr = [2, 3, 5, 7, 11];
        $this->assertEquals(5, Struct::getprop($intarr, 2));
        $this->assertEquals(5, Struct::getprop($intarr, '2'));
    }

    public function testDelpropEdge(): void
    {
        // Test string array deletion
        $strarr0 = ['a', 'b', 'c', 'd', 'e'];
        $strarr1 = ['a', 'b', 'c', 'd', 'e'];
        $this->assertEquals(['a', 'b', 'd', 'e'], Struct::delprop($strarr0, 2));
        $this->assertEquals(['a', 'b', 'd', 'e'], Struct::delprop($strarr1, '2'));

        // Test integer array deletion
        $intarr0 = [2, 3, 5, 7, 11];
        $intarr1 = [2, 3, 5, 7, 11];
        $this->assertEquals([2, 3, 7, 11], Struct::delprop($intarr0, 2));
        $this->assertEquals([2, 3, 7, 11], Struct::delprop($intarr1, '2'));
    }

    public function testGetpathHandler(): void
    {
        $this->testSet(
            $this->testSpec->getpath->handler,
            function ($input) {
                $store = [
                    '$TOP' => self::vin($input, 'store'),
                    '$FOO' => function () {
                        return 'foo';
                    }
                ];
                $state = new \stdClass();
                $state->handler = function ($inj, $val, $cur, $ref) {
                    return $val();
                };
                return Struct::getpath(
                    $store,
                    self::vin($input, 'path'),
                    $state
                );
            }
        );
    }

    public function testClone(): void
    {
        $this->testSet(
            $this->testSpec->minor->clone,
            fn($in) => Struct::clone($in),
            ['null' => false]
        );
    }

    public function testSetprop(): void
    {
        $this->testSet(
            $this->testSpec->minor->setprop,
            function ($input) {
                $parent = self::vin($input, 'parent', Struct::undef());
                $key = self::vin($input, 'key', null);
                $val = self::vin($input, 'val', Struct::undef());
                return Struct::setprop($parent, $key, $val);
            },
            true
        );
    }

    public function testSetpropEdge(): void
    {
        // Test string array modification
        $strarr0 = ['a', 'b', 'c', 'd', 'e'];
        $strarr1 = ['a', 'b', 'c', 'd', 'e'];
        $this->assertEquals(['a', 'b', 'C', 'd', 'e'], Struct::setprop($strarr0, 2, 'C'));
        $this->assertEquals(['a', 'b', 'CC', 'd', 'e'], Struct::setprop($strarr1, '2', 'CC'));

        // Test integer array modification
        $intarr0 = [2, 3, 5, 7, 11];
        $intarr1 = [2, 3, 5, 7, 11];
        $this->assertEquals([2, 3, 55, 7, 11], Struct::setprop($intarr0, 2, 55));
        $this->assertEquals([2, 3, 555, 7, 11], Struct::setprop($intarr1, '2', 555));
    }

    public function testWalkLog(): void
    {
        $spec = $this->testSpec->walk->log;
        $test = Struct::clone($spec);

        $log = [];
        $walklog = function ($key, $val, $parent, $path) use (&$log) {
            $kstr = ($key === null) ? '' : Struct::stringify($key);
            $pstr = ($parent === null) ? '' : Struct::stringify($parent);
            $log[] = 'k=' . $kstr
                . ', v=' . Struct::stringify($val)
                . ', p=' . $pstr
                . ', t=' . Struct::pathify($path);
            return $val;
        };

        Struct::walk($test->in, null, $walklog);
        $this->assertEquals(
            $test->out->after,
            $log,
            "walk-log after did not match"
        );

        $log = [];
        Struct::walk($test->in, $walklog);
        $this->assertEquals(
            $test->out->before,
            $log,
            "walk-log before did not match"
        );

        $log = [];
        Struct::walk($test->in, $walklog, $walklog);
        $this->assertEquals(
            $test->out->both,
            $log,
            "walk-log both did not match"
        );
    }

    /**
     * @covers \Voxgig\Struct\Struct::walk
     */
    public function testWalkBasic(): void
    {
        $this->testSet(
            $this->testSpec->walk->basic,
            function ($input) {
                return Struct::walk(
                    $input,
                    function ($_k, $v, $_p, $path) {
                        return is_string($v)
                            ? $v . '~' . implode('.', $path)
                            : $v;
                    }
                );
            },
            true
        );
    }


    public function testMergeBasic(): void
    {
        $spec = $this->testSpec->merge->basic;
        $in = Struct::clone($spec->in);
        $out = Struct::merge($in);

        $this->assertEquals(
            $spec->out,
            $out,
            "merge-basic did not produce the expected result"
        );
    }

    public function testMergeCases(): void
    {
        $this->testSet(
            $this->testSpec->merge->cases,
            // take the input array/val as-is, don't try to read ->in again
            fn($in) => Struct::merge($in),
            /* force deep‐equal */ true
        );
    }

    public function testMergeArray(): void
    {
        $this->testSet(
            $this->testSpec->merge->array,
            fn($in) => Struct::merge($in),
            /* force deep‐equal */ true
        );
    }

    public function testMergeIntegrity(): void
    {
        $this->testSet(
            $this->testSpec->merge->integrity,
            fn($in) => Struct::merge($in),
            /* force deep‐equal */ true
        );
    }

    public function testMergeSpecial(): void
    {
        // Function‐value merging
        $f0 = function () {
            return null;
        };

        // single‐element list → that element
        $this->assertSame($f0, Struct::merge([$f0]));

        // null then f0 → f0 wins
        $this->assertSame($f0, Struct::merge([null, $f0]));

        // map with function property
        $obj1 = new stdClass();
        $obj1->a = $f0;
        $this->assertEquals(
            $obj1,
            Struct::merge([$obj1])
        );

        // nested map
        $obj2 = new stdClass();
        $obj2->a = new stdClass();
        $obj2->a->b = $f0;
        $this->assertEquals(
            $obj2,
            Struct::merge([$obj2])
        );
    }

    public function testGetpathBasic(): void
    {
        $this->testSet(
            $this->testSpec->getpath->basic,
            function ($input) {
                $path = self::vin($input, 'path', Struct::undef());
                $store = self::vin($input, 'store', Struct::undef());
                $result = Struct::getpath($store, $path);
                return $result;
            },
            true
        );
    }

    public function testGetpathRelative(): void
    {
        $this->testSet(
            $this->testSpec->getpath->relative,
            function ($input) {
                $path = self::vin($input, 'path', Struct::undef());
                $store = self::vin($input, 'store', Struct::undef());
                $state = new \stdClass();
                if ((self::vin($input, 'dparent', Struct::undef()) !== Struct::undef())) {
                    $state->dparent = self::vin($input, 'dparent');
                }
                if ((self::vin($input, 'dpath', Struct::undef()) !== Struct::undef())) {
                    $state->dpath = explode('.', self::vin($input, 'dpath'));
                }
                $result = Struct::getpath($store, $path, $state);
                return $result;
            },
            true
        );
    }

    public function testGetpathSpecial(): void
    {
        $this->testSet(
            $this->testSpec->getpath->special,
            function ($input) {
                $path = self::vin($input, 'path', Struct::undef());
                $store = self::vin($input, 'store', Struct::undef());
                $state = self::vin($input, 'inj', null);
                $result = Struct::getpath($store, $path, $state);
                return $result;
            },
            true
        );
    }

    public function testInjectBasic(): void
    {
        // single‐case spec: injectSpec.basic
        $spec = $this->testSpec->inject->basic;
        // clone the input so we don't modify the fixture
        $val = Struct::clone($spec->in->val);
        $store = $spec->in->store;

        $result = Struct::inject($val, $store);

        $this->assertEquals(
            $spec->out,
            $result,
            "inject-basic did not produce the expected result"
        );
    }

    public function testInjectString(): void
    {
        $this->testSet(
            $this->testSpec->inject->string,
            fn($vin) => Struct::inject(
                self::vin($vin, 'val'),
                self::vin($vin, 'store'),
                (object) ['modify' => [Runner::class, 'nullModifier']]
            )
        );
    }

    /**
     * @suppressWarnings(PHPMD.UnusedLocalVariable)
     * @suppressWarnings(PHPMD.UnusedFormalParameter)
     */
    public function testInjectDeep(): void
    {
        $this->testSet(
            $this->testSpec->inject->deep,
            function ($in) {
                // deep tests never need a modifier or current
                $val = self::vin($in, 'val', null);
                $store = self::vin($in, 'store', null);
                return Struct::inject($val, $store);
            },
            /* force deep‐equal */ true
        );
    }

    // ——— transform-basic ———
    public function testTransformBasic(): void
    {
        // single‐case test (no "set" array)
        $test = $this->testSpec->transform->basic;
        $in = $test->in;
        $out = Struct::transform(self::vin($in, 'data'), self::vin($in, 'spec'));
        $this->assertEquals(
            self::normalizeMaps($test->out),
            self::normalizeMaps($out),
            'transform-basic failed'
        );
    }

    // ——— transform-paths ———
    public function testTransformPaths(): void
    {
        $this->testSet(
            $this->testSpec->transform->paths,
            fn($vin) => Struct::transform(
                self::vin($vin, 'data', Struct::undef()),
                self::vin($vin, 'spec', null)
            )
        );
    }

    // ——— transform-cmds ———
    public function testTransformCmds(): void
    {
        $this->testSet(
            $this->testSpec->transform->cmds,
            fn($vin) => Struct::transform(
                self::vin($vin, 'data', Struct::undef()),
                self::vin($vin, 'spec', null)
            )
        );
    }

    // ——— transform-each ———
    public function testTransformEach(): void
    {
        $this->testSet(
            $this->testSpec->transform->each,
            fn($vin) => Struct::transform(self::vin($vin, 'data'), self::vin($vin, 'spec'))
        );
    }

    public function testTransformPack(): void
    {
        $this->testSet(
            $this->testSpec->transform->pack,
            fn($vin) => Struct::transform(self::vin($vin, 'data'), self::vin($vin, 'spec'))
        );
    }

    public function testTransformModify(): void
    {
        $this->testSet(
            $this->testSpec->transform->modify,
            function ($vin) {
                $opts = new \stdClass();
                $opts->extra = self::vin($vin, 'store', Struct::undef());
                $opts->modify = function ($val, $key, $parent) {
                    if ($key !== null && $parent !== null && is_string($val)) {
                        Struct::setprop($parent, $key, '@' . $val);
                    }
                };
                return Struct::transform(
                    self::vin($vin, 'data'),
                    self::vin($vin, 'spec'),
                    $opts
                );
            }
        );
    }

    public function testTransformRef(): void
    {
        $this->testSet(
            $this->testSpec->transform->ref,
            function ($input) {
                return Struct::transform(
                    self::vin($input, 'data', Struct::undef()),
                    self::vin($input, 'spec', Struct::undef()),
                    self::vin($input, 'store', Struct::undef())
                );
            }
        );
    }

    // ——— transform-extra ———
    public function testTransformExtra(): void
    {
        $extraTransforms = (object) [
            '$UPPER' => function ($state) {
                $last = end($state->path);
                return strtoupper((string) $last);
            }
        ];

        $res = Struct::transform(
            (object) ['a' => 1],
            (object) [
                'x' => '`a`',
                'b' => '`$COPY`',
                'c' => '`$UPPER`',
            ],
            (object) array_merge(
                ['b' => 2],
                (array) $extraTransforms
            )
        );

        $this->assertEquals(
            self::normalizeMaps((object) [
                'x' => 1,
                'b' => 2,
                'c' => 'C',
            ]),
            self::normalizeMaps($res)
        );
    }

    // ——— validate tests ———
    public function testValidateBasic(): void
    {
        $this->testSet(
            $this->testSpec->validate->basic,
            fn($vin) => Struct::validate(self::vin($vin, 'data'), self::vin($vin, 'spec')),
            ['null' => false]
        );
    }

    public function testValidateChild(): void
    {
        $this->testSet(
            $this->testSpec->validate->child,
            fn($vin) => Struct::validate(self::vin($vin, 'data'), self::vin($vin, 'spec'))
        );
    }

    public function testValidateOne(): void
    {
        $this->testSet(
            $this->testSpec->validate->one,
            fn($vin) => Struct::validate(self::vin($vin, 'data'), self::vin($vin, 'spec'))
        );
    }

    public function testValidateExact(): void
    {
        $this->testSet(
            $this->testSpec->validate->exact,
            fn($vin) => Struct::validate(self::vin($vin, 'data'), self::vin($vin, 'spec'))
        );
    }

    public function testValidateInvalid(): void
    {
        $count = 0;
        $this->testSet(
            $this->testSpec->validate->invalid,
            function ($input) use (&$count) {
                $count++;
                return Struct::validate(
                    self::vin($input, 'data', Struct::undef()),
                    self::vin($input, 'spec', Struct::undef())
                );
            },
            ['null' => false]
        );
        $this->assertGreaterThan(0, $count, 'validate-invalid should have run at least one test entry');
    }

    public function testValidateSpecial(): void
    {
        $this->testSet(
            $this->testSpec->validate->special,
            fn($vin) => Struct::validate(self::vin($vin, 'data'), self::vin($vin, 'spec'), self::vin($vin, 'inj'))
        );
    }

    public function testValidateCustom(): void
    {
        // Was `$this->assertTrue(true)` with a TODO comment - a test that
        // passed while asserting nothing. Marked incomplete instead, so it
        // shows up as work rather than as coverage.
        $this->markTestIncomplete('custom validator integration has no corpus group; needs a bespoke test');
    }

    // ——— transform-funcval ———
    public function testTransformFuncval(): void
    {
        $f0 = fn() => 99;

        // literal value stays literal
        $this->assertEquals(
            self::normalizeMaps((object) ['x' => 1]),
            self::normalizeMaps(Struct::transform((object) [], (object) ['x' => 1]))
        );

        // function as a spec value is preserved
        $out1 = Struct::transform((object) [], (object) ['x' => $f0]);
        $this->assertSame($f0, $out1['x']);

        // backtick reference to a number field
        $this->assertEquals(
            self::normalizeMaps((object) ['x' => 1]),
            self::normalizeMaps(Struct::transform((object) ['a' => 1], (object) ['x' => '`a`']))
        );

        // backtick reference to a function field
        $res2 = Struct::transform(
            (object) ['f0' => $f0],
            (object) ['x' => '`f0`']
        );
        $this->assertSame($f0, $res2['x']);
    }

    public function testSelectBasic(): void
    {
        $this->testSet(
            $this->testSpec->select->basic,
            fn($vin) => Struct::select(self::vin($vin, 'obj'), self::vin($vin, 'query'))
        );
    }

    public function testSelectOperators(): void
    {
        $this->testSet(
            $this->testSpec->select->operators,
            fn($vin) => Struct::select(self::vin($vin, 'obj'), self::vin($vin, 'query'))
        );
    }

    public function testSelectEdge(): void
    {
        $this->testSet(
            $this->testSpec->select->edge,
            fn($vin) => Struct::select(self::vin($vin, 'obj'), self::vin($vin, 'query'))
        );
    }

    // ——— Missing minor tests ———

    public function testTypename(): void
    {
        $this->testSet($this->testSpec->minor->typename, [Struct::class, 'typename']);
    }

    public function testFlatten(): void
    {
        $this->testSet(
            $this->testSpec->minor->flatten,
            function ($input) {
                $val = self::vin($input, 'val', Struct::undef());
                $depth = self::vin($input, 'depth', null);
                return Struct::flatten($val, $depth);
            },
            true
        );
    }

    public function testFilter(): void
    {
        $checkmap = [
            'gt3' => function ($n) {
                return $n[1] > 3;
            },
            'lt3' => function ($n) {
                return $n[1] < 3;
            },
        ];
        $this->testSet(
            $this->testSpec->minor->filter,
            function ($input) use ($checkmap) {
                $val = self::vin($input, 'val', Struct::undef());
                $check = $checkmap[self::vin($input, 'check')];
                return Struct::filter($val, $check);
            },
            true
        );
    }

    public function testSetpath(): void
    {
        $this->testSet(
            $this->testSpec->minor->setpath,
            function ($input) {
                $store = self::vin($input, 'store', Struct::undef());
                $path = (self::vin($input, 'path', Struct::undef()) !== Struct::undef()) ? self::vin($input, 'path') : '';
                $val = self::vin($input, 'val', Struct::undef());
                return Struct::setpath($store, $path, $val);
            },
            ['null' => false]
        );
    }

    // ——— Edge tests ———

    public function testMinorEdgeClone(): void
    {
        $f0 = function () {
            return null;
        };
        $result = Struct::clone((object) ['a' => $f0]);
        $this->assertSame($f0, $result->a);

        $x = (object) ['y' => 1];
        $xc = Struct::clone($x);
        $this->assertEquals($x, $xc);
        $this->assertNotSame($x, $xc);
    }

    public function testMinorEdgeCloneClosures(): void
    {
        // Closure preserved by reference in an object.
        $fn = function ($x) {
            return $x + 1;
        };
        $obj = (object) ['a' => 1, 'f' => $fn];
        $cloned = Struct::clone($obj);
        $this->assertSame($fn, $cloned->f);
        $this->assertEquals(1, $cloned->a);
        $this->assertNotSame($obj, $cloned);

        // Closure preserved in a nested object.
        $fn2 = fn($x) => $x * 2;
        $nested = (object) ['x' => (object) ['y' => $fn2, 'z' => 3]];
        $clonedNested = Struct::clone($nested);
        $this->assertSame($fn2, $clonedNested->x->y);
        $this->assertEquals(3, $clonedNested->x->z);
        $this->assertNotSame($nested->x, $clonedNested->x);

        // Closure preserved in an array.
        $fn3 = function () {
            return 'hello';
        };
        $arr = [$fn3, 1, 'two'];
        $clonedArr = Struct::clone($arr);
        $this->assertSame($fn3, $clonedArr[0]);
        $this->assertEquals(1, $clonedArr[1]);
        $this->assertEquals('two', $clonedArr[2]);

        // Multiple closures preserved independently.
        $fnA = function () {
            return 'A';
        };
        $fnB = function () {
            return 'B';
        };
        $multi = (object) ['a' => $fnA, 'b' => $fnB, 'c' => 99];
        $clonedMulti = Struct::clone($multi);
        $this->assertSame($fnA, $clonedMulti->a);
        $this->assertSame($fnB, $clonedMulti->b);
        $this->assertNotSame($fnA, $fnB);
        $this->assertEquals(99, $clonedMulti->c);

        // String that happens to be a callable name is NOT treated as a
        // function — it must remain an ordinary string after clone.
        $strCallable = (object) ['a' => 'strlen', 'b' => 'array_map'];
        $clonedStr = Struct::clone($strCallable);
        $this->assertIsString($clonedStr->a);
        $this->assertEquals('strlen', $clonedStr->a);
        $this->assertIsString($clonedStr->b);
        $this->assertEquals('array_map', $clonedStr->b);

        // String that looks like a function placeholder is not corrupted.
        $placeholder = (object) ['v' => '`$FUNCTION:0`'];
        $clonedPlaceholder = Struct::clone($placeholder);
        $this->assertEquals('`$FUNCTION:0`', $clonedPlaceholder->v);

        // Invokable object preserved by reference.
        $invokable = new class {
            public function __invoke(): string
            {
                return 'invoked';
            }
        };
        $objWithInvokable = (object) ['f' => $invokable];
        $clonedInvokable = Struct::clone($objWithInvokable);
        $this->assertSame($invokable, $clonedInvokable->f);

        // Bare closure as top-level value.
        $topFn = function () {
            return 42;
        };
        $clonedTopFn = Struct::clone($topFn);
        $this->assertSame($topFn, $clonedTopFn);

        // Null and scalars still clone correctly alongside closures.
        $mixed = (object) ['f' => $fn, 'n' => null, 's' => 'text', 'i' => 7];
        $clonedMixed = Struct::clone($mixed);
        $this->assertSame($fn, $clonedMixed->f);
        $this->assertNull($clonedMixed->n);
        $this->assertEquals('text', $clonedMixed->s);
        $this->assertEquals(7, $clonedMixed->i);
    }

    public function testMinorEdgeGetelem(): void
    {
        $this->assertEquals(2, Struct::getelem([], 1, function () {
            return 2;
        }));
    }

    public function testMinorEdgeItems(): void
    {
        $a0 = [11, 22, 33];
        $this->assertEquals([['0', 11], ['1', 22], ['2', 33]], Struct::items($a0));
    }

    public function testMinorEdgeJsonify(): void
    {
        $this->assertEquals('null', Struct::jsonify(function () {
            return 1;
        }));
    }

    public function testMinorEdgeKeysof(): void
    {
        $a0 = [11, 22, 33];
        $this->assertEquals(['0', '1', '2'], Struct::keysof($a0));
    }

    public function testMinorEdgeSetpath(): void
    {
        $x = (object) ['y' => (object) ['z' => 1, 'q' => 2]];
        $result = Struct::setpath($x, 'y.q', Struct::DELETE);
        $this->assertEquals((object) ['z' => 1], $result);
        $this->assertEquals((object) ['y' => (object) ['z' => 1]], $x);
    }

    public function testMinorEdgeStringify(): void
    {
        $this->assertEquals('__STRINGIFY_FAILED__', Struct::stringify(fopen('php://memory', 'r')));
    }

    public function testMinorEdgeTypify(): void
    {
        $this->assertEquals(Struct::T_noval, Struct::typify(Struct::undef()));
        $this->assertEquals(Struct::T_scalar | Struct::T_null, Struct::typify(null));
        $this->assertEquals(Struct::T_scalar | Struct::T_function, Struct::typify(function () {
            return null;
        }));
    }

    // ——— Merge depth ———

    public function testMergeDepth(): void
    {
        $this->testSet(
            $this->testSpec->merge->depth,
            function ($input) {
                $val = self::vin($input, 'val', Struct::undef());
                $depth = self::vin($input, 'depth', null);
                return Struct::merge($val, $depth);
            },
            true
        );
    }

    // ——— Walk copy and depth ———

    public function testWalkCopy(): void
    {
        $cur = [];
        $walkcopy_before = function ($key, $val, $_parent, $path) use (&$cur) {
            if ($key === null) {
                $cur = [];
                $cur[0] = Struct::ismap($val) ? new \stdClass() : (Struct::islist($val) ? [] : $val);
                return $val;
            }

            $v = $val;
            $i = Struct::size($path);

            if (Struct::isnode($v)) {
                $v = Struct::ismap($v) ? new \stdClass() : [];
                $cur[$i] = $v;
            }

            Struct::setprop($cur[$i - 1], $key, $v);

            return $val;
        };

        $walkcopy_after = function ($key, $val, $_parent, $path) use (&$cur) {
            if ($key === null) {
                return $val;
            }
            $i = Struct::size($path);
            if (Struct::isnode($val)) {
                Struct::setprop($cur[$i - 1], $key, $cur[$i]);
            }
            return $val;
        };

        $this->testSet(
            $this->testSpec->walk->copy,
            function ($vin) use (&$cur, $walkcopy_before, $walkcopy_after) {
                Struct::walk($vin, $walkcopy_before, $walkcopy_after);
                return $cur[0];
            },
            true
        );
    }

    public function testWalkDepth(): void
    {
        $this->testSet(
            $this->testSpec->walk->depth,
            function ($vin) {
                // An entry's `in` is a map, which omni delivers as an array.
                if (Struct::undef() === self::vin($vin, 'src', Struct::undef())) {
                    return null;
                }
                $top = null;
                $cur = null;
                $copy = function ($key, $val, $_parent, $_path) use (&$top, &$cur) {
                    if ($key === null || Struct::isnode($val)) {
                        $child = Struct::islist($val) ? [] : new \stdClass();
                        if ($key === null) {
                            $top = $child;
                            $cur = $child;
                        } else {
                            Struct::setprop($cur, $key, $child);
                            $cur = $child;
                        }
                    } else {
                        Struct::setprop($cur, $key, $val);
                    }
                    return $val;
                };
                $maxdepth = self::vin($vin, 'maxdepth', null);
                Struct::walk(self::vin($vin, 'src'), $copy, null, $maxdepth);
                return $top;
            },
            ['null' => false]
        );
    }

    // ——— Validate edge ———

    public function testValidateEdge(): void
    {
        // Was `$this->assertTrue(true)` with a TODO comment - a test that
        // passed while asserting nothing. Marked incomplete instead, so it
        // shows up as work rather than as coverage.
        $this->markTestIncomplete('$INSTANCE validator is unimplemented in this port');
    }

    // ——— Transform apply and format ———

    public function testTransformApply(): void
    {
        $this->testSet(
            $this->testSpec->transform->apply,
            fn($vin) => Struct::transform(self::vin($vin, 'data'), self::vin($vin, 'spec'))
        );
    }

    public function testTransformEdgeApply(): void
    {
        // Was `$this->assertTrue(true)` with a TODO comment - a test that
        // passed while asserting nothing. Marked incomplete instead, so it
        // shows up as work rather than as coverage.
        $this->markTestIncomplete('no corpus group; transform/apply is covered by testTransformApply');
    }

    public function testTransformFormat(): void
    {
        $this->testSet(
            $this->testSpec->transform->format,
            fn($vin) => Struct::transform(self::vin($vin, 'data'), self::vin($vin, 'spec')),
            ['null' => false]
        );
    }

    // ——— Validate: an empty [] is a LIST, and a map spec rejects it ———

    public function testValidateEmptyArrayAgainstMapSpec(): void
    {
        // PHP's [] is ambiguous to the eye but not to this port: `ismap([])`
        // is false and `islist([])` is true. Validation used to make an
        // exception for it - an empty [] passed a map spec - which contradicted
        // both `ismap` and the shared corpus (`validate/basic`, the entry
        // expecting "Expected field c2 to be map, but found list: []").
        //
        // The corpus is the contract, so the exception is gone. A caller who
        // means an empty MAP writes `new stdClass()`, which is what `ismap` has
        // always required. Verified against canonical JavaScript: every case
        // below produces the same errors, and case 5 the same value, there.

        $spec = (object) ['allow' => (object) ['method' => 'GET', 'op' => 'create']];
        $validate = function ($data, $spec) {
            $errs = [];
            $injdef = (object) ['errs' => &$errs];
            $result = Struct::validate($data, $spec, $injdef);
            return [$errs, $result];
        };

        // Case 1: an empty [] against a map spec is a type mismatch.
        [$errs, $result] = $validate((object) ['allow' => []], $spec);
        $this->assertSame(
            ['Expected field allow to be map, but found list: [].'],
            $errs,
            'an empty [] is a list, and a map spec must reject it'
        );
        // validate() delegates to transform(), which returns associative
        // arrays at the public boundary.
        $this->assertIsArray($result);

        // Case 2: the same nested, reported per field.
        [$errs2] = $validate(
            (object) ['config' => (object) ['db' => [], 'cache' => []]],
            (object) ['config' => (object) [
                'db' => (object) ['host' => 'localhost'],
                'cache' => (object) ['ttl' => 300],
            ]]
        );
        $this->assertSame(
            [
                'Expected field config.cache to be map, but found list: [].',
                'Expected field config.db to be map, but found list: [].',
            ],
            $errs2,
            'nested empty [] is reported per field'
        );

        // Case 3: stdClass is the way to spell an empty map, and it passes.
        [$errs3] = $validate((object) ['allow' => (object) []], $spec);
        $this->assertEmpty($errs3, 'an empty stdClass IS a map and must validate');

        // Case 4: a non-empty list is rejected the same way, and prints its
        // contents - the only difference from case 1 is the value in the text.
        [$errs4] = $validate((object) ['allow' => [1, 2, 3]], $spec);
        $this->assertSame(
            ['Expected field allow to be map, but found list: [1,2,3].'],
            $errs4,
            'a non-empty list against a map spec is the same mismatch'
        );

        // Case 5: merge-then-validate. `merge` itself yields a LIST here - the
        // later empty [] replaces the earlier map, being a different type - so
        // validation reports the mismatch. Canonical JavaScript produces this
        // merged value, this error, and this result, identically.
        $merged = Struct::merge([
            (object) ['allow' => (object) ['method' => 'GET', 'op' => 'create'], 'timeout' => 30000],
            (object) ['allow' => [], 'timeout' => 5000],
            (object) [],
        ]);
        $this->assertTrue(Struct::islist(Struct::getprop($merged, 'allow')), 'merge yields a list');

        $optspec = (object) [
            'allow' => (object) [
                'method' => 'GET,PUT,POST',
                'op' => 'create,update,load',
            ],
            'timeout' => 30000,
        ];
        [$errs5, $result5] = $validate($merged, $optspec);
        $this->assertSame(
            ['Expected field allow to be map, but found list: [].'],
            $errs5,
            'merge-then-validate reports the mismatch merge created'
        );
        // The spec defaults are still filled in, mismatch notwithstanding.
        $this->assertSame('create,update,load', $result5['allow']['op'] ?? null);
        $this->assertSame(5000, $result5['timeout'] ?? null);

        // Case 6: a ListRef is a list however empty it is.
        [$errs6] = $validate((object) ['allow' => new ListRef([])], $spec);
        $this->assertSame(
            ['Expected field allow to be map, but found list: [].'],
            $errs6,
            'an empty ListRef is a list too'
        );
    }

    public function testSelectAlts(): void
    {
        $this->testSet(
            $this->testSpec->select->alts,
            fn($vin) => Struct::select(self::vin($vin, 'obj'), self::vin($vin, 'query'))
        );
    }

    public function testSelectNullkey(): void
    {
        $this->testSet(
            $this->testSpec->select->nullkey,
            fn($vin) => Struct::select(self::vin($vin, 'obj'), self::vin($vin, 'query'))
        );
    }

    // `condense`, `expand` and `iscondensed` have no methods on purpose: they
    // are canonical-TypeScript-only by design (tools/check_parity.py lists
    // them under PENDING_PORT), so their 37 corpus entries have no php
    // subject to run against.
}
