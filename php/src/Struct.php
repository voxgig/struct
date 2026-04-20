<?php
declare(strict_types=1);

namespace Voxgig\Struct;

/**
 * Reference-stable wrapper for PHP arrays.
 * PHP arrays are value types (copy-on-write), so storing them in injection
 * state loses reference identity. ListRef wraps the array in an object
 * (reference type) so mutations via setval/delprop propagate through the
 * injection pipeline. Mirrors Go's ListRef[T] strategy.
 */
class ListRef implements \ArrayAccess, \Countable, \IteratorAggregate
{
    public array $list;

    public function __construct(array $list = [])
    {
        $this->list = $list;
    }

    public function offsetExists(mixed $offset): bool
    {
        return isset($this->list[$offset]);
    }

    public function offsetGet(mixed $offset): mixed
    {
        return $this->list[$offset] ?? null;
    }

    public function offsetSet(mixed $offset, mixed $value): void
    {
        if ($offset === null) {
            $this->list[] = $value;
        } else {
            $this->list[$offset] = $value;
        }
    }

    public function offsetUnset(mixed $offset): void
    {
        array_splice($this->list, (int)$offset, 1);
    }

    public function count(): int
    {
        return count($this->list);
    }

    public function getIterator(): \ArrayIterator
    {
        return new \ArrayIterator($this->list);
    }
}

/**
 * Class Struct
 *
 * Utility class for manipulating in-memory JSON-like data structures.
 * These utilities implement functions similar to the TypeScript version,
 * with emphasis on handling nodes, maps, lists, and special "undefined" values.
 */
class Struct
{

    /* =======================
     * String Constants
     * =======================
     */
    private const S_MKEYPRE = 'key:pre';
    private const S_MKEYPOST = 'key:post';
    private const S_MVAL = 'val';
    private const S_MKEY = 'key';

    private const S_DKEY = '`$KEY`';
    private const S_DMETA = '`$META`';
    private const S_DANNO = '`$ANNO`';
    
    // Match TypeScript constants exactly
    private const S_BKEY = '`$KEY`';
    private const S_BANNO = '`$ANNO`';
    private const S_DTOP = '$TOP';
    private const S_DERRS = '$ERRS';
    private const S_ERRS = '$ERRS';

    private const S_array = 'array';
    private const S_boolean = 'boolean';
    private const S_function = 'function';
    private const S_number = 'number';
    private const S_object = 'object';
    private const S_string = 'string';
    private const S_null = 'null';
    private const S_MT = '';
    private const S_BT = '`';
    private const S_DS = '$';
    private const S_DT = '.';
    private const S_CN = ':';
    private const S_KEY = 'KEY';
    public const S_BASE = 'base';

    /**
     * Legacy string marker for undefined. Kept for backward compatibility.
     * Internal code uses the $UNDEF sentinel object via undef().
     */
    public const UNDEF = '__UNDEFINED__';

    /** Sentinel object for undefined — can never collide with real data. */
    private static ?\stdClass $UNDEF = null;

    /** Return the sentinel object for undefined. */
    public static function undef(): \stdClass
    {
        if (self::$UNDEF === null) {
            self::$UNDEF = new \stdClass();
        }
        return self::$UNDEF;
    }

    public const T_any = (1 << 31) - 1;
    public const T_noval = 1 << 30;
    public const T_boolean = 1 << 29;
    public const T_decimal = 1 << 28;
    public const T_integer = 1 << 27;
    public const T_number = 1 << 26;
    public const T_string = 1 << 25;
    public const T_function = 1 << 24;
    public const T_symbol = 1 << 23;
    public const T_null = 1 << 22;
    public const T_list = 1 << 14;
    public const T_map = 1 << 13;
    public const T_instance = 1 << 12;
    public const T_scalar = 1 << 7;
    public const T_node = 1 << 6;

    public const DELETE = ['`$DELETE`' => true];

    private const S_CM = ',';

    private const TYPENAME = [
        'any', 'noval', 'boolean', 'decimal', 'integer', 'number', 'string',
        'function', 'symbol', 'null',
        '', '', '', '', '', '', '',
        'list', 'map', 'instance',
        '', '', '', '',
        'scalar', 'node',
    ];

    public const SKIP = ['`$SKIP`' => true];

    // Mode constants (bitfield) matching TypeScript canonical
    public const M_KEYPRE = 1;
    public const M_KEYPOST = 2;
    public const M_VAL = 4;

    public const MODENAME = [
        self::M_VAL => 'val',
        self::M_KEYPRE => 'key:pre',
        self::M_KEYPOST => 'key:post',
    ];

    private const PLACEMENT = [
        self::M_VAL => 'value',
        self::M_KEYPRE => 'key',
        self::M_KEYPOST => 'key',
    ];

    /* =======================
     * Regular expressions for validation and transformation
     * =======================
     */
    private const R_META_PATH = '/^([^$]+)\$([=~])(.+)$/';
    private const R_TRANSFORM_NAME = '/`\$([A-Z]+)`/';

    /* =======================
     * Private Helpers
     * =======================
     */

    /**
     * Determines whether an array has sequential integer keys, i.e. a list.
     *
     * @param array $val
     * @return bool True if the array is a list (i.e. sequential keys starting at 0).
     */
    private static function isListHelper(array $val): bool
    {
        return array_keys($val) === range(0, count($val) - 1);
    }

    /* =======================
     * Type and Existence Checks
     * =======================
     */

    public static function isnode(mixed $val): bool
    {
        if ($val === self::undef() || $val === null) {
            return false;
        }
        if ($val instanceof \Closure) {
            return false;
        }
        if ($val instanceof ListRef) {
            return true;
        }
        return is_object($val) || is_array($val);
    }



    /**
     * Check if a value is a map (associative array or object) rather than a list.
     *
     * @param mixed $val
     * @return bool
     */
    public static function ismap(mixed $val): bool
    {
        if ($val instanceof ListRef) {
            return false;
        }
        if ($val instanceof \Closure) {
            return false;
        }
        if ($val === self::undef()) {
            return false;
        }
        if (is_object($val)) {
            return true;
        }
        // Any PHP array that isn't a list is a map,
        // but treat *empty* arrays as lists (not maps).
        if (is_array($val)) {
            if (count($val) === 0) {
                return false;
            }
            return !self::islist($val);
        }
        return false;
    }



    /**
     * Check if a value is a list (sequential array).
     *
     * @param mixed $val
     * @return bool
     */
    public static function islist(mixed $val): bool
    {
        if ($val instanceof ListRef) {
            return true;
        }
        if (!is_array($val)) {
            return false;
        }
        $i = 0;
        foreach ($val as $k => $_) {
            if ($k !== $i++) {
                return false;
            }
        }
        return true;
    }

    /**
     * Check if a key is valid (non-empty string or integer/float).
     *
     * @param mixed $key
     * @return bool
     */
    public static function iskey(mixed $key): bool
    {
        if ($key === self::undef()) { // Explicit check for UNDEF
            return false;
        }
        if (is_string($key)) {
            return strlen($key) > 0;
        }
        return is_int($key) || is_float($key);
    }
    /**
     * Check if a value is empty.
     * Considers undefined, null, empty string, empty array, or empty object.
     *
     * @param mixed $val
     * @return bool
     */
    public static function isempty(mixed $val): bool
    {
        if ($val === self::undef() || $val === null || $val === self::S_MT) {
            return true;
        }
        if (is_array($val) && count($val) === 0) {
            return true;
        }
        if (is_object($val) && count(get_object_vars($val)) === 0) {
            return true;
        }
        return false;
    }

    /**
     * Check if a value is callable.
     *
     * @param mixed $val
     * @return bool
     */
    public static function isfunc(mixed $val): bool
    {
        return is_callable($val);
    }

    public static function typify(mixed $value): int
    {
        if ($value === self::undef()) {
            return self::T_noval;
        }
        if ($value === null) {
            return self::T_scalar | self::T_null;
        }
        if (is_bool($value)) {
            return self::T_scalar | self::T_boolean;
        }
        if (is_int($value)) {
            return self::T_scalar | self::T_number | self::T_integer;
        }
        if (is_float($value)) {
            return self::T_scalar | self::T_number | self::T_decimal;
        }
        if (is_string($value)) {
            return self::T_scalar | self::T_string;
        }
        if ($value instanceof \Closure) {
            return self::T_scalar | self::T_function;
        }
        if (is_callable($value) && !is_array($value) && !is_object($value)) {
            return self::T_scalar | self::T_function;
        }
        if ($value instanceof ListRef) {
            return self::T_node | self::T_list;
        }
        if (is_array($value)) {
            if (self::islist($value)) {
                return self::T_node | self::T_list;
            } else {
                return self::T_node | self::T_map;
            }
        }
        if (is_object($value)) {
            return self::T_node | self::T_map;
        }
        return self::T_noval;
    }

    public static function typename(int $type): string
    {
        if ($type <= 0) {
            return self::TYPENAME[0];
        }
        $clz = 31 - (int) floor(log($type, 2));
        return self::TYPENAME[$clz] ?? self::TYPENAME[0];
    }

    /**
     * Get a defined value. Returns alt if val is undefined.
     */
    public static function getdef(mixed $val, mixed $alt): mixed
    {
        if ($val === self::undef() || $val === null) {
            return $alt;
        }
        return $val;
    }

    /**
     * Replace a search string (all), or a regex pattern, in a source string.
     */
    public static function replace(string $s, string|array $from, mixed $to): string
    {
        $rs = $s;
        $ts = self::typify($s);
        if (0 === (self::T_string & $ts)) {
            $rs = self::stringify($s);
        } elseif (0 < ((self::T_noval | self::T_null) & $ts)) {
            $rs = self::S_MT;
        }
        if (is_string($from) && @preg_match($from, '') !== false && $from[0] === '/') {
            return preg_replace($from, (string)$to, $rs);
        }
        return str_replace((string)$from, (string)$to, $rs);
    }

    /**
     * Define a JSON Object using key-value arguments.
     */
    public static function jm(mixed ...$kv): object
    {
        $kvsize = count($kv);
        $o = new \stdClass();
        for ($i = 0; $i < $kvsize; $i += 2) {
            $k = $kv[$i] ?? ('$KEY' . $i);
            $k = is_string($k) ? $k : self::stringify($k);
            $o->$k = $kv[$i + 1] ?? null;
        }
        return $o;
    }

    /**
     * Define a JSON Array using arguments.
     */
    public static function jt(mixed ...$v): array
    {
        return array_values($v);
    }

    public static function getprop(mixed $val, mixed $key, mixed $alt = null): mixed
    {
        $altExplicit = func_num_args() >= 3;
        $out = self::_getprop($val, $key, self::undef());
        if ($out === self::undef()) {
            return $altExplicit ? $alt : null;
        }
        return $out;
    }


    // Internal getprop returning the UNDEF sentinel for missing keys so the
    // injection/transform machinery can distinguish "missing" from a stored null.
    // External callers should use getprop(), which normalises UNDEF to null (or $alt).
    public static function _getprop(mixed $val, mixed $key, mixed $alt = null): mixed
    {
        if ($alt === null) { $alt = self::undef(); }
        // 1) undefined‐marker or invalid key → alt
        if ($val === self::undef() || $key === self::undef()) {
            return $alt;
        }
        if (!self::iskey($key)) {
            return $alt;
        }
        if ($val === null) {
            return $alt;
        }

        // 2) ListRef branch
        if ($val instanceof ListRef) {
            $ki = is_numeric($key) ? (int)$key : -1;
            $out = ($ki >= 0 && $ki < count($val->list)) ? $val->list[$ki] : $alt;
        }
        // 3) array branch
        elseif (is_array($val) && array_key_exists($key, $val)) {
            $out = $val[$key];
        }
        // 4) object branch: cast $key to string
        elseif (is_object($val)) {
            $prop = (string) $key;
            if (property_exists($val, $prop)) {
                $out = $val->$prop;
            } else {
                $out = $alt;
            }
        }
        // 4) fallback
        else {
            $out = $alt;
        }

        // 5) JSON‐null‐marker check
        return ($out === self::undef() ? $alt : $out);
    }


    public static function strkey(mixed $key = null): string
    {
        if ($key === null || $key === self::undef()) {
            return self::S_MT;
        }
        if (is_string($key)) {
            return $key;
        }
        if (is_bool($key)) {
            return self::S_MT;
        }
        if (is_int($key)) {
            return (string) $key;
        }
        if (is_float($key)) {
            return (string) floor($key);
        }
        return self::S_MT;
    }

    /**
     * Get a sorted list of keys from a node (map or list).
     *
     * @param mixed $val
     * @return array
     */
    public static function keysof(mixed $val): array
    {
        if (!self::isnode($val)) {
            return [];
        }
        if (self::ismap($val)) {
            $keys = is_array($val) ? array_keys($val) : array_keys(get_object_vars($val));
            sort($keys, SORT_STRING);
            return $keys;
        } elseif ($val instanceof ListRef) {
            return array_map('strval', array_keys($val->list));
        } elseif (self::islist($val)) {
            return array_map('strval', array_keys($val));
        }
        return [];
    }

