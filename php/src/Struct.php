<?php

namespace Voxgig\Struct;

class Struct {
    // Check if the value is a node (object or array)
    public static function isNode($val): bool {
        return is_array($val) || is_object($val);
    }

    // Check if the value is a map (associative array)
    public static function isMap($val): bool {
        return is_array($val) && array_values($val) !== $val;
    }

    // Check if the value is a list (indexed array)
    public static function isList($val): bool {
        return is_array($val) && array_values($val) === $val;
    }

    // Check if the value is a valid key (string or integer)
    public static function isKey($key): bool {
        return is_string($key) && $key !== "" || is_int($key);
    }

    // Clone a JSON-like data structure
    public static function clone($val) {
        return json_decode(json_encode($val), true);
    }

    // List entries of a map or list as [key, value] pairs
    public static function items($val): array {
        if (self::isMap($val)) {
            return array_map(null, array_keys($val), array_values($val));
        }
        if (self::isList($val)) {
            return array_map(fn($v, $k) => [$k, $v], $val, array_keys($val));
        }
        return [];
    }

    // Safely get a property of a node
    public static function getProp($val, $key, $alt = null) {
        if (!is_string($key) && !is_int($key)) {
            throw new \TypeError("Invalid key type: " . gettype($key));
        }
        return isset($val[$key]) ? $val[$key] : $alt;
    }    

    // Safely set a property in a node
    public static function setProp(&$parent, $key, $val) {
        if (!self::isKey($key)) return;
        
        if (!is_array($parent)) {
            throw new \TypeError("Parent must be an array.");
        }
    
        // Force map behavior if the key is a string
        if (is_string($key) || self::isMap($parent)) {
            if ($val === null) {
                unset($parent[$key]);
            } else {
                $parent[$key] = $val;
            }
        } elseif (self::isList($parent)) {
            $key = (int)$key;
            if ($key < 0) {
                array_unshift($parent, $val);
            } elseif ($key >= count($parent)) {
                $parent[] = $val;
            } else {
                $parent[$key] = $val;
            }
        }
    }    
    

    // Check if a value is empty
    public static function isEmpty($val): bool {
        return $val === null || $val === "" || $val === false || $val === 0 || (is_array($val) && count($val) === 0);
    }

    // Convert a value to a string for printing (not JSON)
    public static function stringify($val, $maxlen = null): string {
        if ($val === false) return "false"; // Ensure "false" is not converted to an empty string
        $json = is_array($val) || is_object($val) ? json_encode($val) : (string)$val;
        if ($json === false) return "";
        $json = str_replace('"', '', $json);
        return $maxlen !== null && strlen($json) > $maxlen ? substr($json, 0, $maxlen - 3) . "..." : $json;
    }    

    // Escape a regular expression
    public static function escre(string $s): string {
        return preg_quote($s, '/');
    }

    // Escape a URL
    public static function escurl(string $s): string {
        return rawurlencode($s);
    }
}

?>
