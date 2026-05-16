<?php

// Discovery test: pathological regex inputs run against the port's re_* API.
// Goal is to surface failures across ports, not to assert behaviour.
// Panel is the same in every port (see REGEX.md).

require_once __DIR__ . '/../src/Struct.php';

use PHPUnit\Framework\TestCase;
use Voxgig\Struct\Struct;

class RegexPathologicalTest extends TestCase
{
    private static function record(string $label, callable $fn): void
    {
        $t0 = hrtime(true);
        try {
            $r = $fn();
            $outcome = 'OK | ' . json_encode($r, JSON_UNESCAPED_UNICODE);
        } catch (\Throwable $e) {
            $outcome = 'ERR | ' . get_class($e) . ': ' . $e->getMessage();
        }
        $ms = (hrtime(true) - $t0) / 1e6;
        printf("[regex-discovery] %s | %.2fms | %s\n", $label, $ms, $outcome);
    }

    public function testPanel(): void
    {
        $a22    = str_repeat('a', 22);
        $nest40 = str_repeat('(', 40) . 'a' . str_repeat(')', 40);

        self::record('P1_redos_nested_plus',      fn() => Struct::re_test('^(a+)+$', $a22 . '!'));
        self::record('P2_redos_alt_overlap',      fn() => Struct::re_test('^(a|aa)+$', $a22 . '!'));
        self::record('P3_empty_repeat_replace',   fn() => Struct::re_replace('a*', 'abc', 'X'));
        self::record('P4_unicode_replace_dot',    fn() => Struct::re_replace('\\.', 'café.au.lait', '/'));
        self::record('P5_unicode_find_codepoint', fn() => Struct::re_find('é', 'café au lait'));
        self::record('P6_deep_nesting_compile',   fn() => Struct::re_test($nest40, 'a'));
        self::record('P7_big_bounded_quantifier', fn() => Struct::re_test('^a{0,10000}b$', str_repeat('a', 10) . 'b'));
        self::record('P8_invalid_pattern',        fn() => Struct::re_compile('[abc'));
        self::record('P9_backref_re2_forbidden',  fn() => Struct::re_test('^(a+)\\1$', 'aaaa'));
        self::record('P10_find_all_zero_width',   fn() => Struct::re_find_all('a*', 'bbb'));

        $this->assertTrue(true);
    }
}