    /**
     * Determine if a node has a defined property with the given key.
     *
     * @param mixed $val
     * @param mixed $key
     * @return bool
     */
    public static function haskey(mixed $val = null, mixed $key = null): bool
    {
        // 1. Validate $val is a node
        if (!self::isnode($val)) {
            return false;
        }

        // 2. Validate $key is a valid key
        if (!self::iskey($key)) {
            return false;
        }

        // 3. Check property existence
        $marker = new \stdClass();
        return self::_getprop($val, $key, $marker) !== $marker;
    }

    public static function items(mixed $val, ?callable $apply = null): array
    {
        $result = [];
        if (self::islist($val)) {
            foreach ($val as $k => $v) {
                $result[] = [(string) $k, $v];
            }
        } else {
            foreach (self::keysof($val) as $k) {
                $result[] = [$k, self::_getprop($val, $k)];
            }
        }
        if ($apply !== null) {
            $result = array_map($apply, $result);
        }
        return $result;
    }

    public static function escre(?string $s): string
    {
        $s = $s ?? self::S_MT;
        return preg_quote($s, '/');
    }

    public static function escurl(?string $s): string
    {
        $s = $s ?? self::S_MT;
        return rawurlencode($s);
    }

    public static function joinurl(array $sarr): string
    {
        return self::join($sarr, '/', true);
    }

    public static function filter(mixed $val, callable $check): array
    {
        $all = self::items($val);
        $numall = self::size($all);
        $out = [];
        for ($i = 0; $i < $numall; $i++) {
            if ($check($all[$i])) {
                $out[] = $all[$i][1];
            }
        }
        return $out;
    }

    public static function join(mixed $arr, ?string $sep = null, ?bool $url = false): string
    {
        $sarr = self::size($arr);
        $sepdef = $sep ?? self::S_CM;
        $sepre = (1 === strlen($sepdef)) ? self::escre($sepdef) : '';

        $filtered = self::filter($arr, function ($n) {
            return (0 < (self::T_string & self::typify($n[1]))) && self::S_MT !== $n[1];
        });

        $mapped = self::filter(
            self::items($filtered, function ($n) use ($sepre, $sepdef, $url, $sarr) {
                $i = (int) $n[0];
                $s = $n[1];

                if ('' !== $sepre && self::S_MT !== $sepre) {
                    if ($url && 0 === $i) {
                        $s = preg_replace('/' . $sepre . '+$/', self::S_MT, $s);
                        return $s;
                    }

                    if (0 < $i) {
                        $s = preg_replace('/^' . $sepre . '+/', self::S_MT, $s);
                    }

                    if ($i < $sarr - 1 || !$url) {
                        $s = preg_replace('/' . $sepre . '+$/', self::S_MT, $s);
                    }

                    $s = preg_replace('/([^' . $sepre . '])' . $sepre . '+([^' . $sepre . '])/',
                        '$1' . $sepdef . '$2', $s);
                }

                return $s;
            }),
            function ($n) {
                return self::S_MT !== $n[1];
            }
        );

        return implode($sepdef, $mapped);
    }

    public static function jsonify(mixed $val, mixed $flags = null): string
    {
        $str = 'null';

        if ($val !== null && $val !== self::undef() && !($val instanceof \Closure)) {
            if ($val instanceof ListRef) {
                $val = self::cloneUnwrap($val);
            }
            $indent = self::_getprop($flags, 'indent', 2);
            try {
                $encoded = json_encode($val, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES);
                if ($encoded === false) {
                    return '__JSONIFY_FAILED__';
                }

                // PHP's JSON_PRETTY_PRINT uses 4-space indents; convert to requested indent
                $encoded = preg_replace_callback('/^(    +)/m', function ($matches) use ($indent) {
                    $level = (int)(strlen($matches[1]) / 4);
                    return str_repeat(' ', $level * $indent);
                }, $encoded);

                $str = $encoded;

                $offset = self::_getprop($flags, 'offset', 0);
                if (0 < $offset) {
                    $lines = explode("\n", $str);
                    $rest = array_slice($lines, 1);
                    $padded = self::filter(
                        self::items($rest, function ($n) use ($offset) {
                            return self::pad($n[1], 0 - $offset - self::size($n[1]));
                        }),
                        function ($n) { return true; }
                    );
                    $str = "{\n" . implode("\n", $padded);
                }
            } catch (\Exception $e) {
                $str = '__JSONIFY_FAILED__';
            }
        }

        return $str;
    }

    /**
     * The integer size of the value. For arrays and strings, the length,
     * for numbers, the integer part, for boolean, true is 1 and false is 0, for all other values, 0.
     */
    public static function size(mixed $val): int
    {
        if ($val === null || $val === self::undef()) {
            return 0;
        }

        if (self::islist($val)) {
            return count($val);
        } elseif (self::ismap($val)) {
            return count(get_object_vars($val));
        }

        if (is_string($val)) {
            return strlen($val);
        } elseif (is_numeric($val)) {
            return (int) floor((float) $val);
        } elseif (is_bool($val)) {
            return $val ? 1 : 0;
        } else {
            return 0;
        }
    }

    /**
     * Extract part of an array or string into a new value, from the start point to the end point.
     * If no end is specified, extract to the full length of the value. Negative arguments count
     * from the end of the value.
     */
    public static function slice(mixed $val, ?int $start = null, ?int $end = null): mixed
    {
        if (is_numeric($val)) {
            $start = $start ?? PHP_INT_MIN;
            $end = ($end ?? PHP_INT_MAX) - 1;
            $result = min(max((float) $val, $start), $end);
            // Return integer if the original value was an integer
            return is_int($val) ? (int) $result : $result;
        }

        $vlen = self::size($val);

        if ($end !== null && $start === null) {
            $start = 0;
        }

        if ($start !== null) {
            if ($start < 0) {
                $end = $vlen + $start;
                if ($end < 0) {
                    $end = 0;
                }
                $start = 0;
            } elseif ($end !== null) {
                if ($end < 0) {
                    $end = $vlen + $end;
                    if ($end < 0) {
                        $end = 0;
                    }
                } elseif ($vlen < $end) {
                    $end = $vlen;
                }
            } else {
                $end = $vlen;
            }

            if ($vlen < $start) {
                $start = $vlen;
            }

            if (-1 < $start && $start <= $end && $end <= $vlen) {
                if ($val instanceof ListRef) {
                    $val = new ListRef(array_slice($val->list, $start, $end - $start));
                } elseif (self::islist($val)) {
                    $val = array_slice($val, $start, $end - $start);
                } elseif (is_string($val)) {
                    $val = substr($val, $start, $end - $start);
                }
            } else {
                if ($val instanceof ListRef) {
                    $val = new ListRef([]);
                } elseif (self::islist($val)) {
                    $val = [];
                } elseif (is_string($val)) {
                    $val = self::S_MT;
                }
            }
        }

        return $val;
    }

    /**
     * Pad a string with a character to a specified length.
     */
    public static function pad(mixed $str, ?int $padding = null, ?string $padchar = null): string
    {
        $str = self::stringify($str);
        $padding = $padding ?? 44;
        $padchar = $padchar ?? ' ';
        $padchar = ($padchar . ' ')[0]; // Get first character or space as fallback
        
        if ($padding >= 0) {
            return str_pad($str, $padding, $padchar, STR_PAD_RIGHT);
        } else {
            return str_pad($str, abs($padding), $padchar, STR_PAD_LEFT);
        }
    }

    /* =======================
     * Stringification and Cloning
     * =======================
     */

    /**
     * Recursively sorts a node (array or object) to ensure consistent stringification.
     *
     * @param mixed $val
     * @return mixed
     */
    private static function sort_obj(mixed $val): mixed
    {
        if (is_array($val)) {
            if (self::islist($val)) {
                return array_map([self::class, 'sort_obj'], $val);
            } else {
                ksort($val);
                foreach ($val as $k => $v) {
                    $val[$k] = self::sort_obj($v);
                }
                return $val;
            }
        } elseif (is_object($val)) {
            $arr = get_object_vars($val);
            ksort($arr);
            foreach ($arr as $k => $v) {
                $arr[$k] = self::sort_obj($v);
            }
            return $arr;
        }
        return $val;
    }

    public static function stringify(mixed $val, ?int $maxlen = null, mixed $pretty = null): string
    {
        if ($val === self::undef()) {
            return $pretty ? '<>' : self::S_MT;
        }

        $valstr = self::S_MT;

        if (is_string($val)) {
            $valstr = $val;
        } else {
            $original = $val;
            // Unwrap ListRefs before JSON encoding
            if ($val instanceof ListRef) {
                $val = self::cloneUnwrap($val);
            }
            try {
                $sorted = self::sort_obj($val);
                $str = json_encode($sorted);
                if ($str === false) {
                    $str = '__STRINGIFY_FAILED__';
                }
                $valstr = str_replace('"', '', $str);

                if (is_object($original) && $valstr === '[]') {
                    $valstr = '{}';
                }
            } catch (\Exception $e) {
                $valstr = '__STRINGIFY_FAILED__';
            }
        }

        if ($maxlen !== null && $maxlen > -1) {
            $js = substr($valstr, 0, $maxlen);
            $valstr = $maxlen < strlen($valstr)
                ? (substr($js, 0, $maxlen - 3) . '...')
                : $valstr;
        }

        return $valstr;
    }

    public static function pathify(mixed $val, ?int $startin = null, ?int $endin = null): string
    {
        $UNDEF = self::undef();
        $S_MT = self::S_MT;
        $S_CN = self::S_CN;
        $S_DT = self::S_DT;

        if (is_array($val) && (self::islist($val) || count($val) === 0)) {
            $path = $val;
        } elseif (is_string($val) || is_int($val) || is_float($val)) {
            $path = [$val];
        } else {
            $path = $UNDEF;
        }

        $start = ($startin === null || $startin < 0) ? 0 : $startin;
        $end = ($endin === null || $endin < 0) ? 0 : $endin;

        $pathstr = $UNDEF;

        if ($path !== $UNDEF && $start >= 0) {
            $len = count($path);
            $length = max(0, $len - $end - $start);
            $slice = array_slice($path, $start, $length);

            if (count($slice) === 0) {
                $pathstr = '<root>';
            } else {
                $parts = [];
                foreach ($slice as $p) {
                    if (!self::iskey($p)) {
                        continue;
                    }
                    if (is_int($p) || is_float($p)) {
                        $parts[] = $S_MT . (string) floor($p);
                    } else {
                        $parts[] = str_replace('.', $S_MT, (string) $p);
                    }
                }
                $pathstr = implode($S_DT, $parts);
            }
        }

        if ($pathstr === $UNDEF) {
            if ($val === $UNDEF || $val === null) {
                $pathstr = '<unknown-path>';
            } elseif (is_object($val) && count(get_object_vars($val)) === 0) {
                // empty object
                $pathstr = '<unknown-path:{}>';
            } else {
                // booleans, numbers, non-empty objects, etc.
                $pathstr = '<unknown-path' . $S_CN . self::stringify($val, 47) . '>';
            }
        }

        return $pathstr;
    }


    public static function flatten(mixed $list, ?int $depth = null): mixed
    {
        if (!self::islist($list)) {
            return $list;
        }
        $depth = $depth ?? 1;
        $result = [];
        foreach ($list as $item) {
            if (self::islist($item) && $depth > 0) {
                $sub = self::flatten($item, $depth - 1);
                foreach ($sub as $v) {
                    $result[] = $v;
                }
            } else {
                $result[] = $item;
            }
        }
        return $result;
    }

    public static function clone(mixed $val): mixed
    {
        if ($val === self::undef()) {
            return self::undef();
        }
        $refs = [];
        $replacer = function (mixed $v) use (&$refs, &$replacer): mixed {
            if ($v instanceof \Closure || (is_object($v) && !($v instanceof \stdClass) && !($v instanceof ListRef) && method_exists($v, '__invoke'))) {
                $refs[] = $v;
                return '`$FUNCTION:' . (count($refs) - 1) . '`';
            } elseif ($v instanceof ListRef) {
                $newList = [];
                foreach ($v->list as $item) {
                    $newList[] = $replacer($item);
                }
                return new ListRef($newList);
            } elseif (is_array($v)) {
                $result = [];
                foreach ($v as $k => $item) {
                    $result[$k] = $replacer($item);
                }
                return $result;
            } elseif (is_object($v)) {
                $objVars = get_object_vars($v);
                $result = new \stdClass();
                foreach ($objVars as $k => $item) {
                    $result->$k = $replacer($item);
                }
                return $result;
            } else {
                return $v;
            }
        };
        $temp = $replacer($val);
        $reviver = function (mixed $v) use (&$refs, &$reviver): mixed {
            if (is_string($v)) {
                if (preg_match('/^`\$FUNCTION:([0-9]+)`$/', $v, $matches)) {
                    $idx = (int) $matches[1];
                    if (isset($refs[$idx])) {
                        return $refs[$idx];
                    }
                }
                return $v;
            } elseif ($v instanceof ListRef) {
                $newList = [];
                foreach ($v->list as $item) {
                    $newList[] = $reviver($item);
                }
                return new ListRef($newList);
            } elseif (is_array($v)) {
                $result = [];
                foreach ($v as $k => $item) {
                    $result[$k] = $reviver($item);
                }
                return $result;
            } elseif (is_object($v)) {
                $objVars = get_object_vars($v);
                $result = new \stdClass();
                foreach ($objVars as $k => $item) {
                    $result->$k = $reviver($item);
                }
                return $result;
            } else {
                return $v;
            }
        };
        return $reviver($temp);
    }

