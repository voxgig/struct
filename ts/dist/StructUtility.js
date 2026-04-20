"use strict";
/* Copyright (c) 2025-2026 Voxgig Ltd. MIT LICENSE. */
Object.defineProperty(exports, "__esModule", { value: true });
exports.MODENAME = exports.M_VAL = exports.M_KEYPOST = exports.M_KEYPRE = exports.T_node = exports.T_scalar = exports.T_instance = exports.T_map = exports.T_list = exports.T_null = exports.T_symbol = exports.T_function = exports.T_string = exports.T_number = exports.T_integer = exports.T_decimal = exports.T_boolean = exports.T_noval = exports.T_any = exports.DELETE = exports.SKIP = exports.StructUtility = void 0;
exports.clone = clone;
exports.delprop = delprop;
exports.escre = escre;
exports.escurl = escurl;
exports.filter = filter;
exports.flatten = flatten;
exports.getdef = getdef;
exports.getelem = getelem;
exports.getpath = getpath;
exports.getprop = getprop;
exports.haskey = haskey;
exports.inject = inject;
exports.isempty = isempty;
exports.isfunc = isfunc;
exports.iskey = iskey;
exports.islist = islist;
exports.ismap = ismap;
exports.isnode = isnode;
exports.items = items;
exports.join = join;
exports.jsonify = jsonify;
exports.keysof = keysof;
exports.merge = merge;
exports.pad = pad;
exports.pathify = pathify;
exports.select = select;
exports.setpath = setpath;
exports.setprop = setprop;
exports.size = size;
exports.slice = slice;
exports.strkey = strkey;
exports.stringify = stringify;
exports.transform = transform;
exports.typify = typify;
exports.typename = typename;
exports.validate = validate;
exports.walk = walk;
exports.jm = jm;
exports.jt = jt;
exports.checkPlacement = checkPlacement;
exports.injectorArgs = injectorArgs;
exports.injectChild = injectChild;
// VERSION: @voxgig/struct 0.0.10
/* Voxgig Struct
 * =============
 *
 * Utility functions to manipulate in-memory JSON-like data
 * structures. These structures assumed to be composed of nested
 * "nodes", where a node is a list or map, and has named or indexed
 * fields.  The general design principle is "by-example". Transform
 * specifications mirror the desired output.  This implementation is
 * designed for porting to multiple language, and to be tolerant of
 * undefined values.
 *
 * Main utilities
 * - getpath: get the value at a key path deep inside an object.
 * - merge: merge multiple nodes, overriding values in earlier nodes.
 * - walk: walk a node tree, applying a function at each node and leaf.
 * - inject: inject values from a data store into a new data structure.
 * - transform: transform a data structure to an example structure.
 * - validate: valiate a data structure against a shape specification.
 *
 * Minor utilities
 * - isnode, islist, ismap, iskey, isfunc: identify value kinds.
 * - isempty: undefined values, or empty nodes.
 * - keysof: sorted list of node keys (ascending).
 * - haskey: true if key value is defined.
 * - clone: create a copy of a JSON-like data structure.
 * - items: list entries of a map or list as [key, value] pairs.
 * - getprop: safely get a property value by key.
 * - setprop: safely set a property value by key.
 * - stringify: human-friendly string version of a value.
 * - escre: escape a regular expresion string.
 * - escurl: escape a url.
 * - join: join parts of a url, merging forward slashes.
 *
 * This set of functions and supporting utilities is designed to work
 * uniformly across many languages, meaning that some code that may be
 * functionally redundant in specific languages is still retained to
 * keep the code human comparable.
 *
 * NOTE: Lists are assumed to be mutable and reference stable.
 *
 * NOTE: In this code JSON nulls are in general *not* considered the
 * same as the undefined value in the given language. However most
 * JSON parsers do use the undefined value to represent JSON
 * null. This is ambiguous as JSON null is a separate value, not an
 * undefined value. You should convert such values to a special value
 * to represent JSON null, if this ambiguity creates issues
 * (thankfully in most APIs, JSON nulls are not used). For example,
 * the unit tests use the string "__NULL__" where necessary.
 *
 */