    /**
     * Clone a value, wrapping all sequential arrays in ListRef for reference stability.
     * Mirrors Go's CloneFlags(val, {wrap: true}).
     */
    public static function cloneWrap(mixed $val): mixed
    {
        if ($val === null || $val === self::undef()) {
            return $val;
        }
        if ($val instanceof \Closure) {
            return $val;
        }
        if ($val instanceof ListRef) {
            $newList = [];
            foreach ($val->list as $item) {
                $newList[] = self::cloneWrap($item);
            }
            return new ListRef($newList);
        }
        if (is_array($val)) {
            if (self::isListHelper($val) || empty($val)) {
                $newList = [];
                foreach ($val as $item) {
                    $newList[] = self::cloneWrap($item);
                }
                return new ListRef($newList);
            }
            // Assoc array (map-array) - clone as stdClass
            $result = new \stdClass();
            foreach ($val as $k => $v) {
                $result->$k = self::cloneWrap($v);
            }
            return $result;
        }
        if ($val instanceof \stdClass) {
            $result = new \stdClass();
            foreach (get_object_vars($val) as $k => $v) {
                $result->$k = self::cloneWrap($v);
            }
            return $result;
        }
        // Class instances and scalars returned as-is
        return $val;
    }

    /**
     * Clone a value, unwrapping all ListRef back to plain arrays.
     * Mirrors Go's CloneFlags(val, {unwrap: true}).
     */
    public static function cloneUnwrap(mixed $val, int $depth = 0): mixed
    {
        if ($depth > 32) {
            return $val;
        }
        if ($val instanceof ListRef) {
            $result = [];
            foreach ($val->list as $item) {
                $result[] = self::cloneUnwrap($item, $depth + 1);
            }
            return $result;
        }
        if ($val instanceof \stdClass) {
            $result = new \stdClass();
            foreach (get_object_vars($val) as $k => $v) {
                $result->$k = self::cloneUnwrap($v, $depth + 1);
            }
            return $result;
        }
        if (is_array($val)) {
            $result = [];
            foreach ($val as $k => $v) {
                $result[$k] = self::cloneUnwrap($v, $depth + 1);
            }
            return $result;
        }
        return $val;
    }

    /**
     * @internal
     * Set a property or list‐index on a "node" (stdClass or PHP array).
     * Respects undef‐marker removals, numeric vs string keys, and
     * list‐vs‐map semantics.
     */
    public static function setprop(mixed &$parent, mixed $key, mixed $val): mixed
    {
        // only valid keys make sense
        if (!self::iskey($key)) {
            return $parent;
        }

        // ─── LISTREF ────────────────────────────────────────────────
        if ($parent instanceof ListRef) {
            if (!is_numeric($key)) {
                return $parent;
            }
            $keyI = (int) floor((float) $key);
            if ($val === self::undef()) {
                if ($keyI >= 0 && $keyI < count($parent->list)) {
                    array_splice($parent->list, $keyI, 1);
                }
            } elseif ($keyI >= 0) {
                if ($keyI >= count($parent->list)) {
                    $parent->list[] = $val;
                } else {
                    $parent->list[$keyI] = $val;
                }
            } else {
                array_unshift($parent->list, $val);
            }
            return $parent;
        }

        // ─── OBJECT (map) ───────────────────────────────────────────
        if (is_object($parent)) {
            $keyStr = self::strkey($key);
            if ($val === self::undef()) {
                unset($parent->$keyStr);
            } else {
                $parent->$keyStr = $val;
            }
            return $parent;
        }

        // ─── ARRAY ──────────────────────────────────────────────────
        if (is_array($parent)) {
            if (!self::islist($parent)) {
                // map‐array
                $keyStr = self::strkey($key);
                if ($val === self::undef()) {
                    unset($parent[$keyStr]);
                } elseif (ctype_digit((string) $key)) {
                    // numeric string key: unshift (TS always merges maps by overwriting)
                    $parent = [$keyStr => $val] + $parent;
                } else {
                    $parent[$keyStr] = $val;
                }
            } else {
                // list‐array
                if (!is_numeric($key)) {
                    return $parent;
                }
                $keyI = (int) floor((float) $key);
                if ($val === self::undef()) {
                    if ($keyI >= 0 && $keyI < count($parent)) {
                        array_splice($parent, $keyI, 1);
                    }
                } elseif ($keyI >= 0) {
                    if (count($parent) < $keyI) {
                        $parent[] = $val;
                    } else {
                        $parent[$keyI] = $val;
                    }
                } else {
                    array_unshift($parent, $val);
                }
            }
        }

        return $parent;
    }


    private const MAXDEPTH = 32;

    /**
     * Walk a data structure depth first, applying callbacks to each value.
     *
     * The `$path` argument passed to the before/after callbacks is backed
     * by a per-depth slot in a shared pool that lives for the duration of
     * the top-level walk call. Read-only consumers (count/size, implode,
     * iteration) see the current path contents without triggering a copy
     * under PHP's copy-on-write semantics. Callbacks that need to retain
     * the path MUST clone it (e.g. via `array_values($path)`); otherwise
     * its contents will be overwritten by subsequent visits.
     */
    public static function walk(
        mixed $val,
        ?callable $before = null,
        ?callable $after = null,
        ?int $maxdepth = null,
        mixed $key = null,
        mixed $parent = null,
        ?array $path = null
    ): mixed {
        $pool = [[]];
        return self::_walk($val, $before, $after, $maxdepth, $key, $parent, $path ?? $pool[0], $pool);
    }

    /**
     * Recursive walk helper. The pool is passed by reference so each depth
     * reuses the same path buffer across sibling iterations, eliminating
     * the per-node path allocation the original implementation incurred.
     *
     * @param array<int, array<int, string>> $pool
     */
    private static function _walk(
        mixed $val,
        ?callable $before,
        ?callable $after,
        ?int $maxdepth,
        mixed $key,
        mixed $parent,
        array $path,
        array &$pool
    ): mixed {
        $depth = count($path);

        $out = ($before !== null) ? $before($key, $val, $parent, $path) : $val;

        $md = ($maxdepth !== null && $maxdepth >= 0) ? $maxdepth : self::MAXDEPTH;
        if (0 === $md || ($depth > 0 && $md <= $depth)) {
            return $out;
        }

        if (self::isnode($out)) {
            $childDepth = $depth + 1;
            if (!array_key_exists($childDepth, $pool)) {
                $pool[$childDepth] = [];
            }
            // Sync prefix [0..depth-1] into the child slot. Siblings at the
            // same level share this prefix; only slot [$depth] differs
            // between iterations.
            for ($i = 0; $i < $depth; $i++) {
                $pool[$childDepth][$i] = $path[$i];
            }

            foreach (self::items($out) as [$childKey, $childVal]) {
                $pool[$childDepth][$depth] = self::S_MT . $childKey;
                $result = self::_walk(
                    $childVal, $before, $after, $md, $childKey, $out, $pool[$childDepth], $pool
                );
                if (self::ismap($out)) {
                    if (is_object($out)) {
                        $out->{self::strkey($childKey)} = $result;
                    } else {
                        $out[self::strkey($childKey)] = $result;
                    }
                } else {
                    $out[(int) $childKey] = $result;
                }
            }
        }

        $out = ($after !== null) ? $after($key, $out, $parent, $path) : $out;

        return $out;
    }

    public static function merge(mixed $val, ?int $maxdepth = null): mixed
    {
        $md = self::slice($maxdepth ?? self::MAXDEPTH, 0);

        if (!self::islist($val)) {
            return $val;
        }

        $list = $val;
        $lenlist = count($list);

        if (0 === $lenlist) {
            return self::undef();
        } elseif (1 === $lenlist) {
            return $list[0];
        }

        $out = self::_getprop($list, 0, new \stdClass());

        for ($oI = 1; $oI < $lenlist; $oI++) {
            $obj = $list[$oI];

            if (!self::isnode($obj)) {
                $out = $obj;
            } else {
                $cur = [&$out];
                $dst = [&$out];

                $before = function ($key, $val, $_parent, $path) use (&$cur, &$dst, $md) {
                    $pI = self::size($path);

                    if ($md <= $pI) {
                        self::setprop($cur[$pI - 1], $key, $val);
                    } elseif (!self::isnode($val)) {
                        $cur[$pI] = $val;
                    } else {
                        $dst[$pI] = 0 < $pI ? self::_getprop($dst[$pI - 1], $key) : $dst[$pI];
                        $tval = $dst[$pI];

                        if (self::undef() === $tval && 0 === (self::T_instance & self::typify($val))) {
                            $cur[$pI] = self::islist($val) ? [] : new \stdClass();
                        } elseif (self::typify($val) === self::typify($tval)) {
                            $cur[$pI] = $tval;
                        } else {
                            $cur[$pI] = $val;
                            $val = self::undef();
                        }
                    }

                    return $val;
                };

                $after = function ($key, $_val, $_parent, $path) use (&$cur) {
                    $cI = self::size($path);
                    $value = $cur[$cI] ?? null;
                    if ($cI > 0) {
                        self::setprop($cur[$cI - 1], $key, $value);
                    }
                    return $value;
                };

                $out = self::walk($obj, $before, $after, $md);
            }
        }

        if (0 === $md) {
            $out = self::getelem($list, -1);
            $out = self::islist($out) ? [] : (self::ismap($out) ? new \stdClass() : $out);
        }

        return $out;
    }

    public static function getpath(
        mixed $store,
        mixed $path,
        mixed $injdef = null
    ): mixed {
        // Convert path to array of parts
        $parts = is_array($path) ? $path :
            (is_string($path) ? explode('.', $path) :
                (is_numeric($path) ? [self::strkey($path)] : self::undef()));

        if ($parts === self::undef()) {
            return self::undef();
        }

        $val = $store;
        $base = self::_getprop($injdef, 'base');
        $src = self::_getprop($store, $base, $store);
        $numparts = count($parts);
        $dparent = self::_getprop($injdef, 'dparent');

        // An empty path (incl empty string) just finds the src (base data)
        if ($path === null || $store === null || ($numparts === 1 && $parts[0] === '')) {
            $val = $src;
        } else if ($numparts > 0) {
            // Check for $ACTIONs
            if ($numparts === 1) {
                $val = self::_getprop($store, $parts[0]);
            }

            if (!self::isfunc($val)) {
                $val = $src;

                // Check for meta path in first part
                if (preg_match('/^([^$]+)\$([=~])(.+)$/', $parts[0], $m) && $injdef && isset($injdef->meta)) {
                    $val = self::_getprop($injdef->meta, $m[1]);
                    $parts[0] = $m[3];
                }

                $dpath = self::_getprop($injdef, 'dpath');

                for ($pI = 0; $val !== self::undef() && $pI < count($parts); $pI++) {
                    $part = $parts[$pI];

                    if ($injdef && $part === '$KEY') {
                        $part = self::_getprop($injdef, 'key');
                    } else if ($injdef && str_starts_with($part, '$GET:')) {
                        // $GET:path$ -> get store value, use as path part (string)
                        $getpath = substr($part, 5, -1);
                        $getval = self::getpath($src, $getpath);
                        $part = self::stringify($getval);
                    } else if ($injdef && str_starts_with($part, '$REF:')) {
                        // $REF:refpath$ -> get spec value, use as path part (string)
                        $refpath = substr($part, 5, -1);
                        $part = self::stringify(self::getpath(self::_getprop($store, '$SPEC'), self::slice($part, 5, -1)));
                    } else if ($injdef && str_starts_with($part, '$META:')) {
                        // $META:metapath$ -> get meta value, use as path part (string)
                        $part = self::stringify(self::getpath(self::_getprop($injdef, 'meta'), substr($part, 6, -1)));
                    }

                    // $$ escapes $
                    $part = str_replace('$$', '$', $part);

                    if ($part === '') {
                        $ascends = 0;
                        while ($pI + 1 < count($parts) && $parts[$pI + 1] === '') {
                            $ascends++;
                            $pI++;
                        }

                        if ($injdef && $ascends > 0) {
                            if ($pI === count($parts) - 1) {
                                $ascends--;
                            }

                            if ($ascends === 0) {
                                $val = $dparent;
                            } else {
                                $fullpath = self::flatten([self::slice($dpath, 0 - $ascends), array_slice($parts, $pI + 1)]);

                                if (is_array($dpath) && $ascends <= count($dpath)) {
                                    $val = self::getpath($store, $fullpath);
                                } else {
                                    $val = self::undef();
                                }
                                break;
                            }
                        } else {
                            // Special case for single dot: use dparent if available
                            if ($dparent !== null && $dparent !== self::undef()) {
                                $val = $dparent;
                            } else {
                                $val = $src;
                            }
                        }
                    } else {
                        $val = self::_getprop($val, $part);
                    }
                }
            }
        }

        // Inj may provide a custom handler to modify found value
        $handler = self::_getprop($injdef, 'handler');
        if ($injdef !== null && self::isfunc($handler)) {
            $ref = self::pathify($path);
            $val = call_user_func($handler, $injdef, $val, $ref, $store);
        }

        return $val;
    }


    public static function inject(
        mixed $val,
        mixed $store,
        mixed $injdef = null
    ): mixed {
        $valtype = gettype($val);

        /** @var Injection $inj */
        $inj = $injdef;

        // Create state if at root of injection. The input value is placed
        // inside a virtual parent holder to simplify edge cases.
        if (self::undef() === $injdef || null === $injdef || !($injdef instanceof Injection)) {
            $inj = new Injection($val, (object) [self::S_DTOP => $val]);
            $inj->dparent = $store;
            $inj->errs = self::_getprop($store, self::S_DERRS, []);
            if (!isset($inj->meta->__d)) {
                $inj->meta->__d = 0;
            }

            if (self::undef() !== $injdef && null !== $injdef) {
                $inj->modify = (is_object($injdef) && property_exists($injdef, 'modify') && null !== $injdef->modify) ? $injdef->modify : $inj->modify;
                $inj->extra = (is_object($injdef) && property_exists($injdef, 'extra') && null !== $injdef->extra) ? $injdef->extra : ($inj->extra ?? null);
                $inj->meta = (is_object($injdef) && property_exists($injdef, 'meta') && null !== $injdef->meta) ? $injdef->meta : $inj->meta;
                $inj->handler = (is_object($injdef) && property_exists($injdef, 'handler') && null !== $injdef->handler) ? $injdef->handler : $inj->handler;
            }
        }

        $inj->descend();

        // Descend into node.
        if (self::isnode($val)) {
            $nodekeys = self::keysof($val);

            if (self::ismap($val)) {
                $nonDollar = [];
                $dollar = [];
                foreach ($nodekeys as $nk) {
                    if (str_contains((string) $nk, self::S_DS)) {
                        $dollar[] = $nk;
                    } else {
                        $nonDollar[] = $nk;
                    }
                }
                $nodekeys = array_merge($nonDollar, $dollar);
            } else {
                $nodekeys = self::keysof($val);
            }

            for ($nkI = 0; $nkI < count($nodekeys); $nkI++) {
                $childinj = $inj->child($nkI, $nodekeys);
                $nodekey = $childinj->key;
                $childinj->mode = self::M_KEYPRE;

                // Perform the key:pre mode injection on the child key.
                $prekey = self::_injectstr($nodekey, $store, $childinj);

                // The injection may modify child processing.
                $nkI = $childinj->keyI;
                $nodekeys = $childinj->keys;

                // Prevent further processing by returning an undefined prekey
                if (self::undef() !== $prekey) {
                    $childinj->val = self::_getprop($val, $prekey);
                    $childinj->mode = self::M_VAL;

                    // Perform the val mode injection on the child value.
                    // NOTE: return value is not used.
                    self::inject($childinj->val, $store, $childinj);

                    // The injection may modify child processing.
                    $nkI = $childinj->keyI;
                    $nodekeys = $childinj->keys;

                    // Perform the key:post mode injection on the child key.
                    $childinj->mode = self::M_KEYPOST;
                    self::_injectstr($nodekey, $store, $childinj);

                    // The injection may modify child processing.
                    $nkI = $childinj->keyI;
                    $nodekeys = $childinj->keys;
                }

                // PHP: arrays are value types; propagate child mutations back to val & parent.
                // Skip sync if a transform modified an ancestor (checked via prior chain).
                if (is_array($val) && is_array($childinj->parent)) {
                    // Check that the grandparent (inj->parent) still references our list.
                    // If a transform like $REF replaced/deleted it, the stored value will differ.
                    $storedVal = self::_getprop($inj->parent, $inj->key);
                    if (is_array($storedVal)) {
                        $val = $childinj->parent;
                        $inj->val = $val;
                        self::setprop($inj->parent, $inj->key, $val);
                    }
                }
            }
        }
        // Inject paths into string scalars.
        else if ($valtype === 'string') {
            $inj->mode = self::M_VAL;
            $val = self::_injectstr($val, $store, $inj);
            if (self::SKIP !== $val) {
                $inj->setval($val);
            }
        }

        // Custom modification.
        if ($inj->modify && self::SKIP !== $val) {
            $mkey = $inj->key;
            $mparent = $inj->parent;
            $mval = self::_getprop($mparent, $mkey);

            call_user_func(
                $inj->modify,
                $mval,
                $mkey,
                $mparent,
                $inj,
                $store
            );
        }

        $inj->val = $val;

        // Original val reference may no longer be correct.
        // This return value is only used as the top level result.
        return self::_getprop($inj->parent, self::S_DTOP);
    }


    private static function _injectstr(
        string $val,
        mixed $store,
        ?object $inj = null
    ): mixed {
        // Can't inject into non-strings
        if ($val === self::S_MT) {
            return self::S_MT;
        }

        $out = $val;

        // Pattern examples: "`a.b.c`", "`$NAME`", "`$NAME1`", "``"
        $m = preg_match('/^`(\$[A-Z]+|[^`]*)[0-9]*`$/', $val, $matches);

        // Full string of the val is an injection.
        if ($m) {
            if ($inj !== null) {
                $inj->full = true;
            }
            $pathref = $matches[1];

            // Special escapes inside injection.
            if (strlen($pathref) > 3) {
                $pathref = str_replace('\\.', '.', $pathref);
                $pathref = str_replace('$BT', self::S_BT, $pathref);
                $pathref = str_replace('$DS', self::S_DS, $pathref);
            }

            // Get the extracted path reference.
            $out = self::getpath($store, $pathref, $inj);
        }
        else {
            // Check for injections within the string.
            $out = preg_replace_callback('/`([^`]+)`/', function($matches) use ($store, $inj) {
                $ref = $matches[1];

                if (strlen($ref) > 3) {
                    $ref = str_replace('\\.', '.', $ref);
                    $ref = str_replace('$BT', self::S_BT, $ref);
                    $ref = str_replace('$DS', self::S_DS, $ref);
                }
                if ($inj !== null) {
                    $inj->full = false;
                }

                $found = self::getpath($store, $ref, $inj);

                // Ensure inject value is a string.
                if ($found === self::undef()) {
                    return self::S_MT;
                }
                if (is_string($found)) {
                    return $found;
                }
                return json_encode($found instanceof ListRef ? self::cloneUnwrap($found) : $found);
            }, $val);

            // Also call the inj handler on the entire string, providing the
            // option for custom injection.
            if ($inj !== null && is_callable($inj->handler)) {
                $inj->full = true;
                $out = call_user_func($inj->handler, $inj, $out, $val, $store);
            }
        }

        return $out;
    }


    public static function _injecthandler(
        object $inj,
        mixed $val,
        string $ref,
        mixed $store
    ): mixed {
        $out = $val;

        // Check if val is a function (command transforms)
        $iscmd = self::isfunc($val) && (self::undef() === $ref || str_starts_with($ref, self::S_DS));

        // Only call val function if it is a special command ($NAME format).
        if ($iscmd) {
            $out = call_user_func($val, $inj, $val, $ref, $store);
        }
        // Update parent with value. Ensures references remain in node tree.
        elseif (self::M_VAL === $inj->mode && $inj->full) {
            $inj->setval($val);
        }
        return $out;
    }

    private static function _injecthandler_getpath(
        object $state,
        mixed $val,
        string $ref,
        mixed $store
    ): mixed {
        return self::_injecthandler($state, $val, $ref, $store);
    }

    /**
     * @internal
     * Delete a key from a map or list.
     */
    public static function transform_DELETE(
        object $state,
        mixed $val,
        mixed $ref,
        mixed $store
    ): mixed {
        // _setparentprop(state, UNDEF)
        $state->setval(self::undef());
        return self::undef();
    }

    /**
     * @internal
     * Copy value from source data.
     */
    public static function transform_COPY(
        object $state,
        mixed $val,
        mixed $ref,
        mixed $store
    ): mixed {
        if (self::M_VAL !== $state->mode) {
            return self::undef();
        }

        $out = self::_getprop($state->dparent, $state->key);
        $state->setval($out);

        return $out;
    }

    /**
     * @internal
     * As a value, inject the key of the parent node.
     * As a key, defines the name of the key property in the source object.
     */
    public static function transform_KEY(
        object $state,
        mixed $val,
        mixed $ref,
        mixed $store
    ): mixed {
        // only in "val" mode do anything
        if (self::M_VAL !== $state->mode) {
            return self::undef();
        }

        // if parent has a "$KEY" override, use that
        $keyspec = self::_getprop($state->parent, self::S_DKEY);
        if ($keyspec !== self::undef()) {
            // remove the marker
            self::setprop($state->parent, self::S_DKEY, self::undef());
            return self::_getprop($state->dparent, $keyspec);
        }

        // otherwise pull from $ANNO.KEY or fallback to the path index
        $meta = self::_getprop($state->parent, self::S_BANNO);
        $idx = count($state->path) - 2;
        return self::_getprop(
            $meta,
            self::S_KEY,
            self::_getprop($state->path, $idx)
        );
    }

    /**
     * @internal
     * Store meta data about a node.  Does nothing itself, just used by other transforms.
     */
    public static function transform_META(
        object $state,
        mixed $val,
        mixed $ref,
        mixed $store
    ): mixed {
        // remove the $META marker
        self::setprop($state->parent, self::S_DMETA, self::undef());
        return self::undef();
    }

    /**
     * @internal
     * Store annotation data about a node. Does nothing itself, just used by other transforms.
     */
    public static function transform_ANNO(
        object $state,
        mixed $val,
        mixed $ref,
        mixed $store
    ): mixed {
        // remove the $ANNO marker
        self::setprop($state->parent, self::S_BANNO, self::undef());
        return self::undef();
    }

    /**
     * @internal
     * Merge a list of objects into the current object.
     */
    public static function transform_MERGE(
        object $state,
        mixed $val,
        mixed $ref,
        mixed $store
    ): mixed {
        $mode = $state->mode;
        $key = $state->key;
        $parent = $state->parent;

        // Ensures $MERGE is removed from parent list (val mode).
        $out = self::undef();

        if (self::M_KEYPRE === $mode) {
            $out = $key;
        }
        // Operate after child values have been transformed.
        elseif (self::M_KEYPOST === $mode) {
            $out = $key;

            $args = self::_getprop($parent, $key);
            $args = self::islist($args) ? (($args instanceof ListRef) ? $args->list : $args) : [$args];

            // Remove the $MERGE command from a parent map.
            $state->setval(self::undef());

            // Literals in the parent have precedence, but we still merge onto
            // the parent object, so that node tree references are not changed.
            $mergelist = self::flatten([[$parent], $args, [clone $parent]]);

            self::merge($mergelist);
        }

        return $out;
    }


    public static function transform_EACH(
        object $state,
        mixed $_val,
        string $_ref,
        mixed $store
    ): mixed {
        // Remove remaining keys to avoid spurious processing.
        $state->keys = array_slice($state->keys, 0, 1);

        if (self::M_VAL !== $state->mode) {
            return self::undef();
        }

        // Get arguments: ['`$EACH`', 'source-path', child-template]
        $srcpath = self::_getprop($state->parent, 1);
        $child = self::clone(self::_getprop($state->parent, 2));

        // Source data.
        $srcstore = self::_getprop($store, $state->base, $store);
        $src = self::getpath($srcstore, $srcpath, $state);

        // Create parallel data structures: source entries :: child templates
        $tcur = [];
        $tval = [];

        $tkey = self::getelem($state->path, -2);
        $target = self::getelem($state->nodes, -2) ?? self::getelem($state->nodes, -1);

        // Create clones of the child template for each value of the current source.
        if (self::islist($src)) {
            $srcArr = ($src instanceof ListRef) ? $src->list : (array) $src;
            $tval = array_map(function($_) use ($child) {
                return self::clone($child);
            }, $srcArr);
        } elseif (self::ismap($src)) {
            $tval = [];
            foreach (self::items($src) as $item) {
                $template = self::merge([
                    self::clone($child),
                    (object) [self::S_BANNO => (object) [self::S_KEY => $item[0]]]
                ], 1);
                $tval[] = $template;
            }
        }

        $rval = [];

        if (0 < self::size($tval)) {
            $tcur = (null == $src) ? self::undef() : ($src instanceof ListRef ? $src->list : array_values((array) $src));

            $ckey = self::getelem($state->path, -2);

            $tpath = self::slice($state->path, -1);
            $dpath = self::flatten([self::S_DTOP, explode(self::S_DT, $srcpath), '$:' . $ckey]);

            // Parent structure.
            $tcur = (object) [$ckey => $tcur];

            if (1 < self::size($tpath)) {
                $pkey = self::getelem($state->path, -3, self::S_DTOP);
                $tcur = (object) [$pkey => $tcur];
                $dpath[] = '$:' . $pkey;
            }

            $tinj = $state->child(0, [$ckey]);
            $tinj->path = $tpath;
            $tinj->nodes = self::slice($state->nodes, -1);

            $tinj->parent = self::getelem($tinj->nodes, -1);
            self::setprop($tinj->parent, $ckey, $tval);

            $tinj->val = $tval;
            $tinj->dpath = $dpath;
            $tinj->dparent = $tcur;

            self::inject($tval, $store, $tinj);
            $rval = $tinj->val;
        }

        // Update ancestors.
        self::setprop($target, $tkey, $rval);

        // Prevent callee from damaging first list entry (since we are in `val` mode).
        return $rval[0] ?? self::undef();
    }