// String constants are explicitly defined.
// Mode value for inject step (bitfield).
const M_KEYPRE = 1;
exports.M_KEYPRE = M_KEYPRE;
const M_KEYPOST = 2;
exports.M_KEYPOST = M_KEYPOST;
const M_VAL = 4;
exports.M_VAL = M_VAL;
// Special strings.
const S_BKEY = '`$KEY`';
const S_BANNO = '`$ANNO`';
const S_BEXACT = '`$EXACT`';
const S_BVAL = '`$VAL`';
const S_DKEY = '$KEY';
const S_DTOP = '$TOP';
const S_DERRS = '$ERRS';
const S_DSPEC = '$SPEC';
// General strings.
const S_list = 'list';
const S_base = 'base';
const S_boolean = 'boolean';
const S_function = 'function';
const S_symbol = 'symbol';
const S_instance = 'instance';
const S_key = 'key';
const S_any = 'any';
const S_nil = 'nil';
const S_null = 'null';
const S_number = 'number';
const S_object = 'object';
const S_string = 'string';
const S_decimal = 'decimal';
const S_integer = 'integer';
const S_map = 'map';
const S_scalar = 'scalar';
const S_node = 'node';
// Character strings.
const S_BT = '`';
const S_CN = ':';
const S_CS = ']';
const S_DS = '$';
const S_DT = '.';
const S_FS = '/';
const S_KEY = 'KEY';
const S_MT = '';
const S_OS = '[';
const S_SP = ' ';
const S_CM = ',';
const S_VIZ = ': ';
// Types
let t = 31;
const T_any = (1 << t--) - 1;
exports.T_any = T_any;
const T_noval = 1 << t--; // Means property absent, undefined. Also NOT a scalar!
exports.T_noval = T_noval;
const T_boolean = 1 << t--;
exports.T_boolean = T_boolean;
const T_decimal = 1 << t--;
exports.T_decimal = T_decimal;
const T_integer = 1 << t--;
exports.T_integer = T_integer;
const T_number = 1 << t--;
exports.T_number = T_number;
const T_string = 1 << t--;
exports.T_string = T_string;
const T_function = 1 << t--;
exports.T_function = T_function;
const T_symbol = 1 << t--;
exports.T_symbol = T_symbol;
const T_null = 1 << t--; // The actual JSON null value.
exports.T_null = T_null;
t -= 7;
const T_list = 1 << t--;
exports.T_list = T_list;
const T_map = 1 << t--;
exports.T_map = T_map;
const T_instance = 1 << t--;
exports.T_instance = T_instance;
t -= 4;
const T_scalar = 1 << t--;
exports.T_scalar = T_scalar;
const T_node = 1 << t--;
exports.T_node = T_node;
const TYPENAME = [
    S_any,
    S_nil,
    S_boolean,
    S_decimal,
    S_integer,
    S_number,
    S_string,
    S_function,
    S_symbol,
    S_null,
    '', '', '',
    '', '', '', '',
    S_list,
    S_map,
    S_instance,
    '', '', '', '',
    S_scalar,
    S_node,
];
// The standard undefined value for this language.
const NONE = undefined;
// Private markers
const SKIP = { '`$SKIP`': true };
exports.SKIP = SKIP;
const DELETE = { '`$DELETE`': true };
exports.DELETE = DELETE;
// Regular expression constants
const R_INTEGER_KEY = /^[-0-9]+$/; // Match integer keys (including <0).
const R_ESCAPE_REGEXP = /[.*+?^${}()|[\]\\]/g; // Chars that need escaping in regexp.
const R_TRAILING_SLASH = /\/+$/; // Trailing slashes in URLs.
const R_LEADING_TRAILING_SLASH = /([^\/])\/+/; // Multiple slashes in URL middle.
const R_LEADING_SLASH = /^\/+/; // Leading slashes in URLs.
const R_QUOTES = /"/g; // Double quotes for removal.
const R_DOT = /\./g; // Dots in path strings.
const R_CLONE_REF = /^`\$REF:([0-9]+)`$/; // Copy reference in cloning.
const R_META_PATH = /^([^$]+)\$([=~])(.+)$/; // Meta path syntax.
const R_DOUBLE_DOLLAR = /\$\$/g; // Double dollar escape sequence.
const R_TRANSFORM_NAME = /`\$([A-Z]+)`/g; // Transform command names.
const R_INJECTION_FULL = /^`(\$[A-Z]+|[^`]*)[0-9]*`$/; // Full string injection pattern.
const R_BT_ESCAPE = /\$BT/g; // Backtick escape sequence.
const R_DS_ESCAPE = /\$DS/g; // Dollar sign escape sequence.
const R_INJECTION_PARTIAL = /`([^`]+)`/g; // Partial string injection pattern.
// Default max depth (for walk etc).
const MAXDEPTH = 32;
// Return type string for narrowest type.
function typename(t) {
    return getelem(TYPENAME, Math.clz32(t), TYPENAME[0]);
}
// Get a defined value. Returns alt if val is undefined.
function getdef(val, alt) {
    if (NONE === val) {
        return alt;
    }
    return val;
}
// Value is a node - defined, and a map (hash) or list (array).
// NOTE: typescript
// things
function isnode(val) {
    return null != val && S_object == typeof val;
}
// Value is a defined map (hash) with string keys.
function ismap(val) {
    return null != val && S_object == typeof val && !Array.isArray(val);
}
// Value is a defined list (array) with integer keys (indexes).
function islist(val) {
    return Array.isArray(val);
}
// Value is a defined string (non-empty) or integer key.
function iskey(key) {
    const keytype = typeof key;
    return (S_string === keytype && S_MT !== key) || S_number === keytype;
}
// Check for an "empty" value - undefined, empty string, array, object.
function isempty(val) {
    return null == val || S_MT === val ||
        (Array.isArray(val) && 0 === val.length) ||
        (S_object === typeof val && 0 === Object.keys(val).length);
}
// Value is a function.
function isfunc(val) {
    return S_function === typeof val;
}
// The integer size of the value. For arrays and strings, the length,
// for numbers, the integer part, for boolean, true is 1 and falso 0, for all other values, 0.
function size(val) {
    if (islist(val)) {
        return val.length;
    }
    else if (ismap(val)) {
        return Object.keys(val).length;
    }
    const valtype = typeof val;
    if (S_string == valtype) {
        return val.length;
    }
    else if (S_number == typeof val) {
        return Math.floor(val);
    }
    else if (S_boolean == typeof val) {
        return true === val ? 1 : 0;
    }
    else {
        return 0;
    }
}
// Extract part of an array or string into a new value, from the start
// point to the end point.  If no end is specified, extract to the
// full length of the value. Negative arguments count from the end of
// the value. For numbers, perform min and max bounding, where start
// is inclusive, and end is *exclusive*.
// NOTE: input lists are not mutated by default. Use the mutate
// argument to mutate lists in place.
function slice(val, start, end, mutate) {
    if (S_number === typeof val) {
        start = null == start || S_number !== typeof start ? Number.MIN_SAFE_INTEGER : start;
        end = (null == end || S_number !== typeof end ? Number.MAX_SAFE_INTEGER : end) - 1;
        return Math.min(Math.max(val, start), end);
    }
    const vlen = size(val);
    if (null != end && null == start) {
        start = 0;
    }
    if (null != start) {
        if (start < 0) {
            end = vlen + start;
            if (end < 0) {
                end = 0;
            }
            start = 0;
        }
        else if (null != end) {
            if (end < 0) {
                end = vlen + end;
                if (end < 0) {
                    end = 0;
                }
            }
            else if (vlen < end) {
                end = vlen;
            }
        }
        else {
            end = vlen;
        }
        if (vlen < start) {
            start = vlen;
        }
        if (-1 < start && start <= end && end <= vlen) {
            if (islist(val)) {
                if (mutate) {
                    for (let i = 0, j = start; j < end; i++, j++) {
                        val[i] = val[j];
                    }
                    val.length = (end - start);
                }
                else {
                    val = val.slice(start, end);
                }
            }
            else if (S_string === typeof val) {
                val = val.substring(start, end);
            }
        }
        else {
            if (islist(val)) {
                val = [];
            }
            else if (S_string === typeof val) {
                val = S_MT;
            }
        }
    }
    return val;
}
// String padding.
function pad(str, padding, padchar) {
    str = S_string === typeof str ? str : stringify(str);
    padding = null == padding ? 44 : padding;
    padchar = null == padchar ? S_SP : ((padchar + S_SP)[0]);
    return -1 < padding ? str.padEnd(padding, padchar) : str.padStart(0 - padding, padchar);
}
// Determine the type of a value as a bit code.
function typify(value) {
    if (undefined === value) {
        return T_noval;
    }
    const typestr = typeof value;
    if (null === value) {
        return T_scalar | T_null;
    }
    else if (S_number === typestr) {
        if (Number.isInteger(value)) {
            return T_scalar | T_number | T_integer;
        }
        else if (isNaN(value)) {
            return T_noval;
        }
        else {
            return T_scalar | T_number | T_decimal;
        }
    }
    else if (S_string === typestr) {
        return T_scalar | T_string;
    }
    else if (S_boolean === typestr) {
        return T_scalar | T_boolean;
    }
    else if (S_function === typestr) {
        return T_scalar | T_function;
    }
    // For languages that have symbolic atoms.
    else if (S_symbol === typestr) {
        return T_scalar | T_symbol;
    }
    else if (Array.isArray(value)) {
        return T_node | T_list;
    }
    else if (S_object === typestr) {
        if (value.constructor instanceof Function) {
            let cname = value.constructor.name;
            if ('Object' !== cname && 'Array' !== cname) {
                return T_node | T_instance;
            }
        }
        return T_node | T_map;
    }
    // Anything else (e.g. bigint) is considered T_any
    return T_any;
}
// Get a list element. The key should be an integer, or a string
// that can parse to an integer only. Negative integers count from the end of the list.
function getelem(val, key, alt) {
    let out = NONE;
    if (NONE === val || NONE === key) {
        return alt;
    }
    if (islist(val)) {
        let nkey = parseInt(key);
        if (Number.isInteger(nkey) && ('' + key).match(R_INTEGER_KEY)) {
            if (nkey < 0) {
                key = val.length + nkey;
            }
            out = val[key];
        }
    }
    if (NONE === out) {
        return 0 < (T_function & typify(alt)) ? alt() : alt;
    }
    return out;
}
// Safely get a property of a node. Undefined arguments return undefined.
// If the key is not found, return the alternative value, if any.
function getprop(val, key, alt) {
    let out = alt;
    if (NONE === val || NONE === key) {
        return alt;
    }
    if (isnode(val)) {
        out = val[key];
    }
    if (NONE === out) {
        return alt;
    }
    return out;
}
// Convert different types of keys to string representation.
// String keys are returned as is.
// Number keys are converted to strings.
// Floats are truncated to integers.
// Booleans, objects, arrays, null, undefined all return empty string.
function strkey(key = NONE) {
    if (NONE === key) {
        return S_MT;
    }
    const t = typify(key);
    if (0 < (T_string & t)) {
        return key;
    }
    else if (0 < (T_boolean & t)) {
        return S_MT;
    }
    else if (0 < (T_number & t)) {
        return key % 1 === 0 ? String(key) : String(Math.floor(key));
    }
    return S_MT;
}
// Sorted keys of a map, or indexes (as strings) of a list.
// Root utility - only uses language facilities.
function keysof(val) {
    return !isnode(val) ? [] :
        ismap(val) ? Object.keys(val).sort() : val.map((_n, i) => S_MT + i);
}
// Value of property with name key in node val is defined.
// Root utility - only uses language facilities.
function haskey(val, key) {
    return NONE !== getprop(val, key);
}
function items(val, apply) {
    let out = keysof(val).map((k) => [k, val[k]]);
    if (null != apply) {
        out = out.map(apply);
    }
    return out;
}
// To replicate the array spread operator:
// a=1, b=[2,3], c=[4,5]
// [a,...b,c] -> [1,2,3,[4,5]]
// flatten([a,b,[c]]) -> [1,2,3,[4,5]]
// NOTE: [c] ensures c is not expanded
function flatten(list, depth) {
    if (!islist(list)) {
        return list;
    }
    return list.flat(getdef(depth, 1));
}
// Filter item values using check function.
function filter(val, check) {
    let all = items(val);
    let numall = size(all);
    let out = [];
    for (let i = 0; i < numall; i++) {
        if (check(all[i])) {
            out.push(all[i][1]);
        }
    }
    return out;
}
// Escape regular expression.
function escre(s) {
    // s = null == s ? S_MT : s
    return replace(s, R_ESCAPE_REGEXP, '\\$&');
}
// Escape URLs.
function escurl(s) {
    s = null == s ? S_MT : s;
    return encodeURIComponent(s);
}
// Replace a search string (all), or a regexp, in a source string.
function replace(s, from, to) {
    let rs = s;
    let ts = typify(s);
    if (0 === (T_string & ts)) {
        rs = stringify(s);
    }
    else if (0 < ((T_noval | T_null) & ts)) {
        rs = S_MT;
    }
    else {
        rs = stringify(s);
    }
    return rs.replace(from, to);
}
// Concatenate url part strings, merging sep char as needed.
function join(arr, sep, url) {
    const sarr = size(arr);
    const sepdef = getdef(sep, S_CM);
    const sepre = 1 === size(sepdef) ? escre(sepdef) : NONE;
    const out = filter(items(
    // filter(arr, (n) => null != n[1] && S_MT !== n[1]),
    filter(arr, (n) => (0 < (T_string & typify(n[1]))) && S_MT !== n[1]), (n) => {
        let i = +n[0];
        let s = n[1];
        if (NONE !== sepre && S_MT !== sepre) {
            if (url && 0 === i) {
                s = replace(s, RegExp(sepre + '+$'), S_MT);
                return s;
            }
            if (0 < i) {
                s = replace(s, RegExp('^' + sepre + '+'), S_MT);
            }
            if (i < sarr - 1 || !url) {
                s = replace(s, RegExp(sepre + '+$'), S_MT);
            }
            s = replace(s, RegExp('([^' + sepre + '])' + sepre + '+([^' + sepre + '])'), '$1' + sepdef + '$2');
        }
        return s;
    }), (n) => S_MT !== n[1])
        .join(sepdef);
    return out;
}
// Output JSON in a "standard" format, with 2 space indents, each property on a new line,
// and spaces after {[: and before ]}. Any "wierd" values (NaN, etc) are output as null.
// In general, the behaivor of of JavaScript's JSON.stringify(val,null,2) is followed.
function jsonify(val, flags) {
    let str = S_null;
    if (null != val) {
        try {
            const indent = getprop(flags, 'indent', 2);
            str = JSON.stringify(val, null, indent);
            if (NONE === str) {
                str = S_null;
            }
            const offset = getprop(flags, 'offset', 0);
            if (0 < offset) {
                // Left offset entire indented JSON so that it aligns with surrounding code
                // indented by offset. Assume first brace is on line with asignment, so not offset.
                str = '{\n' +
                    join(items(slice(str.split('\n'), 1), (n) => pad(n[1], 0 - offset - size(n[1]))), '\n');
            }
        }
        catch (e) {
            str = '__JSONIFY_FAILED__';
        }
    }
    return str;
}
// Safely stringify a value for humans (NOT JSON!).
function stringify(val, maxlen, pretty) {
    let valstr = S_MT;
    pretty = !!pretty;
    if (NONE === val) {
        return pretty ? '<>' : valstr;
    }
    if (S_string === typeof val) {
        valstr = val;
    }
    else {
        try {
            valstr = JSON.stringify(val, function (_key, val) {
                if (val !== null &&
                    typeof val === "object" &&
                    !Array.isArray(val)) {
                    const sortedObj = {};
                    items(val, (n) => {
                        sortedObj[n[0]] = val[n[0]];
                    });
                    return sortedObj;
                }
                return val;
            });
            valstr = valstr.replace(R_QUOTES, S_MT);
        }
        catch (err) {
            valstr = '__STRINGIFY_FAILED__';
        }
    }
    if (null != maxlen && -1 < maxlen) {
        let js = valstr.substring(0, maxlen);
        valstr = maxlen < valstr.length ? (js.substring(0, maxlen - 3) + '...') : valstr;
    }
    if (pretty) {
        // Indicate deeper JSON levels with different terminal colors (simplistic wrt strings).
        let c = items([81, 118, 213, 39, 208, 201, 45, 190, 129, 51, 160, 121, 226, 33, 207, 69], (n) => '\x1b[38;5;' + n[1] + 'm'), r = '\x1b[0m', d = 0, o = c[0], t = o;
        for (const ch of valstr) {
            if (ch === '{' || ch === '[') {
                d++;
                o = c[d % c.length];
                t += o + ch;
            }
            else if (ch === '}' || ch === ']') {
                t += o + ch;
                d--;
                o = c[d % c.length];
            }
            else {
                t += o + ch;
            }
        }
        return t + r;
    }
    return valstr;
}
// Build a human friendly path string.
function pathify(val, startin, endin) {
    let pathstr = NONE;
    let path = islist(val) ? val :
        S_string == typeof val ? [val] :
            S_number == typeof val ? [val] :
                NONE;
    const start = null == startin ? 0 : -1 < startin ? startin : 0;
    const end = null == endin ? 0 : -1 < endin ? endin : 0;
    if (NONE != path && 0 <= start) {
        path = slice(path, start, path.length - end);
        if (0 === path.length) {
            pathstr = '<root>';
        }
        else {
            pathstr = join(items(filter(path, (n) => iskey(n[1])), (n) => {
                let p = n[1];
                return S_number === typeof p ? S_MT + Math.floor(p) :
                    p.replace(R_DOT, S_MT);
            }), S_DT);
        }
    }
    if (NONE === pathstr) {
        pathstr = '<unknown-path' + (NONE === val ? S_MT : S_CN + stringify(val, 47)) + '>';
    }
    return pathstr;
}
// Clone a JSON-like data structure.
// NOTE: function and instance values are copied, *not* cloned.
function clone(val) {
    const refs = [];
    const reftype = T_function | T_instance;
    const replacer = (_k, v) => 0 < (reftype & typify(v)) ?
        (refs.push(v), '`$REF:' + (refs.length - 1) + '`') : v;
    const reviver = (_k, v, m) => S_string === typeof v ?
        (m = v.match(R_CLONE_REF), m ? refs[m[1]] : v) : v;
    const out = NONE === val ? NONE : JSON.parse(JSON.stringify(val, replacer), reviver);
    return out;
}
// Define a JSON Object using function arguments.
function jm(...kv) {
    const kvsize = size(kv);
    const o = {};
    for (let i = 0; i < kvsize; i += 2) {
        let k = getprop(kv, i, '$KEY' + i);
        k = 'string' === typeof k ? k : stringify(k);
        o[k] = getprop(kv, i + 1, null);
    }
    return o;
}
// Define a JSON Array using function arguments.
function jt(...v) {
    const vsize = size(v);
    const a = new Array(vsize);
    for (let i = 0; i < vsize; i++) {
        a[i] = getprop(v, i, null);
    }
    return a;
}
// Safely delete a property from an object or array element. 
// Undefined arguments and invalid keys are ignored.
// Returns the (possibly modified) parent.
// For objects, the property is deleted using the delete operator.
// For arrays, the element at the index is removed and remaining elements are shifted down.
// NOTE: parent list may be new list, thus update references.
function delprop(parent, key) {
    if (!iskey(key)) {
        return parent;
    }
    if (ismap(parent)) {
        key = strkey(key);
        delete parent[key];
    }
    else if (islist(parent)) {
        // Ensure key is an integer.
        let keyI = +key;
        if (isNaN(keyI)) {
            return parent;
        }
        keyI = Math.floor(keyI);
        // Delete list element at position keyI, shifting later elements down.
        const psize = size(parent);
        if (0 <= keyI && keyI < psize) {
            for (let pI = keyI; pI < psize - 1; pI++) {
                parent[pI] = parent[pI + 1];
            }
            parent.length = parent.length - 1;
        }
    }
    return parent;
}
// Safely set a property. Undefined arguments and invalid keys are ignored.
// Returns the (possibly modified) parent.
// If the parent is a list, and the key is negative, prepend the value.
// NOTE: If the key is above the list size, append the value; below, prepend.
// NOTE: parent list may be new list, thus update references.
function setprop(parent, key, val) {
    if (!iskey(key)) {
        return parent;
    }
    if (ismap(parent)) {
        key = S_MT + key;
        const pany = parent;
        pany[key] = val;
    }
    else if (islist(parent)) {
        // Ensure key is an integer.
        let keyI = +key;
        if (isNaN(keyI)) {
            return parent;
        }
        keyI = Math.floor(keyI);
        // TODO: DELETE list element
        // Set or append value at position keyI, or append if keyI out of bounds.
        if (0 <= keyI) {
            parent[slice(keyI, 0, size(parent) + 1)] = val;
        }
        // Prepend value if keyI is negative
        else {
            parent.unshift(val);
        }
    }
    return parent;
}
// Walk a data structure depth first, applying a function to each value.
// The `path` argument passed to the before/after callbacks is a single
// mutable array per depth, shared across all callback invocations for the
// lifetime of this top-level walk call. Callbacks that need to store the
// path MUST clone it (e.g. `path.slice()`); the contents will otherwise
// be overwritten by subsequent visits.
function walk(
// These arguments are the public interface.
val, 
// Before descending into a node.
before, 
// After descending into a node.
after, 
// Maximum recursive depth, default: 32. Use null for infinite depth.
maxdepth, 
// These areguments are used for recursive state.
key, parent, path, pool) {
    if (NONE === pool) {
        pool = [[]];
    }
    if (NONE === path) {
        path = pool[0];
    }
    const depth = path.length;
    let out = null == before ? val : before(key, val, parent, path);
    maxdepth = null != maxdepth && 0 <= maxdepth ? maxdepth : MAXDEPTH;
    if (0 === maxdepth || (0 < maxdepth && maxdepth <= depth)) {
        return out;
    }
    if (isnode(out)) {
        const childDepth = depth + 1;
        let childPath = pool[childDepth];
        if (NONE === childPath) {
            childPath = new Array(childDepth);
            pool[childDepth] = childPath;
        }
        // Sync prefix [0..depth-1] from the current path. Only needed once per
        // parent: siblings share the same prefix and will each overwrite slot
        // [depth] below.
        for (let i = 0; i < depth; i++) {
            childPath[i] = path[i];
        }
        for (let [ckey, child] of items(out)) {
            childPath[depth] = S_MT + ckey;
            setprop(out, ckey, walk(child, before, after, maxdepth, ckey, out, childPath, pool));
        }
    }
    out = null == after ? out : after(key, out, parent, path);
    return out;
}
// Merge a list of values into each other. Later values have
// precedence.  Nodes override scalars. Node kinds (list or map)
// override each other, and do *not* merge.  The first element is
// modified.
function merge(val, maxdepth) {
    // const md: number = null == maxdepth ? MAXDEPTH : maxdepth < 0 ? 0 : maxdepth
    const md = slice(maxdepth ?? MAXDEPTH, 0);
    let out = NONE;
    // Handle edge cases.
    if (!islist(val)) {
        return val;
    }
    const list = val;
    const lenlist = list.length;
    if (0 === lenlist) {
        return NONE;
    }
    else if (1 === lenlist) {
        return list[0];
    }
    // Merge a list of values.
    out = getprop(list, 0, {});
    for (let oI = 1; oI < lenlist; oI++) {
        let obj = list[oI];
        if (!isnode(obj)) {
            // Nodes win.
            out = obj;
        }
        else {
            // Current value at path end in overriding node.
            let cur = [out];
            // Current value at path end in destination node.
            let dst = [out];
            function before(key, val, _parent, path) {
                const pI = size(path);
                if (md <= pI) {
                    setprop(cur[pI - 1], key, val);
                }
                // Scalars just override directly.
                else if (!isnode(val)) {
                    cur[pI] = val;
                }
                // Descend into override node - Set up correct target in `after` function.
                else {
                    // Descend into destination node using same key.
                    dst[pI] = 0 < pI ? getprop(dst[pI - 1], key) : dst[pI];
                    const tval = dst[pI];
                    // Destination empty, so create node (unless override is class instance).
                    if (NONE === tval && 0 === (T_instance & typify(val))) {
                        cur[pI] = islist(val) ? [] : {};
                    }
                    // Matching override and destination so continue with their values.
                    else if (typify(val) === typify(tval)) {
                        cur[pI] = tval;
                    }
                    // Override wins.
                    else {
                        cur[pI] = val;
                        // No need to descend when override wins (destination is discarded).
                        val = NONE;
                    }
                }
                // console.log('BEFORE-END', pathify(path), '@', pI, key,
                //   stringify(val, -1, 1), stringify(parent, -1, 1),
                //   'CUR=', stringify(cur, -1, 1), 'DST=', stringify(dst, -1, 1))
                return val;
            }
            function after(key, _val, _parent, path) {
                const cI = size(path);
                const target = cur[cI - 1];
                const value = cur[cI];
                // console.log('AFTER-PREP', pathify(path), '@', cI, cur, '|',
                //   stringify(key, -1, 1), stringify(value, -1, 1), 'T=', stringify(target, -1, 1))
                setprop(target, key, value);
                return value;
            }
            // Walk overriding node, creating paths in output as needed.
            out = walk(obj, before, after, maxdepth);
            // console.log('WALK-DONE', out, obj)
        }
    }
    if (0 === md) {
        out = getelem(list, -1);
        out = islist(out) ? [] : ismap(out) ? {} : out;
    }
    return out;
}
// Set a value using a path. Missing path parts are created.
// String paths create only maps. Use a string list to create list  parts.
function setpath(store, path, val, injdef) {
    const pathType = typify(path);
    const parts = 0 < (T_list & pathType) ? path :
        0 < (T_string & pathType) ? path.split(S_DT) :
            0 < (T_number & pathType) ? [path] : NONE;
    if (NONE === parts) {
        return NONE;
    }
    const base = getprop(injdef, S_base);
    const numparts = size(parts);
    let parent = getprop(store, base, store);
    for (let pI = 0; pI < numparts - 1; pI++) {
        const partKey = getelem(parts, pI);
        let nextParent = getprop(parent, partKey);
        if (!isnode(nextParent)) {
            nextParent = 0 < (T_number & typify(getelem(parts, pI + 1))) ? [] : {};
            setprop(parent, partKey, nextParent);
        }
        parent = nextParent;
    }
    if (DELETE === val) {
        delprop(parent, getelem(parts, -1));
    }
    else {
        setprop(parent, getelem(parts, -1), val);
    }
    return parent;
}
function getpath(store, path, injdef) {
    // Operate on a string array.
    const parts = islist(path) ? path :
        'string' === typeof path ? path.split(S_DT) :
            'number' === typeof path ? [strkey(path)] : NONE;
    if (NONE === parts) {
        return NONE;
    }
    // let root = store
    let val = store;
    const base = getprop(injdef, S_base);
    const src = getprop(store, base, store);
    const numparts = size(parts);
    const dparent = getprop(injdef, 'dparent');
    // An empty path (incl empty string) just finds the store.
    if (null == path || null == store || (1 === numparts && S_MT === parts[0])) {
        val = src;
    }
    else if (0 < numparts) {
        // Check for $ACTIONs
        if (1 === numparts) {
            val = getprop(store, parts[0]);
        }
        if (!isfunc(val)) {
            val = src;
            const m = parts[0].match(R_META_PATH);
            if (m && injdef && injdef.meta) {
                val = getprop(injdef.meta, m[1]);
                parts[0] = m[3];
            }
            const dpath = getprop(injdef, 'dpath');
            for (let pI = 0; NONE !== val && pI < numparts; pI++) {
                let part = parts[pI];
                if (injdef && S_DKEY === part) {
                    part = getprop(injdef, S_key);
                }
                else if (injdef && part.startsWith('$GET:')) {
                    // $GET:path$ -> get store value, use as path part (string)
                    part = stringify(getpath(src, slice(part, 5, -1)));
                }
                else if (injdef && part.startsWith('$REF:')) {
                    // $REF:refpath$ -> get spec value, use as path part (string)
                    part = stringify(getpath(getprop(store, S_DSPEC), slice(part, 5, -1)));
                }
                else if (injdef && part.startsWith('$META:')) {
                    // $META:metapath$ -> get meta value, use as path part (string)
                    part = stringify(getpath(getprop(injdef, 'meta'), slice(part, 6, -1)));
                }
                // $$ escapes $
                part = part.replace(R_DOUBLE_DOLLAR, '$');
                if (S_MT === part) {
                    let ascends = 0;
                    while (S_MT === parts[1 + pI]) {
                        ascends++;
                        pI++;
                    }
                    if (injdef && 0 < ascends) {
                        if (pI === parts.length - 1) {
                            ascends--;
                        }
                        if (0 === ascends) {
                            val = dparent;
                        }
                        else {
                            // const fullpath = slice(dpath, 0 - ascends).concat(parts.slice(pI + 1))
                            const fullpath = flatten([slice(dpath, 0 - ascends), parts.slice(pI + 1)]);
                            if (ascends <= size(dpath)) {
                                val = getpath(store, fullpath);
                            }
                            else {
                                val = NONE;
                            }
                            break;
                        }
                    }
                    else {
                        val = dparent;
                    }
                }
                else {
                    val = getprop(val, part);
                }
            }
        }
    }
    // Inj may provide a custom handler to modify found value.
    const handler = getprop(injdef, 'handler');
    if (null != injdef && isfunc(handler)) {
        const ref = pathify(path);
        val = handler(injdef, val, ref, store);
    }
    // console.log('GETPATH', path, val)
    return val;
}
// Inject values from a data store into a node recursively, resolving
// paths against the store, or current if they are local. The modify
// argument allows custom modification of the result.  The inj
// (Injection) argument is used to maintain recursive state.
function inject(val, store, injdef) {
    const valtype = typeof val;
    let inj = injdef;
    // Create state if at root of injection.  The input value is placed
    // inside a virtual parent holder to simplify edge cases.
    if (NONE === injdef || null == injdef.mode) {
        // Set up state assuming we are starting in the virtual parent.
        inj = new Injection(val, { [S_DTOP]: val });
        inj.dparent = store;
        inj.errs = getprop(store, S_DERRS, []);
        inj.meta.__d = 0;
        if (NONE !== injdef) {
            inj.modify = null == injdef.modify ? inj.modify : injdef.modify;
            inj.extra = null == injdef.extra ? inj.extra : injdef.extra;
            inj.meta = null == injdef.meta ? inj.meta : injdef.meta;
            inj.handler = null == injdef.handler ? inj.handler : injdef.handler;
        }
    }
    inj.descend();
    // console.log('INJ-START', val, inj.mode, inj.key, inj.val,
    //  't=', inj.path, 'P=', inj.parent, 'dp=', inj.dparent, 'ST=', store.$TOP)
    // Descend into node.
    if (isnode(val)) {
        // Keys are sorted alphanumerically to ensure determinism.
        // Injection transforms ($FOO) are processed *after* other keys.
        // NOTE: the optional digits suffix of the transform can thus be
        // used to order the transforms.
        let nodekeys;
        nodekeys = keysof(val);
        if (ismap(val)) {
            nodekeys = flatten([
                filter(nodekeys, (n => !n[1].includes(S_DS))),
                filter(nodekeys, (n => n[1].includes(S_DS))),
            ]);
        }
        else {
            nodekeys = keysof(val);
        }
        // Each child key-value pair is processed in three injection phases:
        // 1. inj.mode=M_KEYPRE - Key string is injected, returning a possibly altered key.
        // 2. inj.mode=M_VAL - The child value is injected.
        // 3. inj.mode=M_KEYPOST - Key string is injected again, allowing child mutation.
        for (let nkI = 0; nkI < nodekeys.length; nkI++) {
            const childinj = inj.child(nkI, nodekeys);
            const nodekey = childinj.key;
            childinj.mode = M_KEYPRE;
            // Peform the key:pre mode injection on the child key.
            const prekey = _injectstr(nodekey, store, childinj);
            // The injection may modify child processing.
            nkI = childinj.keyI;
            nodekeys = childinj.keys;
            // Prevent further processing by returning an undefined prekey
            if (NONE !== prekey) {
                childinj.val = getprop(val, prekey);
                childinj.mode = M_VAL;
                // Perform the val mode injection on the child value.
                // NOTE: return value is not used.
                inject(childinj.val, store, childinj);
                // The injection may modify child processing.
                nkI = childinj.keyI;
                nodekeys = childinj.keys;
                // Peform the key:post mode injection on the child key.
                childinj.mode = M_KEYPOST;
                _injectstr(nodekey, store, childinj);
                // The injection may modify child processing.
                nkI = childinj.keyI;
                nodekeys = childinj.keys;
            }
        }
    }
    // Inject paths into string scalars.
    else if (S_string === valtype) {
        inj.mode = M_VAL;
        val = _injectstr(val, store, inj);
        if (SKIP !== val) {
            inj.setval(val);
        }
    }
    // Custom modification.
    if (inj.modify && SKIP !== val) {
        let mkey = inj.key;
        let mparent = inj.parent;
        let mval = getprop(mparent, mkey);
        inj.modify(mval, mkey, mparent, inj, store);
    }
    // console.log('INJ-VAL', val)
    inj.val = val;
    // Original val reference may no longer be correct.
    // This return value is only used as the top level result.
    return getprop(inj.parent, S_DTOP);
}
// The transform_* functions are special command inject handlers (see Injector).
// Delete a key from a map or list.
const transform_DELETE = (inj) => {
    inj.setval(NONE);
    return NONE;
};
// Copy value from source data.
const transform_COPY = (inj, _val) => {
    const ijname = 'COPY';
    if (!checkPlacement(M_VAL, ijname, T_any, inj)) {
        return NONE;
    }
    let out = getprop(inj.dparent, inj.key);
    inj.setval(out);
    return out;
};
// As a value, inject the key of the parent node.
// As a key, defined the name of the key property in the source object.
const transform_KEY = (inj) => {
    const { mode, path, parent } = inj;
    // Do nothing in val mode - not an error.
    if (M_VAL !== mode) {
        return NONE;
    }
    // Key is defined by $KEY meta property.
    const keyspec = getprop(parent, S_BKEY);
    if (NONE !== keyspec) {
        delprop(parent, S_BKEY);
        return getprop(inj.dparent, keyspec);
    }
    // Key is defined within general purpose $META object.
    // return getprop(getprop(parent, S_BANNO), S_KEY, getprop(path, path.length - 2))
    return getprop(getprop(parent, S_BANNO), S_KEY, getelem(path, -2));
};
// Annotate node.  Does nothing itself, just used by
// other injectors, and is removed when called.
const transform_ANNO = (inj) => {
    const { parent } = inj;
    delprop(parent, S_BANNO);
    return NONE;
};
// Merge a list of objects into the current object. 
// Must be a key in an object. The value is merged over the current object.
// If the value is an array, the elements are first merged using `merge`. 
// If the value is the empty string, merge the top level store.
// Format: { '`$MERGE`': '`source-path`' | ['`source-paths`', ...] }
const transform_MERGE = (inj) => {
    const { mode, key, parent } = inj;
    // Ensures $MERGE is removed from parent list (val mode).
    let out = NONE;
    if (M_KEYPRE === mode) {
        out = key;
    }
    // Operate after child values have been transformed.
    else if (M_KEYPOST === mode) {
        out = key;
        let args = getprop(parent, key);
        args = Array.isArray(args) ? args : [args];
        // Remove the $MERGE command from a parent map.
        inj.setval(NONE);
        // Literals in the parent have precedence, but we still merge onto
        // the parent object, so that node tree references are not changed.
        const mergelist = flatten([[parent], args, [clone(parent)]]);
        merge(mergelist);
    }
    return out;
};
// Convert a node to a list.
// Format: ['`$EACH`', '`source-path-of-node`', child-template]
const transform_EACH = (inj, _val, _ref, store) => {
    const ijname = 'EACH';
    if (!checkPlacement(M_VAL, ijname, T_list, inj)) {
        return NONE;
    }
    // Remove remaining keys to avoid spurious processing.
    slice(inj.keys, 0, 1, true);
    // const [err, srcpath, child] = injectorArgs([T_string, T_any], inj)
    const [err, srcpath, child] = injectorArgs([T_string, T_any], slice(inj.parent, 1));
    if (NONE !== err) {
        inj.errs.push('$' + ijname + ': ' + err);
        return NONE;
    }
    // Source data.
    const srcstore = getprop(store, inj.base, store);
    const src = getpath(srcstore, srcpath, inj);
    const srctype = typify(src);
    // Create parallel data structures:
    // source entries :: child templates
    let tcur = [];
    let tval = [];
    const tkey = getelem(inj.path, -2);
    const target = getelem(inj.nodes, -2, () => getelem(inj.nodes, -1));
    // Create clones of the child template for each value of the current soruce.
    if (0 < (T_list & srctype)) {
        tval = items(src, () => clone(child));
    }
    else if (0 < (T_map & srctype)) {
        tval = items(src, (n => merge([
            clone(child),
            // Make a note of the key for $KEY transforms.
            { [S_BANNO]: { KEY: n[0] } }
        ], 1)));
    }
    let rval = [];
    if (0 < size(tval)) {
        tcur = null == src ? NONE : items(src, (n) => n[1]);
        const ckey = getelem(inj.path, -2);
        const tpath = slice(inj.path, -1);
        const dpath = flatten([S_DTOP, srcpath.split(S_DT), '$:' + ckey]);
        // Parent structure.
        tcur = { [ckey]: tcur };
        if (1 < size(tpath)) {
            const pkey = getelem(inj.path, -3, S_DTOP);
            tcur = { [pkey]: tcur };
            dpath.push('$:' + pkey);
        }
        const tinj = inj.child(0, [ckey]);
        tinj.path = tpath;
        tinj.nodes = slice(inj.nodes, -1);
        tinj.parent = getelem(tinj.nodes, -1);
        setprop(tinj.parent, ckey, tval);
        tinj.val = tval;
        tinj.dpath = dpath;
        tinj.dparent = tcur;
        inject(tval, store, tinj);
        rval = tinj.val;
    }
    // _updateAncestors(inj, target, tkey, rval)
    setprop(target, tkey, rval);
    // Prevent callee from damaging first list entry (since we are in `val` mode).
    return rval[0];
};
// Convert a node to a map.
// Format: { '`$PACK`':['source-path', child-template]}
const transform_PACK = (inj, _val, _ref, store) => {
    const { mode, key, path, parent, nodes } = inj;
    const ijname = 'EACH';
    if (!checkPlacement(M_KEYPRE, ijname, T_map, inj)) {
        return NONE;
    }
    // Get arguments.
    const args = getprop(parent, key);
    const [err, srcpath, origchildspec] = injectorArgs([T_string, T_any], args);
    if (NONE !== err) {
        inj.errs.push('$' + ijname + ': ' + err);
        return NONE;
    }
    // Find key and target node.
    const tkey = getelem(path, -2);
    const pathsize = size(path);
    const target = getelem(nodes, pathsize - 2, () => getelem(nodes, pathsize - 1));
    // Source data
    const srcstore = getprop(store, inj.base, store);
    let src = getpath(srcstore, srcpath, inj);
    // Prepare source as a list.
    if (!islist(src)) {
        if (ismap(src)) {
            src = items(src, (item) => {
                setprop(item[1], S_BANNO, { KEY: item[0] });
                return item[1];
            });
        }
        else {
            src = NONE;
        }
    }
    if (null == src) {
        return NONE;
    }
    // Get keypath.
    const keypath = getprop(origchildspec, S_BKEY);
    const childspec = delprop(origchildspec, S_BKEY);
    const child = getprop(childspec, S_BVAL, childspec);
    // Build parallel target object.
    let tval = {};
    items(src, (item) => {
        const srckey = item[0];
        const srcnode = item[1];
        let key = srckey;
        if (NONE !== keypath) {
            if (keypath.startsWith('`')) {
                key = inject(keypath, merge([{}, store, { $TOP: srcnode }], 1));
            }
            else {
                key = getpath(srcnode, keypath, inj);
            }
        }
        const tchild = clone(child);
        setprop(tval, key, tchild);
        const anno = getprop(srcnode, S_BANNO);
        if (NONE === anno) {
            delprop(tchild, S_BANNO);
        }
        else {
            setprop(tchild, S_BANNO, anno);
        }
    });
    let rval = {};
    if (!isempty(tval)) {
        // Build parallel source object.
        let tsrc = {};
        src.reduce((a, n, i) => {
            let kn = null == keypath ? i :
                keypath.startsWith('`') ?
                    inject(keypath, merge([{}, store, { $TOP: n }], 1)) :
                    getpath(n, keypath, inj);
            setprop(a, kn, n);
            return a;
        }, tsrc);
        const tpath = slice(inj.path, -1);
        const ckey = getelem(inj.path, -2);
        const dpath = flatten([S_DTOP, srcpath.split(S_DT), '$:' + ckey]);
        let tcur = { [ckey]: tsrc };
        if (1 < size(tpath)) {
            const pkey = getelem(inj.path, -3, S_DTOP);
            tcur = { [pkey]: tcur };
            dpath.push('$:' + pkey);
        }
        const tinj = inj.child(0, [ckey]);
        tinj.path = tpath;
        tinj.nodes = slice(inj.nodes, -1);
        tinj.parent = getelem(tinj.nodes, -1);
        tinj.val = tval;
        tinj.dpath = dpath;
        tinj.dparent = tcur;
        inject(tval, store, tinj);
        rval = tinj.val;
    }
    // _updateAncestors(inj, target, tkey, rval)
    setprop(target, tkey, rval);
    // Drop transform key.
    return NONE;
};
// TODO: not found ref should removed key (setprop NONE)
// Reference original spec (enables recursice transformations)
// Format: ['`$REF`', '`spec-path`']
const transform_REF = (inj, val, _ref, store) => {
    const { nodes } = inj;
    if (M_VAL !== inj.mode) {
        return NONE;
    }
    // Get arguments: ['`$REF`', 'ref-path'].
    const refpath = getprop(inj.parent, 1);
    inj.keyI = size(inj.keys);
    // Spec reference.
    const spec = getprop(store, S_DSPEC)();
    const dpath = slice(inj.path, 1);
    const ref = getpath(spec, refpath, {
        // TODO: test relative refs
        // dpath: inj.path.slice(1),
        dpath,
        // dparent: getpath(spec, inj.path.slice(1))
        dparent: getpath(spec, dpath),
    });
    let hasSubRef = false;
    if (isnode(ref)) {
        walk(ref, (_k, v) => {
            if ('`$REF`' === v) {
                hasSubRef = true;
            }
            return v;
        });
    }
    let tref = clone(ref);
    const cpath = slice(inj.path, -3);
    const tpath = slice(inj.path, -1);
    let tcur = getpath(store, cpath);
    let tval = getpath(store, tpath);
    let rval = NONE;
    if (!hasSubRef || NONE !== tval) {
        const tinj = inj.child(0, [getelem(tpath, -1)]);
        tinj.path = tpath;
        tinj.nodes = slice(inj.nodes, -1);
        tinj.parent = getelem(nodes, -2);
        tinj.val = tref;
        tinj.dpath = flatten([cpath]);
        tinj.dparent = tcur;
        inject(tref, store, tinj);
        rval = tinj.val;
    }
    else {
        rval = NONE;
    }
    const grandparent = inj.setval(rval, 2);
    if (islist(grandparent) && inj.prior) {
        inj.prior.keyI--;
    }
    return val;
};
const transform_FORMAT = (inj, _val, _ref, store) => {
    // console.log('FORMAT-START', inj, _val)
    // Remove remaining keys to avoid spurious processing.
    slice(inj.keys, 0, 1, true);
    if (M_VAL !== inj.mode) {
        return NONE;
    }
    // Get arguments: ['`$FORMAT`', 'name', child].
    // TODO: EACH and PACK should accept customm functions too
    const name = getprop(inj.parent, 1);
    const child = getprop(inj.parent, 2);
    // Source data.
    const tkey = getelem(inj.path, -2);
    const target = getelem(inj.nodes, -2, () => getelem(inj.nodes, -1));
    const cinj = injectChild(child, store, inj);
    const resolved = cinj.val;
    let formatter = 0 < (T_function & typify(name)) ? name : getprop(FORMATTER, name);
    if (NONE === formatter) {
        inj.errs.push('$FORMAT: unknown format: ' + name + '.');
        return NONE;
    }
    let out = walk(resolved, formatter);
    setprop(target, tkey, out);
    // _updateAncestors(inj, target, tkey, out)
    return out;
};
const FORMATTER = {
    identity: (_k, v) => v,
    upper: (_k, v) => isnode(v) ? v : ('' + v).toUpperCase(),
    lower: (_k, v) => isnode(v) ? v : ('' + v).toLowerCase(),
    string: (_k, v) => isnode(v) ? v : ('' + v),
    number: (_k, v) => {
        if (isnode(v)) {
            return v;
        }
        else {
            let n = Number(v);
            if (isNaN(n)) {
                n = 0;
            }
            return n;
        }
    },
    integer: (_k, v) => {
        if (isnode(v)) {
            return v;
        }
        else {
            let n = Number(v);
            if (isNaN(n)) {
                n = 0;
            }
            return n | 0;
        }
    },
    concat: (k, v) => null == k && islist(v) ? join(items(v, (n => isnode(n[1]) ? S_MT : (S_MT + n[1]))), S_MT) : v
};
const transform_APPLY = (inj, _val, _ref, store) => {
    const ijname = 'APPLY';
    if (!checkPlacement(M_VAL, ijname, T_list, inj)) {
        return NONE;
    }
    // const [err, apply, child] = injectorArgs([T_function, T_any], inj)
    const [err, apply, child] = injectorArgs([T_function, T_any], slice(inj.parent, 1));
    if (NONE !== err) {
        inj.errs.push('$' + ijname + ': ' + err);
        return NONE;
    }
    const tkey = getelem(inj.path, -2);
    const target = getelem(inj.nodes, -2, () => getelem(inj.nodes, -1));
    const cinj = injectChild(child, store, inj);
    const resolved = cinj.val;
    const out = apply(resolved, store, cinj);
    setprop(target, tkey, out);
    return out;
};
// Transform data using spec.
// Only operates on static JSON-like data.
// Arrays are treated as if they are objects with indices as keys.
function transform(data, // Source data to transform into new data (original not mutated)
spec, // Transform specification; output follows this shape
injdef) {
    // Clone the spec so that the clone can be modified in place as the transform result.
    const origspec = spec;
    spec = clone(origspec);
    const extra = injdef?.extra;
    const collect = null != injdef?.errs;
    const errs = injdef?.errs || [];
    const extraTransforms = {};
    const extraData = null == extra ? NONE : items(extra)
        .reduce((a, n) => (n[0].startsWith(S_DS) ? extraTransforms[n[0]] = n[1] : (a[n[0]] = n[1]), a), {});
    const dataClone = merge([
        isempty(extraData) ? NONE : clone(extraData),
        clone(data),
    ]);
    // Define a top level store that provides transform operations.
    const store = merge([
        {
            // The inject function recognises this special location for the root of the source data.
            // NOTE: to escape data that contains "`$FOO`" keys at the top level,
            // place that data inside a holding map: { myholder: mydata }.
            $TOP: dataClone,
            $SPEC: () => origspec,
            // Escape backtick (this also works inside backticks).
            $BT: () => S_BT,
            // Escape dollar sign (this also works inside backticks).
            $DS: () => S_DS,
            // Insert current date and time as an ISO string.
            $WHEN: () => new Date().toISOString(),
            $DELETE: transform_DELETE,
            $COPY: transform_COPY,
            $KEY: transform_KEY,
            $ANNO: transform_ANNO,
            $MERGE: transform_MERGE,
            $EACH: transform_EACH,
            $PACK: transform_PACK,
            $REF: transform_REF,
            $FORMAT: transform_FORMAT,
            $APPLY: transform_APPLY,
        },
        // Custom extra transforms, if any.
        extraTransforms,
        {
            $ERRS: errs,
        }
    ], 1);
    const out = inject(spec, store, injdef);
    const generr = (0 < size(errs) && !collect);
    if (generr) {
        throw new Error(join(errs, ' | '));
    }
    return out;
}
// A required string value. NOTE: Rejects empty strings.
const validate_STRING = (inj) => {
    let out = getprop(inj.dparent, inj.key);
    const t = typify(out);
    if (0 === (T_string & t)) {
        let msg = _invalidTypeMsg(inj.path, S_string, t, out, 'V1010');
        inj.errs.push(msg);
        return NONE;
    }
    if (S_MT === out) {
        let msg = 'Empty string at ' + pathify(inj.path, 1);
        inj.errs.push(msg);
        return NONE;
    }
    return out;
};
const validate_TYPE = (inj, _val, ref) => {
    const tname = slice(ref, 1).toLowerCase();
    const typev = 1 << (31 - TYPENAME.indexOf(tname));
    let out = getprop(inj.dparent, inj.key);
    const t = typify(out);
    // console.log('TYPE', tname, typev, tn(typev), 'O=', t, tn(t), out, 'C=', t & typev)
    if (0 === (t & typev)) {
        inj.errs.push(_invalidTypeMsg(inj.path, tname, t, out, 'V1001'));
        return NONE;
    }
    return out;
};
// Allow any value.
const validate_ANY = (inj) => {
    let out = getprop(inj.dparent, inj.key);
    return out;
};
// Specify child values for map or list.
// Map syntax: {'`$CHILD`': child-template }
// List syntax: ['`$CHILD`', child-template ]
const validate_CHILD = (inj) => {
    const { mode, key, parent, keys, path } = inj;
    // Setup data structures for validation by cloning child template.
    // Map syntax.
    if (M_KEYPRE === mode) {
        const childtm = getprop(parent, key);
        // Get corresponding current object.
        const pkey = getelem(path, -2);
        let tval = getprop(inj.dparent, pkey);
        if (NONE == tval) {
            tval = {};
        }
        else if (!ismap(tval)) {
            inj.errs.push(_invalidTypeMsg(slice(inj.path, -1), S_object, typify(tval), tval), 'V0220');
            return NONE;
        }
        const ckeys = keysof(tval);
        for (let ckey of ckeys) {
            setprop(parent, ckey, clone(childtm));
            // NOTE: modifying inj! This extends the child value loop in inject.
            keys.push(ckey);
        }
        // Remove $CHILD to cleanup ouput.
        inj.setval(NONE);
        return NONE;
    }
    // List syntax.
    if (M_VAL === mode) {
        if (!islist(parent)) {
            // $CHILD was not inside a list.
            inj.errs.push('Invalid $CHILD as value');
            return NONE;
        }
        const childtm = getprop(parent, 1);
        if (NONE === inj.dparent) {
            // Empty list as default.
            // parent.length = 0
            slice(parent, 0, 0, true);
            return NONE;
        }
        if (!islist(inj.dparent)) {
            const msg = _invalidTypeMsg(slice(inj.path, -1), S_list, typify(inj.dparent), inj.dparent, 'V0230');
            inj.errs.push(msg);
            inj.keyI = size(parent);
            return inj.dparent;
        }
        // Clone children abd reset inj key index.
        // The inject child loop will now iterate over the cloned children,
        // validating them againt the current list values.
        items(inj.dparent, (n) => setprop(parent, n[0], clone(childtm)));
        slice(parent, 0, inj.dparent.length, true);
        inj.keyI = 0;
        const out = getprop(inj.dparent, 0);
        return out;
    }
    return NONE;
};
// TODO: implement SOME, ALL
// FIX: ONE should mean exactly one, not at least one (=SOME)
// TODO: implement a generate validate_ALT to do all of these
// Match at least one of the specified shapes.
// Syntax: ['`$ONE`', alt0, alt1, ...]
const validate_ONE = (inj, _val, _ref, store) => {
    const { mode, parent, keyI } = inj;
    // Only operate in val mode, since parent is a list.
    if (M_VAL === mode) {
        if (!islist(parent) || 0 !== keyI) {
            inj.errs.push('The $ONE validator at field ' +
                pathify(inj.path, 1, 1) +
                ' must be the first element of an array.');
            return;
        }
        inj.keyI = size(inj.keys);
        // Clean up structure, replacing [$ONE, ...] with current
        inj.setval(inj.dparent, 2);
        inj.path = slice(inj.path, -1);
        inj.key = getelem(inj.path, -1);
        let tvals = slice(parent, 1);
        if (0 === size(tvals)) {
            inj.errs.push('The $ONE validator at field ' +
                pathify(inj.path, 1, 1) +
                ' must have at least one argument.');
            return;
        }
        // See if we can find a match.
        for (let tval of tvals) {
            // If match, then errs.length = 0
            let terrs = [];
            const vstore = merge([{}, store], 1);
            vstore.$TOP = inj.dparent;
            const vcurrent = validate(inj.dparent, tval, {
                extra: vstore,
                errs: terrs,
                meta: inj.meta,
            });
            inj.setval(vcurrent, -2);
            // Accept current value if there was a match
            if (0 === size(terrs)) {
                return;
            }
        }
        // There was no match.
        const valdesc = replace(join(items(tvals, (n) => stringify(n[1])), ', '), R_TRANSFORM_NAME, (_m, p1) => p1.toLowerCase());
        inj.errs.push(_invalidTypeMsg(inj.path, (1 < size(tvals) ? 'one of ' : '') + valdesc, typify(inj.dparent), inj.dparent, 'V0210'));
    }
};
const validate_EXACT = (inj) => {
    const { mode, parent, key, keyI } = inj;
    // Only operate in val mode, since parent is a list.
    if (M_VAL === mode) {
        if (!islist(parent) || 0 !== keyI) {
            inj.errs.push('The $EXACT validator at field ' +
                pathify(inj.path, 1, 1) +
                ' must be the first element of an array.');
            return;
        }
        inj.keyI = size(inj.keys);
        // Clean up structure, replacing [$EXACT, ...] with current data parent
        inj.setval(inj.dparent, 2);
        // inj.path = slice(inj.path, 0, size(inj.path) - 1)
        inj.path = slice(inj.path, 0, -1);
        inj.key = getelem(inj.path, -1);
        let tvals = slice(parent, 1);
        if (0 === size(tvals)) {
            inj.errs.push('The $EXACT validator at field ' +
                pathify(inj.path, 1, 1) +
                ' must have at least one argument.');
            return;
        }
        // See if we can find an exact value match.
        let currentstr = undefined;
        for (let tval of tvals) {
            let exactmatch = tval === inj.dparent;
            if (!exactmatch && isnode(tval)) {
                currentstr = undefined === currentstr ? stringify(inj.dparent) : currentstr;
                const tvalstr = stringify(tval);
                exactmatch = tvalstr === currentstr;
            }
            if (exactmatch) {
                return;
            }
        }
        // There was no match.
        const valdesc = replace(join(items(tvals, (n) => stringify(n[1])), ', '), R_TRANSFORM_NAME, (_m, p1) => p1.toLowerCase());
        inj.errs.push(_invalidTypeMsg(inj.path, (1 < size(inj.path) ? '' : 'value ') +
            'exactly equal to ' + (1 === size(tvals) ? '' : 'one of ') + valdesc, typify(inj.dparent), inj.dparent, 'V0110'));
    }
    else {
        delprop(parent, key);
    }
};
// This is the "modify" argument to inject. Use this to perform
// generic validation. Runs *after* any special commands.
const _validation = (pval, key, parent, inj) => {
    if (NONE === inj) {
        return;
    }
    if (SKIP === pval) {
        return;
    }
    // select needs exact matches
    const exact = getprop(inj.meta, S_BEXACT, false);
    // Current val to verify.
    const cval = getprop(inj.dparent, key);
    if (NONE === inj || (!exact && NONE === cval)) {
        return;
    }
    const ptype = typify(pval);
    // Delete any special commands remaining.
    if (0 < (T_string & ptype) && pval.includes(S_DS)) {
        return;
    }
    const ctype = typify(cval);
    // Type mismatch.
    if (ptype !== ctype && NONE !== pval) {
        inj.errs.push(_invalidTypeMsg(inj.path, typename(ptype), ctype, cval, 'V0010'));
        return;
    }
    if (ismap(cval)) {
        if (!ismap(pval)) {
            inj.errs.push(_invalidTypeMsg(inj.path, typename(ptype), ctype, cval, 'V0020'));
            return;
        }
        const ckeys = keysof(cval);
        const pkeys = keysof(pval);
        // Empty spec object {} means object can be open (any keys).
        if (0 < size(pkeys) && true !== getprop(pval, '`$OPEN`')) {
            const badkeys = [];
            for (let ckey of ckeys) {
                if (!haskey(pval, ckey)) {
                    badkeys.push(ckey);
                }
            }
            // Closed object, so reject extra keys not in shape.
            if (0 < size(badkeys)) {
                const msg = 'Unexpected keys at field ' + pathify(inj.path, 1) + S_VIZ + join(badkeys, ', ');
                inj.errs.push(msg);
            }
        }
        else {
            // Object is open, so merge in extra keys.
            merge([pval, cval]);
            if (isnode(pval)) {
                delprop(pval, '`$OPEN`');
            }
        }
    }
    else if (islist(cval)) {
        if (!islist(pval)) {
            inj.errs.push(_invalidTypeMsg(inj.path, typename(ptype), ctype, cval, 'V0030'));
        }
    }
    else if (exact) {
        if (cval !== pval) {
            const pathmsg = 1 < size(inj.path) ? 'at field ' + pathify(inj.path, 1) + S_VIZ : S_MT;
            inj.errs.push('Value ' + pathmsg + cval +
                ' should equal ' + pval + S_DT);
        }
    }
    else {
        // Spec value was a default, copy over data
        setprop(parent, key, cval);
    }
    return;
};
// Validate a data structure against a shape specification.  The shape
// specification follows the "by example" principle.  Plain data in
// teh shape is treated as default values that also specify the
// required type.  Thus shape {a:1} validates {a:2}, since the types
// (number) match, but not {a:'A'}.  Shape {a;1} against data {}
// returns {a:1} as a=1 is the default value of the a key.  Special
// validation commands (in the same syntax as transform ) are also
// provided to specify required values.  Thus shape {a:'`$STRING`'}
// validates {a:'A'} but not {a:1}. Empty map or list means the node
// is open, and if missing an empty default is inserted.
function validate(data, // Source data to transform into new data (original not mutated)
spec, // Transform specification; output follows this shape
injdef) {
    const extra = injdef?.extra;
    const collect = null != injdef?.errs;
    const errs = injdef?.errs || [];
    const store = merge([
        {
            // Remove the transform commands.
            $DELETE: null,
            $COPY: null,
            $KEY: null,
            $META: null,
            $MERGE: null,
            $EACH: null,
            $PACK: null,
            $STRING: validate_STRING,
            $NUMBER: validate_TYPE,
            $INTEGER: validate_TYPE,
            $DECIMAL: validate_TYPE,
            $BOOLEAN: validate_TYPE,
            $NULL: validate_TYPE,
            $NIL: validate_TYPE,
            $MAP: validate_TYPE,
            $LIST: validate_TYPE,
            $FUNCTION: validate_TYPE,
            $INSTANCE: validate_TYPE,
            $ANY: validate_ANY,
            $CHILD: validate_CHILD,
            $ONE: validate_ONE,
            $EXACT: validate_EXACT,
        },
        getdef(extra, {}),
        // A special top level value to collect errors.
        // NOTE: collecterrs parameter always wins.
        {
            $ERRS: errs,
        }
    ], 1);
    let meta = getprop(injdef, 'meta', {});
    setprop(meta, S_BEXACT, getprop(meta, S_BEXACT, false));
    const out = transform(data, spec, {
        meta,
        extra: store,
        modify: _validation,
        handler: _validatehandler,
        errs,
    });
    const generr = (0 < size(errs) && !collect);
    if (generr) {
        throw new Error(join(errs, ' | '));
    }
    return out;
}
const select_AND = (inj, _val, _ref, store) => {
    if (M_KEYPRE === inj.mode) {
        const terms = getprop(inj.parent, inj.key);
        const ppath = slice(inj.path, -1);
        const point = getpath(store, ppath);
        const vstore = merge([{}, store], 1);
        vstore.$TOP = point;
        for (let term of terms) {
            let terrs = [];
            validate(point, term, {
                extra: vstore,
                errs: terrs,
                meta: inj.meta,
            });
            if (0 != size(terrs)) {
                inj.errs.push('AND:' + pathify(ppath) + S_VIZ + stringify(point) + ' fail:' + stringify(terms));
            }
        }
        const gkey = getelem(inj.path, -2);
        const gp = getelem(inj.nodes, -2);
        setprop(gp, gkey, point);
    }
};
const select_OR = (inj, _val, _ref, store) => {
    if (M_KEYPRE === inj.mode) {
        const terms = getprop(inj.parent, inj.key);
        const ppath = slice(inj.path, -1);
        const point = getpath(store, ppath);
        const vstore = merge([{}, store], 1);
        vstore.$TOP = point;
        for (let term of terms) {
            let terrs = [];
            validate(point, term, {
                extra: vstore,
                errs: terrs,
                meta: inj.meta,
            });
            if (0 === size(terrs)) {
                const gkey = getelem(inj.path, -2);
                const gp = getelem(inj.nodes, -2);
                setprop(gp, gkey, point);
                return;
            }
        }
        inj.errs.push('OR:' + pathify(ppath) + S_VIZ + stringify(point) + ' fail:' + stringify(terms));
    }
};
const select_NOT = (inj, _val, _ref, store) => {
    if (M_KEYPRE === inj.mode) {
        const term = getprop(inj.parent, inj.key);
        const ppath = slice(inj.path, -1);
        const point = getpath(store, ppath);
        const vstore = merge([{}, store], 1);
        vstore.$TOP = point;
        let terrs = [];
        validate(point, term, {
            extra: vstore,
            errs: terrs,
            meta: inj.meta,
        });
        if (0 == size(terrs)) {
            inj.errs.push('NOT:' + pathify(ppath) + S_VIZ + stringify(point) + ' fail:' + stringify(term));
        }
        const gkey = getelem(inj.path, -2);
        const gp = getelem(inj.nodes, -2);
        setprop(gp, gkey, point);
    }
};
const select_CMP = (inj, _val, ref, store) => {
    if (M_KEYPRE === inj.mode) {
        const term = getprop(inj.parent, inj.key);
        // const src = getprop(store, inj.base, store)
        const gkey = getelem(inj.path, -2);
        // const tval = getprop(src, gkey)
        const ppath = slice(inj.path, -1);
        const point = getpath(store, ppath);
        let pass = false;
        if ('$GT' === ref && point > term) {
            pass = true;
        }
        else if ('$LT' === ref && point < term) {
            pass = true;
        }
        else if ('$GTE' === ref && point >= term) {
            pass = true;
        }
        else if ('$LTE' === ref && point <= term) {
            pass = true;
        }
        else if ('$LIKE' === ref && stringify(point).match(RegExp(term))) {
            pass = true;
        }
        if (pass) {
            // Update spec to match found value so that _validate does not complain.
            const gp = getelem(inj.nodes, -2);
            setprop(gp, gkey, point);
        }
        else {
            inj.errs.push('CMP: ' + pathify(ppath) + S_VIZ + stringify(point) +
                ' fail:' + ref + ' ' + stringify(term));
        }
    }
    return NONE;
};
// Select children from a top-level object that match a MongoDB-style query.
// Supports $and, $or, and equality comparisons.
// For arrays, children are elements; for objects, children are values.
// TODO: swap arg order for consistency
function select(children, query) {
    if (!isnode(children)) {
        return [];
    }
    if (ismap(children)) {
        children = items(children, n => {
            setprop(n[1], S_DKEY, n[0]);
            return n[1];
        });
    }
    else {
        children = items(children, (n) => (setprop(n[1], S_DKEY, +n[0]), n[1]));
    }
    const results = [];
    const injdef = {
        errs: [],
        meta: { [S_BEXACT]: true },
        extra: {
            $AND: select_AND,
            $OR: select_OR,
            $NOT: select_NOT,
            $GT: select_CMP,
            $LT: select_CMP,
            $GTE: select_CMP,
            $LTE: select_CMP,
            $LIKE: select_CMP,
        }
    };
    const q = clone(query);
    walk(q, (_k, v) => {
        if (ismap(v)) {
            setprop(v, '`$OPEN`', getprop(v, '`$OPEN`', true));
        }
        return v;
    });
    for (const child of children) {
        injdef.errs = [];
        validate(child, clone(q), injdef);
        if (0 === size(injdef.errs)) {
            results.push(child);
        }
    }
    return results;
}
// Injection state used for recursive injection into JSON - like data structures.
class Injection {
    constructor(val, parent) {
        this.val = val;
        this.parent = parent;
        this.errs = [];
        this.dparent = NONE;
        this.dpath = [S_DTOP];
        this.mode = M_VAL;
        this.full = false;
        this.keyI = 0;
        this.keys = [S_DTOP];
        this.key = S_DTOP;
        this.path = [S_DTOP];
        this.nodes = [parent];
        this.handler = _injecthandler;
        this.base = S_DTOP;
        this.meta = {};
    }
    toString(prefix) {
        return 'INJ' + (null == prefix ? '' : S_FS + prefix) + S_CN +
            pad(pathify(this.path, 1)) +
            MODENAME[this.mode] + (this.full ? '/full' : '') + S_CN +
            'key=' + this.keyI + S_FS + this.key + S_FS + S_OS + this.keys + S_CS +
            '  p=' + stringify(this.parent, -1, 1) +
            '  m=' + stringify(this.meta, -1, 1) +
            '  d/' + pathify(this.dpath, 1) + '=' + stringify(this.dparent, -1, 1) +
            '  r=' + stringify(this.nodes[0]?.[S_DTOP], -1, 1);
    }
    descend() {
        this.meta.__d++;
        const parentkey = getelem(this.path, -2);
        // Resolve current node in store for local paths.
        if (NONE === this.dparent) {
            // Even if there's no data, dpath should continue to match path, so that
            // relative paths work properly.
            if (1 < size(this.dpath)) {
                this.dpath = flatten([this.dpath, parentkey]);
            }
        }
        else {
            // this.dparent is the containing node of the current store value.
            if (null != parentkey) {
                this.dparent = getprop(this.dparent, parentkey);
                let lastpart = getelem(this.dpath, -1);
                if (lastpart === '$:' + parentkey) {
                    this.dpath = slice(this.dpath, -1);
                }
                else {
                    this.dpath = flatten([this.dpath, parentkey]);
                }
            }
        }
        // TODO: is this needed?
        return this.dparent;
    }
    child(keyI, keys) {
        const key = strkey(keys[keyI]);
        const val = this.val;
        const cinj = new Injection(getprop(val, key), val);
        cinj.keyI = keyI;
        cinj.keys = keys;
        cinj.key = key;
        cinj.path = flatten([getdef(this.path, []), key]);
        cinj.nodes = flatten([getdef(this.nodes, []), [val]]);
        cinj.mode = this.mode;
        cinj.handler = this.handler;
        cinj.modify = this.modify;
        cinj.base = this.base;
        cinj.meta = this.meta;
        cinj.errs = this.errs;
        cinj.prior = this;
        cinj.dpath = flatten([this.dpath]);
        cinj.dparent = this.dparent;
        return cinj;
    }
    setval(val, ancestor) {
        let parent = NONE;
        if (null == ancestor || ancestor < 2) {
            parent = NONE === val ?
                this.parent = delprop(this.parent, this.key) :
                setprop(this.parent, this.key, val);
        }
        else {
            const aval = getelem(this.nodes, 0 - ancestor);
            const akey = getelem(this.path, 0 - ancestor);
            parent = NONE === val ?
                delprop(aval, akey) :
                setprop(aval, akey, val);
        }
        // console.log('SETVAL', val, this.key, this.parent)
        return parent;
    }
}
// Internal utilities
// ==================
// // Update all references to target in inj.nodes.
// function _updateAncestors(_inj: Injection, target: any, tkey: any, tval: any) {
//   // SetProp is sufficient in TypeScript as target reference remains consistent even for lists.
//   setprop(target, tkey, tval)
// }
// Build a type validation error message.
function _invalidTypeMsg(path, needtype, vt, v, _whence) {
    let vs = null == v ? 'no value' : stringify(v);
    return 'Expected ' +
        (1 < size(path) ? ('field ' + pathify(path, 1) + ' to be ') : '') +
        needtype + ', but found ' +
        (null != v ? typename(vt) + S_VIZ : '') + vs +
        // Uncomment to help debug validation errors.
        // ' [' + _whence + ']' +
        '.';
}
// Default inject handler for transforms. If the path resolves to a function,
// call the function passing the injection inj. This is how transforms operate.
const _injecthandler = (inj, val, ref, store) => {
    let out = val;
    const iscmd = isfunc(val) && (NONE === ref || ref.startsWith(S_DS));
    // Only call val function if it is a special command ($NAME format).
    // TODO: OR if meta.'$CALL'
    if (iscmd) {
        out = val(inj, val, ref, store);
    }
    // Update parent with value. Ensures references remain in node tree.
    else if (M_VAL === inj.mode && inj.full) {
        inj.setval(val);
    }
    return out;
};
const _validatehandler = (inj, val, ref, store) => {
    let out = val;
    const m = ref.match(R_META_PATH);
    const ismetapath = null != m;
    if (ismetapath) {
        if ('=' === m[2]) {
            inj.setval([S_BEXACT, val]);
        }
        else {
            inj.setval(val);
        }
        inj.keyI = -1;
        out = SKIP;
    }
    else {
        out = _injecthandler(inj, val, ref, store);
    }
    return out;
};
// Inject values from a data store into a string. Not a public utility - used by
// `inject`.  Inject are marked with `path` where path is resolved
// with getpath against the store or current (if defined)
// arguments. See `getpath`.  Custom injection handling can be
// provided by inj.handler (this is used for transform functions).
// The path can also have the special syntax $NAME999 where NAME is
// upper case letters only, and 999 is any digits, which are
// discarded. This syntax specifies the name of a transform, and
// optionally allows transforms to be ordered by alphanumeric sorting.
function _injectstr(val, store, inj) {
    // Can't inject into non-strings
    if (S_string !== typeof val || S_MT === val) {
        return S_MT;
    }
    let out = val;
    // Pattern examples: "`a.b.c`", "`$NAME`", "`$NAME1`"
    const m = val.match(R_INJECTION_FULL);
    // Full string of the val is an injection.
    if (m) {
        if (null != inj) {
            inj.full = true;
        }
        let pathref = m[1];
        // Special escapes inside injection.
        if (3 < size(pathref)) {
            pathref = pathref.replace(R_BT_ESCAPE, S_BT).replace(R_DS_ESCAPE, S_DS);
        }
        // Get the extracted path reference.
        out = getpath(store, pathref, inj);
    }
    else {
        // Check for injections within the string.
        const partial = (_m, ref) => {
            // Special escapes inside injection.
            if (3 < size(ref)) {
                ref = ref.replace(R_BT_ESCAPE, S_BT).replace(R_DS_ESCAPE, S_DS);
            }
            if (inj) {
                inj.full = false;
            }
            const found = getpath(store, ref, inj);
            // Ensure inject value is a string.
            return NONE === found ? S_MT : S_string === typeof found ? found : JSON.stringify(found);
        };
        out = val.replace(R_INJECTION_PARTIAL, partial);
        // Also call the inj handler on the entire string, providing the
        // option for custom injection.
        if (null != inj && isfunc(inj.handler)) {
            inj.full = true;
            out = inj.handler(inj, out, val, store);
        }
    }
    return out;
}
// Handler Utilities
// =================
const MODENAME = {
    [M_VAL]: 'val',
    [M_KEYPRE]: 'key:pre',
    [M_KEYPOST]: 'key:post',
};
exports.MODENAME = MODENAME;
const PLACEMENT = {
    [M_VAL]: 'value',
    [M_KEYPRE]: S_key,
    [M_KEYPOST]: S_key,
};
function checkPlacement(modes, ijname, parentTypes, inj) {
    if (0 === (modes & inj.mode)) {
        inj.errs.push('$' + ijname + ': invalid placement as ' + PLACEMENT[inj.mode] +
            ', expected: ' + join(items([M_KEYPRE, M_KEYPOST, M_VAL].filter(m => modes & m), (n) => PLACEMENT[n[1]]), ',') + '.');
        return false;
    }
    if (!isempty(parentTypes)) {
        const ptype = typify(inj.parent);
        if (0 === (parentTypes & ptype)) {
            inj.errs.push('$' + ijname + ': invalid placement in parent ' + typename(ptype) +
                ', expected: ' + typename(parentTypes) + '.');
            return false;
        }
    }
    return true;
}
// function injectorArgs(argTypes: number[], inj: Injection): any {
function injectorArgs(argTypes, args) {
    const numargs = size(argTypes);
    const found = new Array(1 + numargs);
    found[0] = NONE;
    for (let argI = 0; argI < numargs; argI++) {
        // const arg = inj.parent[1 + argI]
        const arg = args[argI];
        const argType = typify(arg);
        if (0 === (argTypes[argI] & argType)) {
            found[0] = 'invalid argument: ' + stringify(arg, 22) +
                ' (' + typename(argType) + ' at position ' + (1 + argI) +
                ') is not of type: ' + typename(argTypes[argI]) + '.';
            break;
        }
        found[1 + argI] = arg;
    }
    return found;
}
function injectChild(child, store, inj) {
    let cinj = inj;
    // Replace ['`$FORMAT`',...] with child
    if (null != inj.prior) {
        if (null != inj.prior.prior) {
            cinj = inj.prior.prior.child(inj.prior.keyI, inj.prior.keys);
            cinj.val = child;
            setprop(cinj.parent, inj.prior.key, child);
        }
        else {
            cinj = inj.prior.child(inj.keyI, inj.keys);
            cinj.val = child;
            setprop(cinj.parent, inj.key, child);
        }
    }
    // console.log('FORMAT-INJECT-CHILD', child)
    inject(child, store, cinj);
    return cinj;
}
class StructUtility {
    constructor() {
        this.clone = clone;
        this.delprop = delprop;
        this.escre = escre;
        this.escurl = escurl;
        this.filter = filter;
        this.flatten = flatten;
        this.getdef = getdef;
        this.getelem = getelem;
        this.getpath = getpath;
        this.getprop = getprop;
        this.haskey = haskey;
        this.inject = inject;
        this.isempty = isempty;
        this.isfunc = isfunc;
        this.iskey = iskey;
        this.islist = islist;
        this.ismap = ismap;
        this.isnode = isnode;
        this.items = items;
        this.join = join;
        this.jsonify = jsonify;
        this.keysof = keysof;
        this.merge = merge;
        this.pad = pad;
        this.pathify = pathify;
        this.select = select;
        this.setpath = setpath;
        this.setprop = setprop;
        this.size = size;
        this.slice = slice;
        this.strkey = strkey;
        this.stringify = stringify;
        this.transform = transform;
        this.typify = typify;
        this.typename = typename;
        this.validate = validate;
        this.walk = walk;
        this.SKIP = SKIP;
        this.DELETE = DELETE;
        this.jm = jm;
        this.jt = jt;
        this.tn = typename;
        this.T_any = T_any;
        this.T_noval = T_noval;
        this.T_boolean = T_boolean;
        this.T_decimal = T_decimal;
        this.T_integer = T_integer;
        this.T_number = T_number;
        this.T_string = T_string;
        this.T_function = T_function;
        this.T_symbol = T_symbol;
        this.T_null = T_null;
        this.T_list = T_list;
        this.T_map = T_map;
        this.T_instance = T_instance;
        this.T_scalar = T_scalar;
        this.T_node = T_node;
        this.checkPlacement = checkPlacement;
        this.injectorArgs = injectorArgs;
        this.injectChild = injectChild;
    }
}
exports.StructUtility = StructUtility;
//# sourceMappingURL=StructUtility.js.map