    /** @internal */
    public static function transform_PACK(
        object $state,
        mixed $_val,
        mixed $_ref,
        mixed $store
    ): mixed {
        $mode = $state->mode;
        $key = $state->key;
        $path = $state->path;
        $parent = $state->parent;
        $nodes = $state->nodes;

        // Only run in key:pre mode.
        if (self::M_KEYPRE !== $mode) {
            return self::undef();
        }

        // Get arguments. Spec arrays are wrapped in ListRef by transform() so
        // accept either a plain array or a ListRef here.
        $args = self::_getprop($parent, $key);
        if ($args instanceof ListRef) {
            $args = $args->list;
        }
        if (!is_array($args) || count($args) < 2) {
            return self::undef();
        }

        $srcpath = $args[0];
        $origchildspec = self::clone($args[1]);

        // Find key and target node.
        $tkey = self::getelem($path, -2);
        $pathsize = self::size($path);
        $target = self::getelem($nodes, $pathsize - 2) ?? self::getelem($nodes, $pathsize - 1);

        // Source data
        $srcstore = self::_getprop($store, $state->base, $store);
        $src = self::getpath($srcstore, $srcpath, $state);

        // Prepare source as a list.
        if (!self::islist($src)) {
            if (self::ismap($src)) {
                $newSrc = [];
                foreach (self::items($src) as $item) {
                    self::setprop($item[1], self::S_BANNO, (object) [self::S_KEY => $item[0]]);
                    $newSrc[] = $item[1];
                }
                $src = $newSrc;
            } else {
                return self::undef();
            }
        }

        if (null == $src) {
            return self::undef();
        }

        // Get keypath.
        $keypath = self::_getprop($origchildspec, self::S_BKEY);
        $childspec = self::delprop($origchildspec, self::S_BKEY);

        $child = $childspec;

        // Build parallel target object.
        $tval = new \stdClass();

        foreach (self::items($src) as $item) {
            $srckey = $item[0];
            $srcnode = $item[1];

            $nkey = $srckey;
            if (self::undef() !== $keypath) {
                if (is_string($keypath) && str_starts_with($keypath, '`')) {
                    $nkey = self::inject($keypath, self::merge([new \stdClass(), $store, (object) ['$TOP' => $srcnode]], 1));
                } else {
                    $nkey = self::getpath($srcnode, $keypath, $state);
                }
            }

            $tchild = self::clone($child);
            self::setprop($tval, $nkey, $tchild);

            $anno = self::_getprop($srcnode, self::S_BANNO);
            if (self::undef() === $anno) {
                self::delprop($tchild, self::S_BANNO);
            } else {
                self::setprop($tchild, self::S_BANNO, $anno);
            }
        }

        $rval = new \stdClass();

        if (!self::isempty($tval)) {
            // Build parallel source object.
            $tsrc = new \stdClass();
            foreach ($src as $i => $n) {
                $kn = null;
                if (self::undef() === $keypath) {
                    $kn = $i;
                } elseif (is_string($keypath) && str_starts_with($keypath, '`')) {
                    $kn = self::inject($keypath, self::merge([new \stdClass(), $store, (object) ['$TOP' => $n]], 1));
                } else {
                    $kn = self::getpath($n, $keypath, $state);
                }
                self::setprop($tsrc, $kn, $n);
            }

            $tpath = self::slice($state->path, -1);

            $ckey = self::getelem($state->path, -2);
            $dpath = self::flatten([self::S_DTOP, explode(self::S_DT, $srcpath), '$:' . $ckey]);

            $tcur = (object) [$ckey => $tsrc];

            if (1 < self::size($tpath)) {
                $pkey = self::getelem($state->path, -3, self::S_DTOP);
                $tcur = (object) [$pkey => $tcur];
                $dpath[] = '$:' . $pkey;
            }

            $tinj = $state->child(0, [$ckey]);
            $tinj->path = $tpath;
            $tinj->nodes = self::slice($state->nodes, -1);

            $tinj->parent = self::getelem($tinj->nodes, -1);
            $tinj->val = $tval;

            $tinj->dpath = $dpath;
            $tinj->dparent = $tcur;

            self::inject($tval, $store, $tinj);
            $rval = $tinj->val;
        }

        // Update ancestors.
        self::setprop($target, $tkey, $rval);

        // Drop transform key.
        return self::undef();
    }


    /** @internal */
    public static function transform_REF(object $state, mixed $_val, string $_ref, mixed $store): mixed
    {
        $nodes = $state->nodes;

        if (self::M_VAL !== $state->mode) {
            return self::undef();
        }

        // Get arguments: ['`$REF`', 'ref-path'].
        $refpath = self::_getprop($state->parent, 1);
        $state->keyI = self::size($state->keys);

        // Spec reference.
        $specFn = self::_getprop($store, '$SPEC');
        $spec = is_callable($specFn) ? $specFn() : self::undef();

        $dpath = self::slice($state->path, 1);
        $ref = self::getpath($spec, $refpath, (object) [
            'dpath' => $dpath,
            'dparent' => self::getpath($spec, $dpath),
        ]);

        $hasSubRef = false;
        if (self::isnode($ref)) {
            self::walk($ref, function ($_k, $v) use (&$hasSubRef) {
                if ($v === '`$REF`') {
                    $hasSubRef = true;
                }
                return $v;
            });
        }

        $tref = self::cloneWrap($ref);

        $cpath = self::slice($state->path, -3);
        $tpath = self::slice($state->path, -1);
        $tcur = self::getpath($store, $cpath);
        $tval = self::getpath($store, $tpath);
        $rval = self::undef();

        if (!$hasSubRef || self::undef() !== $tval) {
            $tinj = $state->child(0, [self::getelem($tpath, -1)]);

            $tinj->path = $tpath;
            $tinj->nodes = self::slice($state->nodes, -1);
            $tinj->parent = self::getelem($nodes, -2);
            $tinj->val = $tref;

            $tinj->dpath = self::flatten([$cpath]);
            $tinj->dparent = $tcur;

            $injResult = self::inject($tref, $store, $tinj);

            // If inject returned SKIP, use tref (mutated in place) not tinj->val (which may be SKIP)
            if ($injResult === self::SKIP || $tinj->val === self::SKIP) {
                $rval = is_object($tref) ? $tref : self::undef();
            } else {
                $rval = $tinj->val;
            }
        } else {
            $rval = self::undef();
        }

        $grandparent = $state->setval($rval, 2);

        // PHP: arrays in nodes are copies, so ancestor setval on arrays doesn't propagate.
        // Sync the prior injection's parent if it's an array.
        if ($state->prior && is_array($state->prior->parent)) {
            $akey = self::getelem($state->path, -2);
            if (self::undef() === $rval) {
                $state->prior->parent = self::delprop($state->prior->parent, $akey);
            } else {
                self::setprop($state->prior->parent, $akey, $rval);
            }
        }

        if (self::islist($grandparent) && $state->prior) {
            $state->prior->keyI--;
        }

        return $_val;
    }


    private static array $FORMATTER = [];

    private static function _getFormatters(): array
    {
        if (empty(self::$FORMATTER)) {
            self::$FORMATTER = [
                'identity' => fn($_k, $v) => $v,
                'upper' => fn($_k, $v) => self::isnode($v) ? $v : strtoupper('' . $v),
                'lower' => fn($_k, $v) => self::isnode($v) ? $v : strtolower('' . $v),
                'string' => fn($_k, $v) => self::isnode($v) ? $v : ('' . $v),
                'number' => function ($_k, $v) {
                    if (self::isnode($v)) {
                        return $v;
                    }
                    $n = is_numeric($v) ? $v + 0 : 0;
                    return $n;
                },
                'integer' => function ($_k, $v) {
                    if (self::isnode($v)) {
                        return $v;
                    }
                    $n = is_numeric($v) ? (int)$v : 0;
                    return $n;
                },
                'concat' => function ($k, $v) {
                    if (null === $k && self::islist($v)) {
                        $parts = self::items($v, fn($n) => self::isnode($n[1]) ? '' : ('' . $n[1]));
                        return self::join($parts, '');
                    }
                    return $v;
                },
            ];
        }
        return self::$FORMATTER;
    }


    /** @internal */
    public static function transform_FORMAT(object $inj, mixed $_val, string $_ref, mixed $store): mixed
    {
        // Remove remaining keys to avoid spurious processing.
        self::slice($inj->keys, 0, 1, true);

        if (self::M_VAL !== $inj->mode) {
            return self::undef();
        }

        // Get arguments: ['`$FORMAT`', 'name', child].
        $name = self::_getprop($inj->parent, 1);
        $child = self::_getprop($inj->parent, 2);

        // Source data.
        $tkey = self::getelem($inj->path, -2);
        $target = self::getelem($inj->nodes, -2, fn() => self::getelem($inj->nodes, -1));

        $cinj = self::injectChild($child, $store, $inj);
        $resolved = $cinj->val;

        $formatters = self::_getFormatters();
        $formatter = (0 < (self::T_function & self::typify($name))) ? $name : ($formatters[$name] ?? self::undef());

        if (self::undef() === $formatter) {
            $inj->errs[] = '$FORMAT: unknown format: ' . $name . '.';
            return self::undef();
        }

        $out = self::walk($resolved, $formatter);

        self::setprop($target, $tkey, $out);

        return $out;
    }


    /** @internal */
    public static function transform_APPLY(object $inj, mixed $_val, string $_ref, mixed $store): mixed
    {
        $ijname = 'APPLY';

        if (!self::checkPlacement(self::M_VAL, $ijname, self::T_list, $inj)) {
            return self::undef();
        }

        $args = self::slice($inj->parent, 1);
        $argsList = [];
        if (self::islist($args)) {
            if ($args instanceof ListRef) {
                $argsList = $args->list;
            } else {
                $argsList = $args;
            }
        }
        [$err, $apply, $child] = self::injectorArgs([self::T_function, self::T_any], $argsList);
        if (self::undef() !== $err) {
            $inj->errs[] = '$' . $ijname . ': ' . $err;
            return self::undef();
        }

        $tkey = self::getelem($inj->path, -2);
        $target = self::getelem($inj->nodes, -2, fn() => self::getelem($inj->nodes, -1));

        $cinj = self::injectChild($child, $store, $inj);
        $resolved = $cinj->val;

        $out = call_user_func($apply, $resolved, $store, $cinj);

        self::setprop($target, $tkey, $out);

        return $out;
    }


    /**
     * Transform data using a spec.
     *
     * @param mixed $data   Source data (not mutated)
     * @param mixed $spec   Transform spec (JSON-like)
     * @param array<mixed>|object|null $extra   extra transforms or data
     * @param callable|null $modify  optional per-value hook
     */
    public static function transform(
        mixed $data,
        mixed $spec,
        mixed $injdef = null
    ): mixed {
        // Support injdef object pattern or backward compat (extra data passed directly)
        $extra = null;
        $modify = null;
        $errs = null;
        if (is_object($injdef) && (
            property_exists($injdef, 'extra') ||
            property_exists($injdef, 'modify') ||
            property_exists($injdef, 'errs') ||
            property_exists($injdef, 'meta') ||
            property_exists($injdef, 'handler')
        )) {
            // New injdef pattern: { extra, modify, errs, meta, handler }
            $extra = property_exists($injdef, 'extra') ? $injdef->extra : null;
            $modify = property_exists($injdef, 'modify') ? $injdef->modify : null;
            $errs = property_exists($injdef, 'errs') ? $injdef->errs : null;
        } else {
            // Backward compat: treat 3rd arg as extra data/store directly
            $extra = $injdef;
        }

        // 1) clone spec, wrapping arrays in ListRef for reference stability (Go pattern)
        $specClone = self::cloneWrap($spec);

        // 2) split extra into data vs transforms
        $extraTransforms = [];
        $extraData = [];

        foreach ((array) ($extra ?? []) as $k => $v) {
            if (str_starts_with((string) $k, self::S_DS)) {
                $extraTransforms[$k] = $v;
            } else {
                $extraData[$k] = $v;
            }
        }

        // 3) build the combined store
        $dataClone = self::merge([
            self::cloneWrap($extraData),
            self::cloneWrap($data),
        ]);

        $store = (object) array_merge(
            [
                self::S_DTOP => $dataClone,
                '$BT' => fn() => self::S_BT,
                '$DS' => fn() => self::S_DS,
                '$WHEN' => fn() => (new \DateTime)->format(\DateTime::ATOM),
                '$DELETE' => [self::class, 'transform_DELETE'],
                '$COPY' => [self::class, 'transform_COPY'],
                '$KEY' => [self::class, 'transform_KEY'],
                '$META' => [self::class, 'transform_META'],
                '$ANNO' => [self::class, 'transform_ANNO'],
                '$MERGE' => [self::class, 'transform_MERGE'],
                '$EACH' => [self::class, 'transform_EACH'],
                '$PACK' => [self::class, 'transform_PACK'],
                '$SPEC' => fn() => $spec,
                '$REF' => [self::class, 'transform_REF'],
                '$FORMAT' => [self::class, 'transform_FORMAT'],
                '$APPLY' => [self::class, 'transform_APPLY'],
            ],
            $extraTransforms
        );

        // 4) run inject to do the transform
        $injectOpts = new \stdClass();
        if ($modify !== null) {
            $injectOpts->modify = $modify;
        }
        if (is_object($injdef) && property_exists($injdef, 'handler') && $injdef->handler !== null) {
            $injectOpts->handler = $injdef->handler;
        }
        if (is_object($injdef) && property_exists($injdef, 'meta') && $injdef->meta !== null) {
            $injectOpts->meta = $injdef->meta;
        }
        if (is_object($injdef) && property_exists($injdef, 'errs') && $injdef->errs !== null) {
            $injectOpts->errs = $injdef->errs;
        }
        $result = self::inject($specClone, $store, $injectOpts);

        // When a child transform (e.g. $REF) deletes the key, inject returns SKIP; return mutated spec
        if ($result === self::SKIP) {
            return self::_stdClassToArray(self::cloneUnwrap($specClone));
        }

        // Return maps as PHP associative arrays (the native map type) so callers
        // can use is_array()/array access directly. Internal processing may use
        // stdClass; the conversion here happens only at the public boundary.
        return self::_stdClassToArray(self::cloneUnwrap($result));
    }


    // Deeply convert stdClass map nodes to associative arrays, leaving lists
    // (sequential arrays) and scalar values untouched. Used at the transform()
    // public boundary so consumers receive PHP-idiomatic arrays.
    private static function _stdClassToArray(mixed $val, int $depth = 0): mixed
    {
        if ($depth > 64) {
            return $val;
        }
        if ($val instanceof \stdClass) {
            $out = [];
            foreach (get_object_vars($val) as $k => $v) {
                $out[$k] = self::_stdClassToArray($v, $depth + 1);
            }
            return $out;
        }
        if (is_array($val)) {
            $out = [];
            foreach ($val as $k => $v) {
                $out[$k] = self::_stdClassToArray($v, $depth + 1);
            }
            return $out;
        }
        return $val;
    }

    /**
     * Remove unresolved $REF list entries from a list spec.
     * This handles PHP's value-type arrays where in-place mutation via references doesn't propagate.
     */
    private static function _cleanRefEntries(array $list): array {
        $cleaned = [];
        foreach ($list as $item) {
            if (self::islist($item) && count($item) >= 1 && self::_getprop($item, 0) === '`$REF`') {
                // This is an unresolved $REF entry - remove it
                continue;
            }
            if (self::islist($item)) {
                $item = self::_cleanRefEntries($item);
            }
            $cleaned[] = $item;
        }
        return $cleaned;
    }

    /** @internal */
    private static function _invalidTypeMsg(array $path, string $needtype, int $vt, mixed $v): string
    {
        $missing = ($v === null || $v === self::undef());
        $vs = $missing ? 'no value' : self::stringify($v);
        return 'Expected ' .
            (1 < self::size($path) ? ('field ' . self::pathify($path, 1) . ' to be ') : '') .
            $needtype . ', but found ' .
            ($missing ? '' : self::typename($vt) . ': ') . $vs . '.';
    }

    /* =======================
     * Validation Functions
     * =======================

    /**
     * A required string value.
     */
    public static function validate_STRING(object $inj): mixed
    {
        $out = self::_getprop($inj->dparent, $inj->key);

        $t = self::typify($out);
        if (0 === (self::T_string & $t)) {
            $msg = self::_invalidTypeMsg($inj->path, self::S_string, $t, $out);
            $inj->errs[] = $msg;
            return self::undef();
        }

        if (self::S_MT === $out) {
            $msg = 'Empty string at ' . self::pathify($inj->path, 1);
            $inj->errs[] = $msg;
            return self::undef();
        }

        return $out;
    }

    /**
     * A required number value (int or float).
     */
    public static function validate_NUMBER(object $inj): mixed
    {
        $out = self::_getprop($inj->dparent, $inj->key);

        $t = self::typify($out);
        if (0 === (self::T_number & $t)) {
            $inj->errs[] = self::_invalidTypeMsg($inj->path, self::S_number, $t, $out);
            return self::undef();
        }

        return $out;
    }

    /**
     * A required boolean value.
     */
    public static function validate_BOOLEAN(object $inj): mixed
    {
        $out = self::_getprop($inj->dparent, $inj->key);

        $t = self::typify($out);
        if (0 === (self::T_boolean & $t)) {
            $inj->errs[] = self::_invalidTypeMsg($inj->path, self::S_boolean, $t, $out);
            return self::undef();
        }

        return $out;
    }

    /**
     * A required object (map) value (contents not validated).
     */
    public static function validate_OBJECT(object $inj): mixed
    {
        $out = self::_getprop($inj->dparent, $inj->key);

        $t = self::typify($out);
        if (0 === (self::T_map & $t)) {
            $inj->errs[] = self::_invalidTypeMsg($inj->path, self::S_object, $t, $out);
            return self::undef();
        }

        return $out;
    }

    /**
     * A required array (list) value (contents not validated).
     */
    public static function validate_ARRAY(object $inj): mixed
    {
        $out = self::_getprop($inj->dparent, $inj->key);

        $t = self::typify($out);
        if (0 === (self::T_list & $t)) {
            $inj->errs[] = self::_invalidTypeMsg($inj->path, 'list', $t, $out);
            return self::undef();
        }

        return $out;
    }

    /**
     * A required function value.
     */
    public static function validate_FUNCTION(object $inj): mixed
    {
        $out = self::_getprop($inj->dparent, $inj->key);

        $t = self::typify($out);
        if (0 === (self::T_function & $t)) {
            $inj->errs[] = self::_invalidTypeMsg($inj->path, self::S_function, $t, $out);
            return self::undef();
        }

        return $out;
    }

    /**
     * Generic type validator. Validates against any type name via TYPENAME lookup.
     */
    public static function validate_TYPE(object $inj, mixed $_val = null, ?string $ref = null): mixed
    {
        $tname = strtolower(substr($ref ?? '', 1));
        $idx = array_search($tname, self::TYPENAME);
        $typev = ($idx !== false) ? (1 << (31 - $idx)) : 0;
        $out = self::_getprop($inj->dparent, $inj->key);

        $t = self::typify($out);
        if (0 === ($t & $typev)) {
            $inj->errs[] = self::_invalidTypeMsg($inj->path, $tname, $t, $out);
            return self::undef();
        }

        return $out;
    }

    /**
     * Allow any value.
     */
    public static function validate_ANY(object $inj): mixed
    {
        $out = self::_getprop($inj->dparent, $inj->key);
        return $out;
    }

    /**
     * Specify child values for map or list.
     * Map syntax: {'`$CHILD`': child-template }
     * List syntax: ['`$CHILD`', child-template ]
     */
    public static function validate_CHILD(object $inj): mixed
    {
        $mode = $inj->mode;
        $key = $inj->key;
        $parent = $inj->parent;
        $keys = $inj->keys ?? [];
        $path = $inj->path;

        // Map syntax.
        if (self::M_KEYPRE === $mode) {
            $childtm = self::_getprop($parent, $key);

            // Get corresponding current object.
            $pkey = self::_getprop($path, count($path) - 2);
            $tval = self::_getprop($inj->dparent, $pkey);

            if (self::undef() == $tval) {
                $tval = new \stdClass();
            } elseif (!self::ismap($tval)) {
                $inj->errs[] = self::_invalidTypeMsg(
                    self::slice($inj->path, 0, -1), self::S_object, self::typify($tval), $tval);
                return self::undef();

            }

            $ckeys = self::keysof($tval);
            foreach ($ckeys as $ckey) {
                self::setprop($parent, $ckey, self::clone($childtm));
                // NOTE: modifying inj! This extends the child value loop in inject.
                $keys[] = $ckey;
            }
            $inj->keys = $keys;

            // Remove $CHILD to cleanup output.
            $inj->setval(self::undef());
            return self::undef();
        }

        // List syntax.
        if (self::M_VAL === $mode) {
            if (!self::islist($parent)) {
                // $CHILD was not inside a list.
                $inj->errs[] = 'Invalid $CHILD as value';
                return self::undef();
            }

            $childtm = self::_getprop($parent, 1);

            if (self::undef() === $inj->dparent) {
                // Empty list as default.
                while (count($parent) > 0) {
                    array_pop($parent);
                }
                return self::undef();
            }

            if (!self::islist($inj->dparent)) {
                $msg = self::_invalidTypeMsg(
                    self::slice($inj->path, 0, -1), self::S_array, self::typify($inj->dparent), $inj->dparent);
                $inj->errs[] = $msg;
                $inj->keyI = count($parent);
                return $inj->dparent;
            }

            // Clone children and reset inj key index.
            foreach ($inj->dparent as $i => $n) {
                $parent[$i] = self::clone($childtm);
            }
            // Adjust array length
            while (count($parent) > count($inj->dparent)) {
                array_pop($parent);
            }
            $inj->keyI = 0;
            $out = self::_getprop($inj->dparent, 0);
            return $out;
        }

        return self::undef();
    }

    /**
     * Match at least one of the specified shapes.
     * Syntax: ['`$ONE`', alt0, alt1, ...]
     */
    public static function validate_ONE(
        object $inj,
        mixed $_val,
        string $_ref,
        mixed $store
    ): mixed {
        $mode = $inj->mode;
        $parent = $inj->parent;
        $keyI = $inj->keyI;

        // Only operate in val mode, since parent is a list.
        if (self::M_VAL === $mode) {
            if (!self::islist($parent) || 0 !== $keyI) {
                $inj->errs[] = 'The $ONE validator at field ' .
                    self::pathify($inj->path, 1, 1) .
                    ' must be the first element of an array.';
                return self::undef();
            }

            $inj->keyI = count($inj->keys ?? []);

            // Clean up structure, replacing [$ONE, ...] with current
            $inj->setval($inj->dparent, 2);

            $inj->path = self::slice($inj->path, 0, -1);
            $inj->key = self::getelem($inj->path, -1);

            $tvals = self::slice($parent, 1);
            if (0 === count($tvals)) {
                $inj->errs[] = 'The $ONE validator at field ' .
                    self::pathify($inj->path, 1, 1) .
                    ' must have at least one argument.';
                return self::undef();
            }

            // See if we can find a match.
            foreach ($tvals as $tval) {
                // If match, then errs.length = 0
                $terrs = [];

                $vstore = array_merge((array) $store, [self::S_DTOP => $inj->dparent]);

                $vcurrent = self::validate($inj->dparent, $tval, (object) [
                    'extra' => $vstore,
                    'errs' => $terrs,
                    'meta' => $inj->meta,
                ]);

                $inj->setval($vcurrent, 2);

                // Accept current value if there was a match
                if (0 === count($terrs)) {
                    return self::undef();
                }
            }

            // There was no match.
            $tvArr = ($tvals instanceof ListRef) ? $tvals->list : (is_array($tvals) ? $tvals : []);
            $valdesc = implode(', ', array_map(fn($v) => self::stringify($v), $tvArr));
            $valdesc = preg_replace(self::R_TRANSFORM_NAME, '$1', strtolower($valdesc));

            $inj->errs[] = self::_invalidTypeMsg(
                $inj->path,
                (1 < count($tvals) ? 'one of ' : '') . $valdesc,
                self::typify($inj->dparent), $inj->dparent);
        }

        return self::undef();
    }

    /**
     * Match exactly one of the specified values.
     */
    public static function validate_EXACT(object $inj): mixed
    {
        $mode = $inj->mode;
        $parent = $inj->parent;
        $key = $inj->key;
        $keyI = $inj->keyI;

        // Only operate in val mode, since parent is a list.
        if (self::M_VAL === $mode) {
            if (!self::islist($parent) || 0 !== $keyI) {
                $inj->errs[] = 'The $EXACT validator at field ' .
                    self::pathify($inj->path, 1, 1) .
                    ' must be the first element of an array.';
                return self::undef();
            }

            $inj->keyI = count($inj->keys ?? []);

            // Clean up structure, replacing [$EXACT, ...] with current data parent
            $inj->setval($inj->dparent, 2);

            $inj->path = self::slice($inj->path, 0, count($inj->path) - 1);
            $inj->key = self::getelem($inj->path, -1);

            $tvals = self::slice($parent, 1);
            if (0 === count($tvals)) {
                $inj->errs[] = 'The $EXACT validator at field ' .
                    self::pathify($inj->path, 1, 1) .
                    ' must have at least one argument.';
                return self::undef();
            }

            // See if we can find an exact value match.
            $currentstr = null;
            foreach ($tvals as $tval) {
                $exactmatch = $tval === $inj->dparent;

                if (!$exactmatch && self::isnode($tval)) {
                    $currentstr = $currentstr ?? self::stringify($inj->dparent);
                    $tvalstr = self::stringify($tval);
                    $exactmatch = $tvalstr === $currentstr;
                }

                if ($exactmatch) {
                    return self::undef();
                }
            }

            $tvArr = ($tvals instanceof ListRef) ? $tvals->list : (is_array($tvals) ? $tvals : []);
            $valdesc = implode(', ', array_map(fn($v) => self::stringify($v), $tvArr));
            $valdesc = preg_replace(self::R_TRANSFORM_NAME, '$1', strtolower($valdesc));

            $inj->errs[] = self::_invalidTypeMsg(
                $inj->path,
                (1 < count($inj->path) ? '' : 'value ') .
                'exactly equal to ' . (1 === count($tvals) ? '' : 'one of ') . $valdesc,
                self::typify($inj->dparent), $inj->dparent);
        } else {
            self::delprop($parent, $key);
        }

        return self::undef();
    }

    /**
     * This is the "modify" argument to inject. Use this to perform
     * generic validation. Runs *after* any special commands.
     */
    private static function _validation(
        mixed $pval,
        mixed $key = null,
        mixed $parent = null,
        ?object $inj = null,
        mixed $store = null
    ): void {
        if (self::undef() === $inj) {
            return;
        }

        if ($pval === self::SKIP) {
            return;
        }

        // select needs exact matches
        $exact = self::_getprop($inj->meta, '`$EXACT`', false);

        // Current val to verify.
        $cval = self::_getprop($inj->dparent, $key);

        if (self::undef() === $inj || (!$exact && self::undef() === $cval)) {
            return;
        }

        $ptype = self::typify($pval);

        // Delete any special commands remaining.
        if (0 < (self::T_string & $ptype) && str_contains($pval, self::S_DS)) {
            return;
        }

        $ctype = self::typify($cval);

        // PHP empty [] is ambiguous (list vs map). When the spec expects a
        // map, treat an empty array/ListRef in the data as an empty map so
        // that validation does not produce a spurious type-mismatch error.
        // Go/Lua don't hit this because they have distinct map/list types.
        if (0 < (self::T_map & $ptype) &&
            (is_array($cval) || $cval instanceof \Voxgig\Struct\ListRef) &&
            0 === count($cval)) {
            $cval = new \stdClass();
            $ctype = self::typify($cval);
        }

        // Type mismatch.
        if ($ptype !== $ctype && self::undef() !== $pval) {
            $inj->errs[] = self::_invalidTypeMsg($inj->path, self::typename($ptype), $ctype, $cval);
            return;
        }

        if (self::ismap($cval)) {
            if (!self::ismap($pval)) {
                $inj->errs[] = self::_invalidTypeMsg($inj->path, self::typename($ptype), $ctype, $cval);
                return;
            }

            $ckeys = self::keysof($cval);
            $pkeys = self::keysof($pval);

            // Empty spec object {} means object can be open (any keys).
            if (0 < count($pkeys) && true !== self::_getprop($pval, '`$OPEN`')) {
                $badkeys = [];
                foreach ($ckeys as $ckey) {
                    if (!self::haskey($pval, $ckey)) {
                        $badkeys[] = $ckey;
                    }
                }

                // Closed object, so reject extra keys not in shape.
                if (0 < count($badkeys)) {
                    $msg = 'Unexpected keys at field ' . self::pathify($inj->path, 1) . ': ' . implode(', ', $badkeys);
                    $inj->errs[] = $msg;
                }
            } else {
                // Object is open, so merge in extra keys.
                self::merge([$pval, $cval]);
                if (self::isnode($pval)) {
                    self::delprop($pval, '`$OPEN`');
                }
            }
        } elseif (self::islist($cval)) {
            if (!self::islist($pval)) {
                $inj->errs[] = self::_invalidTypeMsg($inj->path, self::typename($ptype), $ctype, $cval);
            }
        } elseif ($exact) {
            if ($cval !== $pval) {
                $pathmsg = 1 < self::size($inj->path) ? 'at field ' . self::pathify($inj->path, 1) . ': ' : '';
                $inj->errs[] = 'Value ' . $pathmsg . $cval . ' should equal ' . $pval . '.';
            }
        } else {
            // Spec value was a default, copy over data
            self::setprop($parent, $key, $cval);
        }
    }

    /**
     * Validation handler for injection.
     */
    private static function _validatehandler(
        object $inj,
        mixed $val,
        string $ref,
        mixed $store
    ): mixed {
        $out = $val;

        $m = preg_match(self::R_META_PATH, $ref, $matches);
        $ismetapath = null != $m;

        if ($ismetapath) {
            if ('=' === $matches[2]) {
                $inj->setval(['`$EXACT`', $val]);
            } else {
                $inj->setval($val);
            }
            $inj->keyI = -1;

            $out = self::SKIP;
        } else {
            $out = self::_injecthandler($inj, $val, $ref, $store);
        }

        return $out;
    }

    /**
     * Validate a data structure against a shape specification.
     * The shape specification follows the "by example" principle.
     * 
     * @param mixed $data Source data to validate
     * @param mixed $spec Validation specification
     * @param mixed $injdef Optional injection definition with extra validators, etc.
     * @return mixed Validated data
     */
    public static function validate(mixed $data, mixed $spec, mixed $injdef = null): mixed
    {
        $extra = is_object($injdef) && property_exists($injdef, 'extra') ? $injdef->extra : null;

        $collect = null != $injdef && property_exists($injdef, 'errs');

        // PHP arrays are value-copied, so a plain array on $injdef->errs would be
        // detached from $inj->errs deep inside inject. Wrap in ArrayObject so the
        // same storage is shared through the whole transform/inject chain.
        $errs = (is_object($injdef) && property_exists($injdef, 'errs')) ? $injdef->errs : [];
        if (is_array($errs)) {
            $errs = new \ArrayObject($errs);
        }
        if ($collect) {
            $injdef->errs = $errs;
        }

        $store = array_merge([
            // Remove the transform commands.
            '$DELETE' => null,
            '$COPY' => null,
            '$KEY' => null,
            '$META' => null,
            '$MERGE' => null,
            '$EACH' => null,
            '$PACK' => null,

            '$STRING' => [self::class, 'validate_STRING'],
            '$NUMBER' => [self::class, 'validate_TYPE'],
            '$INTEGER' => [self::class, 'validate_TYPE'],
            '$DECIMAL' => [self::class, 'validate_TYPE'],
            '$BOOLEAN' => [self::class, 'validate_TYPE'],
            '$NULL' => [self::class, 'validate_TYPE'],
            '$NIL' => [self::class, 'validate_TYPE'],
            '$MAP' => [self::class, 'validate_TYPE'],
            '$LIST' => [self::class, 'validate_TYPE'],
            '$FUNCTION' => [self::class, 'validate_TYPE'],
            '$INSTANCE' => [self::class, 'validate_TYPE'],
            '$ANY' => [self::class, 'validate_ANY'],
            '$CHILD' => [self::class, 'validate_CHILD'],
            '$ONE' => [self::class, 'validate_ONE'],
            '$EXACT' => [self::class, 'validate_EXACT'],

            // A special top level value to collect errors.
            '$ERRS' => $errs,
        ], (array) ($extra ?? []));

        $meta = is_object($injdef) && property_exists($injdef, 'meta') ? $injdef->meta : null;

        $transformOpts = new \stdClass();
        $transformOpts->extra = $store;
        $transformOpts->modify = [self::class, '_validation'];
        $transformOpts->handler = [self::class, '_validatehandler'];
        if ($meta !== null) {
            $transformOpts->meta = $meta;
        }
        $transformOpts->errs = $errs;
        $out = self::transform($data, $spec, $transformOpts);

        // Unwrap shared ArrayObject back to a plain array on the caller's injdef
        // so count()/foreach work as callers (including select) expect.
        if ($collect && $injdef->errs instanceof \ArrayObject) {
            $injdef->errs = $injdef->errs->getArrayCopy();
        }

        $generr = (0 < count($errs) && !$collect);
        if ($generr) {
            throw new \Exception('Invalid data: ' . implode(' | ', (array) $errs));
        }

        return $out;
    }

    /**
     * Select children from a top-level object that match a MongoDB-style query.
     * Supports $and, $or, and equality comparisons.
     * For arrays, children are elements; for objects, children are values.
     *
     * @param mixed $query The query specification
     * @param mixed $children The object or array to search in
     * @return array Array of matching children
     */
    public static function select(mixed $children, mixed $query): array
    {
        if (!self::isnode($children)) {
            return [];
        }

        if (self::ismap($children)) {
            $children = array_map(function($n) {
                self::setprop($n[1], self::S_DKEY, $n[0]);
                return $n[1];
            }, self::items($children));
        } else {
            $children = array_map(function($n, $i) {
                if (self::ismap($n)) {
                    self::setprop($n, self::S_DKEY, $i);
                }
                return $n;
            }, $children, array_keys($children));
        }

        $results = [];
        $injdef = (object) [
            'errs' => [],
            'meta' => (object) ['`$EXACT`' => true],
            'extra' => [
                '$AND' => [self::class, 'select_AND'],
                '$OR' => [self::class, 'select_OR'],
                '$NOT' => [self::class, 'select_NOT'],
                '$GT' => [self::class, 'select_CMP'],
                '$LT' => [self::class, 'select_CMP'],
                '$GTE' => [self::class, 'select_CMP'],
                '$LTE' => [self::class, 'select_CMP'],
                '$LIKE' => [self::class, 'select_CMP'],
            ]
        ];

        $q = self::clone($query);
        $q = self::_select_add_open($q);

        foreach ($children as $child) {
            $injdef->errs = [];
            self::validate($child, self::clone($q), $injdef);

            if (count($injdef->errs) === 0) {
                $results[] = $child;
            }
        }

        return $results;
    }

    // Recursively add `$OPEN` to all maps in a query for select.
    // PHP arrays are value types, so walk can't modify in-place.
    private static function _select_add_open(mixed $val): mixed
    {
        if (self::ismap($val)) {
            if (is_array($val)) {
                if (!array_key_exists('`$OPEN`', $val)) {
                    $val['`$OPEN`'] = true;
                }
                foreach ($val as $k => $v) {
                    $val[$k] = self::_select_add_open($v);
                }
            } elseif ($val instanceof \stdClass) {
                if (!property_exists($val, '`$OPEN`')) {
                    $val->{'`$OPEN`'} = true;
                }
                foreach (get_object_vars($val) as $k => $v) {
                    $val->$k = self::_select_add_open($v);
                }
            }
        } elseif (self::islist($val) && is_array($val)) {
            foreach ($val as $i => $v) {
                $val[$i] = self::_select_add_open($v);
            }
        }
        return $val;
    }

    /**
     * Helper method for $AND operator in select queries
     */
    private static function select_AND(object $state, mixed $_val, mixed $_ref, mixed $store): mixed
    {
        if (self::M_KEYPRE === $state->mode) {
            $terms = self::_getprop($state->parent, $state->key);

            $ppath = self::slice($state->path, -1);
            $point = self::getpath($store, $ppath);

            $vstore = self::merge([(object) [], $store], 1);
            $vstore->{'$TOP'} = $point;

            foreach ($terms as $term) {
                $terrs = [];
                self::validate($point, $term, (object) [
                    'extra' => $vstore,
                    'errs' => $terrs,
                    'meta' => $state->meta,
                ]);

                if (count($terrs) !== 0) {
                    $state->errs[] = 'AND:' . self::pathify($ppath) . ': ' . self::stringify($point) . ' fail:' . self::stringify($terms);
                }
            }

            $gkey = self::getelem($state->path, -2);
            $gp = self::getelem($state->nodes, -2);
            self::setprop($gp, $gkey, $point);
        }
        return null;
    }

    /**
     * Helper method for $OR operator in select queries
     */
    private static function select_OR(object $state, mixed $_val, mixed $_ref, mixed $store): mixed
    {
        if (self::M_KEYPRE === $state->mode) {
            $terms = self::_getprop($state->parent, $state->key);

            $ppath = self::slice($state->path, -1);
            $point = self::getpath($store, $ppath);

            $vstore = self::merge([(object) [], $store], 1);
            $vstore->{'$TOP'} = $point;

            foreach ($terms as $term) {
                $terrs = [];
                self::validate($point, $term, (object) [
                    'extra' => $vstore,
                    'errs' => $terrs,
                    'meta' => $state->meta,
                ]);

                if (count($terrs) === 0) {
                    $gkey = self::getelem($state->path, -2);
                    $gp = self::getelem($state->nodes, -2);
                    self::setprop($gp, $gkey, $point);

                    return null;
                }
            }

            $state->errs[] = 'OR:' . self::pathify($ppath) . ': ' . self::stringify($point) . ' fail:' . self::stringify($terms);
        }
        return null;
    }

    /**
     * Helper method for $NOT operator in select queries
     */
    private static function select_NOT(object $state, mixed $_val, mixed $_ref, mixed $store): mixed
    {
        if (self::M_KEYPRE === $state->mode) {
            $term = self::_getprop($state->parent, $state->key);

            $ppath = self::slice($state->path, -1);
            $point = self::getpath($store, $ppath);

            $vstore = self::merge([(object) [], $store], 1);
            $vstore->{'$TOP'} = $point;

            $terrs = [];
            self::validate($point, $term, (object) [
                'extra' => $vstore,
                'errs' => $terrs,
                'meta' => $state->meta,
            ]);

            if (count($terrs) === 0) {
                $state->errs[] = 'NOT:' . self::pathify($ppath) . ': ' . self::stringify($point) . ' fail:' . self::stringify($term);
            }

            $gkey = self::getelem($state->path, -2);
            $gp = self::getelem($state->nodes, -2);
            self::setprop($gp, $gkey, $point);
        }
        return null;
    }

    /**
     * Helper method for comparison operators in select queries
     */
    private static function select_CMP(object $state, mixed $_val, mixed $ref, mixed $store): mixed
    {
        if (self::M_KEYPRE === $state->mode) {
            $term = self::_getprop($state->parent, $state->key);
            $gkey = self::getelem($state->path, -2);

            $ppath = self::slice($state->path, -1);
            $point = self::getpath($store, $ppath);

            $pass = false;

            if ('$GT' === $ref && $point > $term) {
                $pass = true;
            }
            elseif ('$LT' === $ref && $point < $term) {
                $pass = true;
            }
            elseif ('$GTE' === $ref && $point >= $term) {
                $pass = true;
            }
            elseif ('$LTE' === $ref && $point <= $term) {
                $pass = true;
            }
            elseif ('$LIKE' === $ref && preg_match('/' . $term . '/', self::stringify($point))) {
                $pass = true;
            }

            if ($pass) {
                // Update spec to match found value so that _validate does not complain
                $gp = self::getelem($state->nodes, -2);
                self::setprop($gp, $gkey, $point);
            }
            else {
                $state->errs[] = 'CMP: ' . self::pathify($ppath) . ': ' . self::stringify($point) .
                    ' fail:' . $ref . ' ' . self::stringify($term);
            }
        }
        return null;
    }

    /**
     * Get element from array by index, supporting negative indices
     * The key should be an integer, or a string that can parse to an integer only.
     * Negative integers count from the end of the list.
     */
    public static function getelem(mixed $val, mixed $key, mixed $alt = null): mixed
    {
        $altIsDefault = (func_num_args() < 3);
        $out = self::undef();

        if ($val === null || $val === self::undef() || $key === null || $key === self::undef()) {
            return $altIsDefault ? null : (is_callable($alt) ? $alt() : $alt);
        }

        if (self::islist($val)) {
            $listArr = ($val instanceof ListRef) ? $val->list : $val;
            $listLen = count($listArr);
            if (is_string($key)) {
                if (!preg_match('/^[-0-9]+$/', $key)) {
                    $out = self::undef();
                } else {
                    $nkey = (int) $key;
                    if ($nkey < 0) {
                        $nkey = $listLen + $nkey;
                    }
                    $out = ($nkey >= 0 && $nkey < $listLen) ? $listArr[$nkey] : self::undef();
                }
            } elseif (is_int($key)) {
                $nkey = $key;
                if ($nkey < 0) {
                    $nkey = $listLen + $nkey;
                }
                $out = ($nkey >= 0 && $nkey < $listLen) ? $listArr[$nkey] : self::undef();
            }
        }

        if ($out === self::undef()) {
            if ($altIsDefault) {
                return null;
            }
            return is_callable($alt) ? $alt() : $alt;
        }

        return $out;
    }

    /**
     * Safely delete a property from an object or array element.
     * Undefined arguments and invalid keys are ignored.
     * Returns the (possibly modified) parent.
     * For objects, the property is deleted using unset.
     * For arrays, the element at the index is removed and remaining elements are shifted down.
     */
    public static function delprop(mixed $parent, mixed $key): mixed
    {
        if (!self::iskey($key)) {
            return $parent;
        }

        if ($parent instanceof ListRef) {
            $keyI = (int)$key;
            if (!is_numeric($key)) {
                return $parent;
            }
            if ($keyI >= 0 && $keyI < count($parent->list)) {
                array_splice($parent->list, $keyI, 1);
            }
            return $parent;
        }

        if (self::ismap($parent)) {
            $key = self::strkey($key);
            unset($parent->$key);
        }
        elseif (self::islist($parent)) {
            // Ensure key is an integer
            $keyI = (int)$key;
            if (!is_numeric($key) || (string)$keyI !== (string)$key) {
                return $parent;
            }

            // Delete list element at position keyI, shifting later elements down
            if ($keyI >= 0 && $keyI < count($parent)) {
                for ($pI = $keyI; $pI < count($parent) - 1; $pI++) {
                    $parent[$pI] = $parent[$pI + 1];
                }
                array_pop($parent);
            }
        }

        return $parent;
    }


    public static function setpath(
        mixed $store,
        mixed $path,
        mixed $val,
        mixed $injdef = null
    ): mixed {
        $pathType = self::typify($path);

        $parts = (0 < (self::T_list & $pathType)) ? $path :
            ((0 < (self::T_string & $pathType)) ? explode('.', $path) :
                ((0 < (self::T_number & $pathType)) ? [$path] : self::undef()));

        if (self::undef() === $parts) {
            return self::undef();
        }

        $base = self::_getprop($injdef, self::S_BASE);
        $numparts = self::size($parts);
        $parent = self::_getprop($store, $base, $store);

        for ($pI = 0; $pI < $numparts - 1; $pI++) {
            $partKey = self::getelem($parts, $pI);
            $nextParent = self::_getprop($parent, $partKey);
            if (!self::isnode($nextParent)) {
                $nextParent = (0 < (self::T_number & self::typify(self::getelem($parts, $pI + 1))))
                    ? [] : new \stdClass();
                self::setprop($parent, $partKey, $nextParent);
            }
            $parent = $nextParent;
        }

        if ($val === self::DELETE) {
            self::delprop($parent, self::getelem($parts, -1));
        } else {
            self::setprop($parent, self::getelem($parts, -1), $val);
        }

        return $parent;
    }


    public static function checkPlacement(
        int $modes,
        string $ijname,
        int $parentTypes,
        object $inj
    ): bool {
        if (0 === ($modes & $inj->mode)) {
            $modeItems = array_filter(
                [self::M_KEYPRE, self::M_KEYPOST, self::M_VAL],
                fn($m) => $modes & $m
            );
            $placementNames = array_map(fn($m) => self::PLACEMENT[$m] ?? '', $modeItems);
            $inj->errs[] = '$' . $ijname . ': invalid placement as ' . (self::PLACEMENT[$inj->mode] ?? '') .
                ', expected: ' . implode(',', $placementNames) . '.';
            return false;
        }
        if (!self::isempty($parentTypes)) {
            $ptype = self::typify($inj->parent);
            if (0 === ($parentTypes & $ptype)) {
                $inj->errs[] = '$' . $ijname . ': invalid placement in parent ' . self::typename($ptype) .
                    ', expected: ' . self::typename($parentTypes) . '.';
                return false;
            }
        }
        return true;
    }


    public static function injectorArgs(array $argTypes, array $args): array
    {
        $numargs = self::size($argTypes);
        $found = array_fill(0, 1 + $numargs, self::undef());
        $found[0] = self::undef();
        for ($argI = 0; $argI < $numargs; $argI++) {
            $arg = $args[$argI] ?? self::undef();
            $argType = self::typify($arg);
            if (0 === ($argTypes[$argI] & $argType)) {
                $found[0] = 'invalid argument: ' . self::stringify($arg, 22) .
                    ' (' . self::typename($argType) . ' at position ' . (1 + $argI) .
                    ') is not of type: ' . self::typename($argTypes[$argI]) . '.';
                break;
            }
            $found[1 + $argI] = $arg;
        }
        return $found;
    }


    public static function injectChild(mixed $child, mixed $store, object $inj): object
    {
        $cinj = $inj;

        // Replace ['`$FORMAT`',...] with child
        if (null !== $inj->prior) {
            if (null !== $inj->prior->prior) {
                $cinj = $inj->prior->prior->child($inj->prior->keyI, $inj->prior->keys);
                $cinj->val = $child;
                self::setprop($cinj->parent, $inj->prior->key, $child);
            }
            else {
                $cinj = $inj->prior->child($inj->keyI, $inj->keys);
                $cinj->val = $child;
                self::setprop($cinj->parent, $inj->key, $child);
            }
        }

        self::inject($child, $store, $cinj);

        return $cinj;
    }

}


class Injection
{

    public int $mode;
    public bool $full;
    public int $keyI;
    public array $keys;
    public string $key;
    public mixed $val;
    public mixed $parent;
    public array $path;
    public array $nodes;
    /** @var callable */
    public mixed $handler;
    // Accepts plain array or ArrayObject. ArrayObject is used by validate/select
    // so that mutations propagate back through the inject/transform call chain.
    public array|\ArrayObject $errs;
    public object $meta;
    public mixed $dparent;
    public array $dpath;
    public string $base;
    /** @var callable|null */
    public mixed $modify;
    public ?Injection $prior;
    public mixed $extra;

    public function __construct(mixed $val, mixed $parent)
    {
        $this->val = $val;
        $this->parent = $parent;
        $this->errs = [];

        $this->dparent = Struct::UNDEF;
        $this->dpath = ['$TOP'];

        $this->mode = Struct::M_VAL;
        $this->full = false;
        $this->keyI = 0;
        $this->keys = ['$TOP'];
        $this->key = '$TOP';
        $this->path = ['$TOP'];
        $this->nodes = [$parent];
        $this->handler = [Struct::class, '_injecthandler'];
        $this->base = '$TOP';
        $this->meta = (object) [];
        $this->modify = null;
        $this->prior = null;
        $this->extra = null;
    }


    public function __toString(): string
    {
        return $this->toString();
    }

    public function toString(?string $prefix = null): string
    {
        return 'INJ' . (null === $prefix ? '' : '/' . $prefix) . ':' .
            Struct::pad(Struct::pathify($this->path, 1)) .
            (Struct::MODENAME[$this->mode] ?? '') . ($this->full ? '/full' : '') . ':' .
            'key=' . $this->keyI . '/' . $this->key . '/' . '[' . implode(',', $this->keys) . ']' .
            '  p=' . Struct::stringify($this->parent, -1, 1) .
            '  m=' . Struct::stringify($this->meta, -1, 1) .
            '  d/' . Struct::pathify($this->dpath, 1) . '=' . Struct::stringify($this->dparent, -1, 1) .
            '  r=' . Struct::stringify(Struct::_getprop($this->nodes[0] ?? null, '$TOP'), -1, 1);
    }


    public function descend(): mixed
    {
        if (!isset($this->meta->__d)) {
            $this->meta->__d = 0;
        }
        $this->meta->__d++;
        $parentkey = Struct::getelem($this->path, -2);

        // Resolve current node in store for local paths.
        if (Struct::UNDEF === $this->dparent) {

            // Even if there's no data, dpath should continue to match path, so that
            // relative paths work properly.
            if (1 < Struct::size($this->dpath)) {
                $this->dpath = Struct::flatten([$this->dpath, $parentkey]);
            }
        }
        else {
            // this->dparent is the containing node of the current store value.
            if (null !== $parentkey && Struct::UNDEF !== $parentkey) {
                $this->dparent = Struct::_getprop($this->dparent, $parentkey);

                $lastpart = Struct::getelem($this->dpath, -1);
                if ($lastpart === '$:' . $parentkey) {
                    $this->dpath = Struct::slice($this->dpath, -1);
                }
                else {
                    $this->dpath = Struct::flatten([$this->dpath, $parentkey]);
                }
            }
        }

        return $this->dparent;
    }


    public function child(int $keyI, array $keys): Injection
    {
        $key = Struct::strkey($keys[$keyI] ?? null);
        $val = $this->val;

        $cinj = new Injection(Struct::_getprop($val, $key), $val);
        $cinj->keyI = $keyI;
        $cinj->keys = $keys;
        $cinj->key = $key;

        $cinj->path = Struct::flatten([Struct::getdef($this->path, []), $key]);
        $cinj->nodes = Struct::flatten([Struct::getdef($this->nodes, []), [$val]]);

        $cinj->mode = $this->mode;
        $cinj->handler = $this->handler;
        $cinj->modify = $this->modify;
        $cinj->base = $this->base;
        $cinj->meta = $this->meta;
        $cinj->errs = &$this->errs;
        $cinj->prior = $this;

        $cinj->dpath = Struct::flatten([$this->dpath]);
        $cinj->dparent = $this->dparent;

        return $cinj;
    }


    public function setval(mixed $val, ?int $ancestor = null): mixed
    {
        $parent = Struct::UNDEF;
        if (null === $ancestor || $ancestor < 2) {
            if (Struct::UNDEF === $val) {
                $this->parent = Struct::delprop($this->parent, $this->key);
                $parent = $this->parent;
            } else {
                $parent = Struct::setprop($this->parent, $this->key, $val);
            }
        }
        else {
            $aval = Struct::getelem($this->nodes, 0 - $ancestor);
            $akey = Struct::getelem($this->path, 0 - $ancestor);
            if (Struct::UNDEF === $val) {
                $parent = Struct::delprop($aval, $akey);
            } else {
                $parent = Struct::setprop($aval, $akey, $val);
            }
        }

        return $parent;
    }
}
?>
