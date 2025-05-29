"use strict";
/* Copyright (c) 2025 Voxgig Ltd. MIT LICENSE. */
Object.defineProperty(exports, "__esModule", { value: true });
exports.StructUtility = void 0;
exports.clone = clone;
exports.delprop = delprop;
exports.escre = escre;
exports.escurl = escurl;
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
exports.joinurl = joinurl;
exports.keysof = keysof;
exports.merge = merge;
exports.pad = pad;
exports.pathify = pathify;
exports.setprop = setprop;
exports.size = size;
exports.slice = slice;
exports.strkey = strkey;
exports.stringify = stringify;
exports.transform = transform;
exports.typify = typify;
exports.validate = validate;
exports.walk = walk;
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
 * - joinurl: join parts of a url, merging forward slashes.
 *
 * This set of functions and supporting utilities is designed to work
 * uniformly across many languages, meaning that some code that may be
 * functionally redundant in specific languages is still retained to
 * keep the code human comparable.
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
// Mode value for inject step.
const S_MKEYPRE = 'key:pre';
const S_MKEYPOST = 'key:post';
const S_MVAL = 'val';
const S_MKEY = 'key';
// Special keys.
const S_BKEY = '`$KEY`';
const S_BANNO = '`$ANNO`';
const S_DKEY = '$KEY';
const S_DTOP = '$TOP';
const S_DERRS = '$ERRS';
const S_DSPEC = '$SPEC';
// General strings.
const S_array = 'array';
const S_base = 'base';
const S_boolean = 'boolean';
const S_function = 'function';
const S_number = 'number';
const S_object = 'object';
const S_string = 'string';
const S_null = 'null';
const S_key = 'key';
const S_MT = '';
const S_BT = '`';
const S_DS = '$';
const S_DT = '.';
const S_CN = ':';
const S_FS = '/';
const S_OS = '[';
const S_CS = ']';
const S_SP = ' ';
const S_KEY = 'KEY';
// The standard undefined value for this language.
const UNDEF = undefined;
// Private marker to indicate a skippable value.
const SKIP = {};
// Regular expression constants
const R_INTEGER_KEY = /^[-0-9]+$/; // Match integer keys (including <0).
const R_ESCAPE_REGEXP = /[.*+?^${}()|[\]\\]/g; // Chars that need escaping in regexp.
const R_TRAILING_SLASH = /\/+$/; // Trailing slashes in URLs.
const R_LEADING_TRAILING_SLASH = /([^\/])\/+/; // Multiple slashes in URL middle.
const R_LEADING_SLASH = /^\/+/; // Leading slashes in URLs.
const R_QUOTES = /"/g; // Double quotes for removal.
const R_DOT = /\./g; // Dots in path strings.
const R_FUNCTION_REF = /^`\$FUNCTION:([0-9]+)`$/; // Function reference in clone.
const R_META_PATH = /^([^$]+)\$([=~])(.+)$/; // Meta path syntax.
const R_DOUBLE_DOLLAR = /\$\$/g; // Double dollar escape sequence.
const R_TRANSFORM_NAME = /`\$([A-Z]+)`/g; // Transform command names.
const R_INJECTION_FULL = /^`(\$[A-Z]+|[^`]*)[0-9]*`$/; // Full string injection pattern.
const R_BT_ESCAPE = /\$BT/g; // Backtick escape sequence.
const R_DS_ESCAPE = /\$DS/g; // Dollar sign escape sequence.
const R_INJECTION_PARTIAL = /`([^`]+)`/g; // Partial string injection pattern.
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
// Extract part of an array or string into a new value, from the start point to the end point.
// If no end is specified, extract to the full length of the value. Negative arguments count
// from the end of the value. For numbers, perform min and max bounding, where start is
// inclusive, and end is *exclusive*.
function slice(val, start, end) {
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
                val = val.slice(start, end);
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
function pad(str, padding, padchar) {
    str = stringify(str);
    padding = null == padding ? 44 : padding;
    padchar = null == padchar ? S_SP : ((padchar + S_SP)[0]);
    return -1 < padding ? str.padEnd(padding, padchar) : str.padStart(0 - padding, padchar);
}
// Determine the type of a value as a string.
// Returns one of: 'null', 'string', 'number', 'boolean', 'function', 'array', 'object'
// Normalizes and simplifies JavaScript's type system for consistency.
function typify(value) {
    if (value === null || value === undefined) {
        return S_null;
    }
    const type = typeof value;
    if (Array.isArray(value)) {
        return S_array;
    }
    if (type === 'object') {
        return S_object;
    }
    return type;
}
// Get a list element. The key should be an integer, or a string
// that can parse to an integer only. Negative integers count from the end of the list.
function getelem(val, key, alt) {
    let out = UNDEF;
    if (UNDEF === val || UNDEF === key) {
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
    if (UNDEF === out) {
        return alt;
    }
    return out;
}
// Safely get a property of a node. Undefined arguments return undefined.
// If the key is not found, return the alternative value, if any.
function getprop(val, key, alt) {
    let out = alt;
    if (UNDEF === val || UNDEF === key) {
        return alt;
    }
    if (isnode(val)) {
        out = val[key];
    }
    if (UNDEF === out) {
        return alt;
    }
    return out;
}
// Convert different types of keys to string representation.
// String keys are returned as is.
// Number keys are converted to strings.
// Floats are truncated to integers.
// Booleans, objects, arrays, null, undefined all return empty string.
function strkey(key = UNDEF) {
    if (UNDEF === key) {
        return S_MT;
    }
    if (typeof key === S_string) {
        return key;
    }
    if (typeof key === S_boolean) {
        return S_MT;
    }
    if (typeof key === S_number) {
        return key % 1 === 0 ? String(key) : String(Math.floor(key));
    }
    return S_MT;
}
// Sorted keys of a map, or indexes of a list.
function keysof(val) {
    return !isnode(val) ? [] :
        ismap(val) ? Object.keys(val).sort() : val.map((_n, i) => S_MT + i);
}
// Value of property with name key in node val is defined.
function haskey(val, key) {
    return UNDEF !== getprop(val, key);
}
// List the sorted keys of a map or list as an array of tuples of the form [key, value].
// NOTE: Unlike keysof, list indexes are returned as numbers.
function items(val) {
    return keysof(val).map((k) => [k, val[k]]);
}
// Escape regular expression.
function escre(s) {
    s = null == s ? S_MT : s;
    return s.replace(R_ESCAPE_REGEXP, '\\$&');
}
// Escape URLs.
function escurl(s) {
    s = null == s ? S_MT : s;
    return encodeURIComponent(s);
}
// Concatenate url part strings, merging forward slashes as needed.
function joinurl(sarr) {
    return sarr
        .filter(s => null != s && S_MT !== s)
        .map((s, i) => 0 === i ? s.replace(R_TRAILING_SLASH, S_MT) :
        s.replace(R_LEADING_TRAILING_SLASH, '$1/')
            .replace(R_LEADING_SLASH, S_MT)
            .replace(R_TRAILING_SLASH, S_MT))
        .filter(s => S_MT !== s)
        .join(S_FS);
}
// Safely stringify a value for humans (NOT JSON!).
function stringify(val, maxlen, pretty) {
    let valstr = S_MT;
    pretty = !!pretty;
    if (UNDEF === val) {
        return pretty ? '<>' : valstr;
    }
    try {
        valstr = JSON.stringify(val, function (_key, val) {
            if (val !== null &&
                typeof val === "object" &&
                !Array.isArray(val)) {
                const sortedObj = {};
                for (const k of Object.keys(val).sort()) {
                    sortedObj[k] = val[k];
                }
                return sortedObj;
            }
            return val;
        });
    }
    catch (err) {
        valstr = S_MT + val;
    }
    valstr = S_string !== typeof valstr ? S_MT + valstr : valstr;
    valstr = valstr.replace(R_QUOTES, S_MT);
    if (null != maxlen && -1 < maxlen) {
        let js = valstr.substring(0, maxlen);
        valstr = maxlen < valstr.length ? (js.substring(0, maxlen - 3) + '...') : valstr;
    }
    if (pretty) {
        // Indicate deeper JSON levels with different terminal colors (simplistic wrt strings).
        let c = [81, 118, 213, 39, 208, 201, 45, 190, 129, 51, 160, 121, 226, 33, 207, 69]
            .map(n => `\x1b[38;5;${n}m`), r = '\x1b[0m', d = 0, o = c[0], t = o;
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
    let pathstr = UNDEF;
    let path = islist(val) ? val :
        S_string == typeof val ? [val] :
            S_number == typeof val ? [val] :
                UNDEF;
    const start = null == startin ? 0 : -1 < startin ? startin : 0;
    const end = null == endin ? 0 : -1 < endin ? endin : 0;
    if (UNDEF != path && 0 <= start) {
        path = slice(path, start, path.length - end);
        if (0 === path.length) {
            pathstr = '<root>';
        }
        else {
            pathstr = path
                // .filter((p: any, t: any) => (t = typeof p, S_string === t || S_number === t))
                .filter((p) => iskey(p))
                .map((p) => S_number === typeof p ? S_MT + Math.floor(p) :
                p.replace(R_DOT, S_MT))
                .join(S_DT);
        }
    }
    if (UNDEF === pathstr) {
        pathstr = '<unknown-path' + (UNDEF === val ? S_MT : S_CN + stringify(val, 47)) + '>';
    }
    return pathstr;
}
// Clone a JSON-like data structure.
// NOTE: function value references are copied, *not* cloned.
function clone(val) {
    const refs = [];
    const replacer = (_k, v) => S_function === typeof v ?
        (refs.push(v), '`$FUNCTION:' + (refs.length - 1) + '`') : v;
    const reviver = (_k, v, m) => S_string === typeof v ?
        (m = v.match(R_FUNCTION_REF), m ? refs[m[1]] : v) : v;
    return UNDEF === val ? UNDEF : JSON.parse(JSON.stringify(val, replacer), reviver);
}
// Safely delete a property from an object or array element. 
// Undefined arguments and invalid keys are ignored.
// Returns the (possibly modified) parent.
// For objects, the property is deleted using the delete operator.
// For arrays, the element at the index is removed and remaining elements are shifted down.
function delprop(parent, key) {
    if (!iskey(key)) {
        return parent;
    }
    if (ismap(parent)) {
        // key = S_MT + key
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
        if (0 <= keyI && keyI < parent.length) {
            for (let pI = keyI; pI < parent.length - 1; pI++) {
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
        // Set or append value at position keyI, or append if keyI out of bounds.
        if (0 <= keyI) {
            parent[parent.length < keyI ? parent.length : keyI] = val;
        }
        // Prepend value if keyI is negative
        else {
            parent.unshift(val);
        }
    }
    return parent;
}
// Walk a data structure depth first, applying a function to each value.
function walk(
// These arguments are the public interface.
val, apply, 
// These areguments are used for recursive state.
key, parent, path) {
    if (isnode(val)) {
        for (let [ckey, child] of items(val)) {
            setprop(val, ckey, walk(child, apply, ckey, val, [...(path || []), S_MT + ckey]));
        }
    }
    // Nodes are applied *after* their children.
    // For the root node, key and parent will be undefined.
    return apply(key, val, parent, path || []);
}
// Merge a list of values into each other. Later values have
// precedence.  Nodes override scalars. Node kinds (list or map)
// override each other, and do *not* merge.  The first element is
// modified.
function merge(val) {
    let out = UNDEF;
    // Handle edge cases.
    if (!islist(val)) {
        return val;
    }
    const list = val;
    const lenlist = list.length;
    if (0 === lenlist) {
        return UNDEF;
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
            // Nodes win, also over nodes of a different kind.
            if (!isnode(out) || (ismap(obj) && islist(out)) || (islist(obj) && ismap(out))) {
                out = obj;
            }
            else {
                // Node stack. walking down the current obj.
                let cur = [out];
                let cI = 0;
                function merger(key, val, parent, path) {
                    if (null == key) {
                        return val;
                    }
                    // Get the curent value at the current path in obj.
                    // NOTE: this is not exactly efficient, and should be optimised.
                    let lenpath = path.length;
                    cI = lenpath - 1;
                    if (UNDEF === cur[cI]) {
                        cur[cI] = getpath(out, slice(path, 0, lenpath - 1));
                    }
                    // Create node if needed.
                    if (!isnode(cur[cI])) {
                        cur[cI] = islist(parent) ? [] : {};
                    }
                    // Node child is just ahead of us on the stack, since
                    // `walk` traverses leaves before nodes.
                    if (isnode(val) && !isempty(val)) {
                        setprop(cur[cI], key, cur[cI + 1]);
                        cur[cI + 1] = UNDEF;
                    }
                    // Scalar child.
                    else {
                        setprop(cur[cI], key, val);
                    }
                    return val;
                }
                // Walk overriding node, creating paths in output as needed.
                walk(obj, merger);
            }
        }
    }
    return out;
}
function getpath(store, path, injdef) {
    // Operate on a string array.
    const parts = islist(path) ? path : S_string === typeof path ? path.split(S_DT) : UNDEF;
    if (UNDEF === parts) {
        return UNDEF;
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
            for (let pI = 0; UNDEF !== val && pI < parts.length; pI++) {
                let part = parts[pI];
                if (injdef && S_DKEY === part) {
                    part = getprop(injdef, S_key);
                }
                else if (injdef && part.startsWith('$GET:')) {
                    // $GET:path$ -> get store value, use as path part (string)
                    part = stringify(getpath(src, part.substring(5, part.length - 1)));
                }
                else if (injdef && part.startsWith('$REF:')) {
                    // $REF:refpath$ -> get spec value, use as path part (string)
                    part = stringify(getpath(getprop(store, S_DSPEC), part.substring(5, part.length - 1)));
                }
                else if (injdef && part.startsWith('$META:')) {
                    // $META:metapath$ -> get meta value, use as path part (string)
                    part = stringify(getpath(getprop(injdef, 'meta'), part.substring(6, part.length - 1)));
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
                            const fullpath = slice(dpath, 0 - ascends).concat(parts.slice(pI + 1));
                            if (ascends <= size(dpath)) {
                                val = getpath(store, fullpath);
                            }
                            else {
                                val = UNDEF;
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
    return val;
}
// Inject values from a data store into a node recursively, resolving
// paths against the store, or current if they are local. THe modify
// argument allows custom modification of the result.  The inj
// (Injection) argument is used to maintain recursive state.
function inject(val, store, injdef) {
    const valtype = typeof val;
    let inj = injdef;
    // Create state if at root of injection.  The input value is placed
    // inside a virtual parent holder to simplify edge cases.
    if (UNDEF === injdef || null == injdef.mode) {
        // Set up state assuming we are starting in the virtual parent.
        inj = new Injection(val, { [S_DTOP]: val });
        inj.dparent = store;
        inj.errs = getprop(store, S_DERRS, []);
        inj.meta.__d = 0;
        if (UNDEF !== injdef) {
            inj.modify = null == injdef.modify ? inj.modify : injdef.modify;
            inj.extra = null == injdef.extra ? inj.extra : injdef.extra;
            inj.meta = null == injdef.meta ? inj.meta : injdef.meta;
            inj.handler = null == injdef.handler ? inj.handler : injdef.handler;
        }
    }
    inj.descend();
    // Descend into node.
    if (isnode(val)) {
        // Keys are sorted alphanumerically to ensure determinism.
        // Injection transforms ($FOO) are processed *after* other keys.
        // NOTE: the optional digits suffix of the transform can thus be
        // used to order the transforms.
        let nodekeys = ismap(val) ? [
            ...Object.keys(val).filter(k => !k.includes(S_DS)).sort(),
            ...Object.keys(val).filter(k => k.includes(S_DS)).sort(),
        ] : val.map((_n, i) => i);
        // Each child key-value pair is processed in three injection phases:
        // 1. inj.mode='key:pre' - Key string is injected, returning a possibly altered key.
        // 2. inj.mode='val' - The child value is injected.
        // 3. inj.mode='key:post' - Key string is injected again, allowing child mutation.
        for (let nkI = 0; nkI < nodekeys.length; nkI++) {
            const childinj = inj.child(nkI, nodekeys);
            const nodekey = childinj.key;
            childinj.mode = S_MKEYPRE;
            // Peform the key:pre mode injection on the child key.
            const prekey = _injectstr(nodekey, store, childinj);
            // The injection may modify child processing.
            nkI = childinj.keyI;
            nodekeys = childinj.keys;
            // Prevent further processing by returning an undefined prekey
            if (UNDEF !== prekey) {
                childinj.val = getprop(val, prekey);
                childinj.mode = S_MVAL;
                // Perform the val mode injection on the child value.
                // NOTE: return value is not used.
                inject(childinj.val, store, childinj);
                // The injection may modify child processing.
                nkI = childinj.keyI;
                nodekeys = childinj.keys;
                // Peform the key:post mode injection on the child key.
                childinj.mode = S_MKEYPOST;
                _injectstr(nodekey, store, childinj);
                // The injection may modify child processing.
                nkI = childinj.keyI;
                nodekeys = childinj.keys;
            }
        }
    }
    // Inject paths into string scalars.
    else if (S_string === valtype) {
        inj.mode = S_MVAL;
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
    inj.val = val;
    // Original val reference may no longer be correct.
    // This return value is only used as the top level result.
    return getprop(inj.parent, S_DTOP);
}
// The transform_* functions are special command inject handlers (see Injector).
// Delete a key from a map or list.
const transform_DELETE = (inj) => {
    inj.setval(UNDEF);
    return UNDEF;
};
// Copy value from source data.
const transform_COPY = (inj, _val) => {
    const { mode, key } = inj;
    let out = key;
    if (!mode.startsWith(S_MKEY)) {
        out = getprop(inj.dparent, key);
        inj.setval(out);
    }
    return out;
};
// As a value, inject the key of the parent node.
// As a key, defined the name of the key property in the source object.
const transform_KEY = (inj) => {
    const { mode, path, parent } = inj;
    // Do nothing in val mode.
    if (S_MVAL !== mode) {
        return UNDEF;
    }
    // Key is defined by $KEY meta property.
    const keyspec = getprop(parent, S_BKEY);
    if (UNDEF !== keyspec) {
        delprop(parent, S_BKEY);
        return getprop(inj.dparent, keyspec);
    }
    // Key is defined within general purpose $META object.
    return getprop(getprop(parent, S_BANNO), S_KEY, getprop(path, path.length - 2));
};
// Annotatea node.  Does nothing itself, just used by
// other injectors, and is removed when called.
const transform_ANNO = (inj) => {
    const { parent } = inj;
    delprop(parent, S_BANNO);
    return UNDEF;
};
// Merge a list of objects into the current object. 
// Must be a key in an object. The value is merged over the current object.
// If the value is an array, the elements are first merged using `merge`. 
// If the value is the empty string, merge the top level store.
// Format: { '`$MERGE`': '`source-path`' | ['`source-paths`', ...] }
const transform_MERGE = (inj) => {
    const { mode, key, parent } = inj;
    // Ensures $MERGE is removed from parent list (val mode).
    let out = UNDEF;
    if (S_MKEYPRE === mode) {
        out = key;
    }
    // Operate after child values have been transformed.
    else if (S_MKEYPOST === mode) {
        out = key;
        let args = getprop(parent, key);
        args = Array.isArray(args) ? args : [args];
        // Remove the $MERGE command from a parent map.
        inj.setval(UNDEF);
        // Literals in the parent have precedence, but we still merge onto
        // the parent object, so that node tree references are not changed.
        const mergelist = [parent, ...args, clone(parent)];
        merge(mergelist);
        // return key
    }
    return out;
};
// Convert a node to a list.
// Format: ['`$EACH`', '`source-path-of-node`', child-template]
const transform_EACH = (inj, _val, _ref, store) => {
    // Remove arguments to avoid spurious processing.
    if (null != inj.keys) {
        inj.keys.length = 1;
    }
    if (S_MVAL !== inj.mode) {
        return UNDEF;
    }
    // Get arguments: ['`$EACH`', 'source-path', child-template].
    const srcpath = getprop(inj.parent, 1);
    const child = clone(getprop(inj.parent, 2));
    // Source data.
    const srcstore = getprop(store, inj.base, store);
    const src = getpath(srcstore, srcpath, inj);
    // Create parallel data structures:
    // source entries :: child templates
    let tcur = [];
    let tval = [];
    const tkey = inj.path[inj.path.length - 2];
    const target = inj.nodes[inj.nodes.length - 2] || inj.nodes[inj.nodes.length - 1];
    // Create clones of the child template for each value of the current soruce.
    if (islist(src)) {
        tval = src.map(() => clone(child));
    }
    else if (ismap(src)) {
        tval = Object.entries(src).map(n => ({
            ...clone(child),
            // Make a note of the key for $KEY transforms.
            [S_BANNO]: { KEY: n[0] }
        }));
    }
    let rval = [];
    if (0 < size(tval)) {
        tcur = null == src ? UNDEF : Object.values(src);
        const ckey = getelem(inj.path, -2);
        const tpath = slice(inj.path, -1);
        const dpath = [S_DTOP, ...srcpath.split(S_DT), '$:' + ckey];
        // Parent structure.
        // const ckey = getelem(cpath, -1)
        tcur = { [ckey]: tcur };
        if (1 < tpath.length) {
            const pkey = getelem(inj.path, -3, S_DTOP);
            // const pkey = getelem(cpath, -2, S_DTOP)
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
    _updateAncestors(inj, target, tkey, rval);
    // Prevent callee from damaging first list entry (since we are in `val` mode).
    return rval[0];
};
// Convert a node to a map.
// Format: { '`$PACK`':['`source-path`', child-template]}
const transform_PACK = (inj, _val, _ref, store) => {
    const { mode, key, path, parent, nodes } = inj;
    // Defensive context checks.
    if (S_MKEYPRE !== mode || S_string !== typeof key || null == path || null == nodes) {
        return UNDEF;
    }
    // Get arguments.
    const args = parent[key];
    const srcpath = args[0]; // Path to source data.
    const child = clone(args[1]); // Child template.
    // Find key and target node.
    const keyprop = child[S_BKEY];
    const tkey = getelem(path, -2);
    const target = nodes[path.length - 2] || nodes[path.length - 1];
    // Source data
    const srcstore = getprop(store, inj.base, store);
    let src = getpath(srcstore, srcpath, inj);
    // Prepare source as a list.
    src = islist(src) ? src :
        ismap(src) ? Object.entries(src)
            .reduce((a, n) => (n[1][S_BANNO] = { KEY: n[0] }, a.push(n[1]), a), []) :
            UNDEF;
    if (null == src) {
        return UNDEF;
    }
    // Get key if specified.
    let childkey = getprop(child, S_BKEY);
    let keyname = UNDEF === childkey ? keyprop : childkey;
    delprop(child, S_BKEY);
    // Build parallel target object.
    let tval = {};
    tval = src.reduce((a, n) => {
        let kn = getprop(n, keyname);
        setprop(a, kn, clone(child));
        const nchild = getprop(a, kn);
        const mval = getprop(n, S_BANNO);
        if (UNDEF === mval) {
            delprop(nchild, S_BANNO);
        }
        else {
            setprop(nchild, S_BANNO, mval);
        }
        return a;
    }, tval);
    let rval = {};
    if (0 < size(tval)) {
        // Build parallel source object.
        let tcur = {};
        src.reduce((a, n) => {
            let kn = getprop(n, keyname);
            setprop(a, kn, n);
            return a;
        }, tcur);
        const tpath = slice(inj.path, -1);
        const ckey = getelem(inj.path, -2);
        const dpath = [S_DTOP, ...srcpath.split(S_DT), '$:' + ckey];
        tcur = { [ckey]: tcur };
        if (1 < tpath.length) {
            const pkey = getelem(inj.path, -3, S_DTOP);
            tcur = { [pkey]: tcur };
            dpath.push('$:' + pkey);
        }
        const tinj = inj.child(0, [ckey]);
        tinj.path = tpath;
        tinj.nodes = slice(inj.nodes, -1);
        // tinj.parent = tcur
        tinj.parent = getelem(tinj.nodes, -1);
        tinj.val = tval;
        tinj.dpath = dpath;
        tinj.dparent = tcur;
        inject(tval, store, tinj);
        rval = tinj.val;
    }
    _updateAncestors(inj, target, tkey, rval);
    // Drop transform key.
    return UNDEF;
};
// TODO: not found ref should removed key (setprop UNDEF)
// Reference original spec (enables recursice transformations)
// Format: ['`$REF`', '`spec-path`']
const transform_REF = (inj, val, _ref, store) => {
    const { nodes } = inj;
    if (S_MVAL !== inj.mode) {
        return UNDEF;
    }
    // Get arguments: ['`$REF`', 'ref-path'].
    const refpath = getprop(inj.parent, 1);
    inj.keyI = inj.keys.length;
    // Spec reference.
    const spec = getprop(store, S_DSPEC)();
    const ref = getpath(spec, refpath, {
        // TODO: test relative refs
        dpath: inj.path.slice(1),
        dparent: getpath(spec, inj.path.slice(1))
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
    let rval = UNDEF;
    if (!hasSubRef || UNDEF !== tval) {
        const tinj = inj.child(0, [getelem(tpath, -1)]);
        tinj.path = tpath;
        tinj.nodes = slice(inj.nodes, -1);
        tinj.parent = getelem(nodes, -2);
        tinj.val = tref;
        tinj.dpath = [...cpath];
        tinj.dparent = tcur;
        inject(tref, store, tinj);
        rval = tinj.val;
    }
    else {
        rval = UNDEF;
    }
    const grandparent = inj.setval(rval, 2);
    if (islist(grandparent) && inj.prior) {
        inj.prior.keyI--;
    }
    return val;
};
// Transform data using spec.
// Only operates on static JSON-like data.
// Arrays are treated as if they are objects with indices as keys.
function transform(data, // Source data to transform into new data (original not mutated)
spec, // Transform specification; output follows this shape
// extra?: any, // Additional store of data and transforms.
// modify?: Modify // Optionally modify individual values.
injdef) {
    // Clone the spec so that the clone can be modified in place as the transform result.
    const origspec = spec;
    spec = clone(origspec);
    const extra = injdef?.extra;
    // const modify = injdef?.modify
    const extraTransforms = {};
    const extraData = null == extra ? UNDEF : items(extra)
        .reduce((a, n) => (n[0].startsWith(S_DS) ? extraTransforms[n[0]] = n[1] : (a[n[0]] = n[1]), a), {});
    const dataClone = merge([
        isempty(extraData) ? UNDEF : clone(extraData),
        clone(data),
    ]);
    // Define a top level store that provides transform operations.
    const store = {
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
        // Custom extra transforms, if any.
        ...extraTransforms,
    };
    // const out = inject(spec, store, { modify, extra })
    const out = inject(spec, store, injdef);
    return out;
}
// A required string value. NOTE: Rejects empty strings.
const validate_STRING = (inj) => {
    let out = getprop(inj.dparent, inj.key);
    const t = typify(out);
    if (S_string !== t) {
        let msg = _invalidTypeMsg(inj.path, S_string, t, out, 'V1010');
        inj.errs.push(msg);
        return UNDEF;
    }
    if (S_MT === out) {
        let msg = 'Empty string at ' + pathify(inj.path, 1);
        inj.errs.push(msg);
        return UNDEF;
    }
    return out;
};
// A required number value (int or float).
const validate_NUMBER = (inj) => {
    let out = getprop(inj.dparent, inj.key);
    const t = typify(out);
    if (S_number !== t) {
        inj.errs.push(_invalidTypeMsg(inj.path, S_number, t, out, 'V1020'));
        return UNDEF;
    }
    return out;
};
// A required boolean value.
const validate_BOOLEAN = (inj) => {
    let out = getprop(inj.dparent, inj.key);
    const t = typify(out);
    if (S_boolean !== t) {
        inj.errs.push(_invalidTypeMsg(inj.path, S_boolean, t, out, 'V1030'));
        return UNDEF;
    }
    return out;
};
// A required object (map) value (contents not validated).
const validate_OBJECT = (inj) => {
    let out = getprop(inj.dparent, inj.key);
    const t = typify(out);
    if (t !== S_object) {
        inj.errs.push(_invalidTypeMsg(inj.path, S_object, t, out, 'V1040'));
        return UNDEF;
    }
    return out;
};
// A required array (list) value (contents not validated).
const validate_ARRAY = (inj) => {
    let out = getprop(inj.dparent, inj.key);
    const t = typify(out);
    if (t !== S_array) {
        inj.errs.push(_invalidTypeMsg(inj.path, S_array, t, out, 'V1050'));
        return UNDEF;
    }
    return out;
};
// A required function value.
const validate_FUNCTION = (inj) => {
    let out = getprop(inj.dparent, inj.key);
    const t = typify(out);
    if (S_function !== t) {
        inj.errs.push(_invalidTypeMsg(inj.path, S_function, t, out, 'V1060'));
        return UNDEF;
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
    if (S_MKEYPRE === mode) {
        const childtm = getprop(parent, key);
        // Get corresponding current object.
        const pkey = getprop(path, path.length - 2);
        let tval = getprop(inj.dparent, pkey);
        if (UNDEF == tval) {
            tval = {};
        }
        else if (!ismap(tval)) {
            inj.errs.push(_invalidTypeMsg(slice(inj.path, -1), S_object, typify(tval), tval), 'V0220');
            return UNDEF;
        }
        const ckeys = keysof(tval);
        for (let ckey of ckeys) {
            setprop(parent, ckey, clone(childtm));
            // NOTE: modifying inj! This extends the child value loop in inject.
            keys.push(ckey);
        }
        // Remove $CHILD to cleanup ouput.
        inj.setval(UNDEF);
        return UNDEF;
    }
    // List syntax.
    if (S_MVAL === mode) {
        if (!islist(parent)) {
            // $CHILD was not inside a list.
            inj.errs.push('Invalid $CHILD as value');
            return UNDEF;
        }
        const childtm = getprop(parent, 1);
        if (UNDEF === inj.dparent) {
            // Empty list as default.
            parent.length = 0;
            return UNDEF;
        }
        if (!islist(inj.dparent)) {
            const msg = _invalidTypeMsg(slice(inj.path, -1), S_array, typify(inj.dparent), inj.dparent, 'V0230');
            inj.errs.push(msg);
            inj.keyI = parent.length;
            return inj.dparent;
        }
        // Clone children abd reset inj key index.
        // The inject child loop will now iterate over the cloned children,
        // validating them againt the current list values.
        inj.dparent.map((_n, i) => parent[i] = clone(childtm));
        parent.length = inj.dparent.length;
        inj.keyI = 0;
        const out = getprop(inj.dparent, 0);
        return out;
    }
    return UNDEF;
};
// Match at least one of the specified shapes.
// Syntax: ['`$ONE`', alt0, alt1, ...]okI
const validate_ONE = (inj, _val, _ref, store) => {
    const { mode, parent, keyI } = inj;
    // Only operate in val mode, since parent is a list.
    if (S_MVAL === mode) {
        if (!islist(parent) || 0 !== keyI) {
            inj.errs.push('The $ONE validator at field ' +
                pathify(inj.path, 1, 1) +
                ' must be the first element of an array.');
            return;
        }
        inj.keyI = inj.keys.length;
        // Clean up structure, replacing [$ONE, ...] with current
        inj.setval(inj.dparent, 2);
        inj.path = slice(inj.path, -1);
        inj.key = getelem(inj.path, -1);
        let tvals = slice(parent, 1);
        if (0 === tvals.length) {
            inj.errs.push('The $ONE validator at field ' +
                pathify(inj.path, 1, 1) +
                ' must have at least one argument.');
            return;
        }
        // See if we can find a match.
        for (let tval of tvals) {
            // If match, then errs.length = 0
            let terrs = [];
            const vstore = { ...store };
            vstore.$TOP = inj.dparent;
            const vcurrent = validate(inj.dparent, tval, {
                extra: vstore,
                errs: terrs,
                meta: inj.meta,
            });
            inj.setval(vcurrent, -2);
            // Accept current value if there was a match
            if (0 === terrs.length) {
                return;
            }
        }
        // There was no match.
        const valdesc = tvals
            .map((v) => stringify(v))
            .join(', ')
            .replace(R_TRANSFORM_NAME, (_m, p1) => p1.toLowerCase());
        inj.errs.push(_invalidTypeMsg(inj.path, (1 < tvals.length ? 'one of ' : '') + valdesc, typify(inj.dparent), inj.dparent, 'V0210'));
    }
};
const validate_EXACT = (inj) => {
    const { mode, parent, key, keyI } = inj;
    // Only operate in val mode, since parent is a list.
    if (S_MVAL === mode) {
        if (!islist(parent) || 0 !== keyI) {
            inj.errs.push('The $EXACT validator at field ' +
                pathify(inj.path, 1, 1) +
                ' must be the first element of an array.');
            return;
        }
        inj.keyI = inj.keys.length;
        // Clean up structure, replacing [$EXACT, ...] with current data parent
        inj.setval(inj.dparent, 2);
        inj.path = slice(inj.path, 0, inj.path.length - 1);
        inj.key = getelem(inj.path, -1);
        let tvals = slice(parent, 1);
        if (0 === tvals.length) {
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
        const valdesc = tvals
            .map((v) => stringify(v))
            .join(', ')
            .replace(R_TRANSFORM_NAME, (_m, p1) => p1.toLowerCase());
        inj.errs.push(_invalidTypeMsg(inj.path, (1 < inj.path.length ? '' : 'value ') +
            'exactly equal to ' + (1 === tvals.length ? '' : 'one of ') + valdesc, typify(inj.dparent), inj.dparent, 'V0110'));
    }
    else {
        delprop(parent, key);
    }
};
// This is the "modify" argument to inject. Use this to perform
// generic validation. Runs *after* any special commands.
const _validation = (pval, key, parent, inj) => {
    if (UNDEF === inj) {
        return;
    }
    if (SKIP === pval) {
        return;
    }
    // Current val to verify.
    const cval = getprop(inj.dparent, key);
    if (UNDEF === cval || UNDEF === inj) {
        return;
    }
    const ptype = typify(pval);
    // Delete any special commands remaining.
    if (S_string === ptype && pval.includes(S_DS)) {
        return;
    }
    const ctype = typify(cval);
    // Type mismatch.
    if (ptype !== ctype && UNDEF !== pval) {
        inj.errs.push(_invalidTypeMsg(inj.path, ptype, ctype, cval, 'V0010'));
        return;
    }
    if (ismap(cval)) {
        if (!ismap(pval)) {
            inj.errs.push(_invalidTypeMsg(inj.path, ptype, ctype, cval, 'V0020'));
            return;
        }
        const ckeys = keysof(cval);
        const pkeys = keysof(pval);
        // Empty spec object {} means object can be open (any keys).
        if (0 < pkeys.length && true !== getprop(pval, '`$OPEN`')) {
            const badkeys = [];
            for (let ckey of ckeys) {
                if (!haskey(pval, ckey)) {
                    badkeys.push(ckey);
                }
            }
            // Closed object, so reject extra keys not in shape.
            if (0 < badkeys.length) {
                const msg = 'Unexpected keys at field ' + pathify(inj.path, 1) + ': ' + badkeys.join(', ');
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
            inj.errs.push(_invalidTypeMsg(inj.path, ptype, ctype, cval, 'V0030'));
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
    const store = {
        // Remove the transform commands.
        $DELETE: null,
        $COPY: null,
        $KEY: null,
        $META: null,
        $MERGE: null,
        $EACH: null,
        $PACK: null,
        $STRING: validate_STRING,
        $NUMBER: validate_NUMBER,
        $BOOLEAN: validate_BOOLEAN,
        $OBJECT: validate_OBJECT,
        $ARRAY: validate_ARRAY,
        $FUNCTION: validate_FUNCTION,
        $ANY: validate_ANY,
        $CHILD: validate_CHILD,
        $ONE: validate_ONE,
        $EXACT: validate_EXACT,
        ...(extra || {}),
        // A special top level value to collect errors.
        // NOTE: collecterrs paramter always wins.
        $ERRS: errs,
    };
    const out = transform(data, spec, {
        meta: injdef?.meta,
        extra: store,
        modify: _validation,
        handler: _validatehandler
    });
    const generr = (0 < errs.length && !collect);
    if (generr) {
        throw new Error('Invalid data: ' + errs.join(' | '));
    }
    return out;
}
// Injection state used for recursive injection into JSON - like data structures.
class Injection {
    constructor(val, parent) {
        this.val = val;
        this.parent = parent;
        this.errs = [];
        this.dparent = UNDEF;
        this.dpath = [S_DTOP];
        this.mode = S_MVAL;
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
            this.mode + (this.full ? '/full' : '') + S_CN +
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
        if (UNDEF === this.dparent) {
            // Even if there's no data, dpath should continue to match path, so that
            // relative paths work properly.
            if (1 < this.dpath.length) {
                this.dpath = [...this.dpath, parentkey];
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
                    this.dpath = [...this.dpath, parentkey];
                }
            }
        }
        return this.dparent;
    }
    child(keyI, keys) {
        const key = strkey(keys[keyI]);
        const val = this.val;
        const cinj = new Injection(getprop(val, key), val);
        cinj.keyI = keyI;
        cinj.keys = keys;
        cinj.key = key;
        cinj.path = [...(this.path || []), key];
        cinj.nodes = [...(this.nodes || []), val];
        cinj.mode = this.mode;
        cinj.handler = this.handler;
        cinj.modify = this.modify;
        cinj.base = this.base;
        cinj.meta = this.meta;
        cinj.errs = this.errs;
        cinj.prior = this;
        cinj.dpath = [...this.dpath];
        cinj.dparent = this.dparent;
        return cinj;
    }
    setval(val, ancestor) {
        if (null == ancestor || ancestor < 2) {
            return UNDEF === val ?
                delprop(this.parent, this.key) :
                setprop(this.parent, this.key, val);
        }
        else {
            const aval = getelem(this.nodes, 0 - ancestor);
            const akey = getelem(this.path, 0 - ancestor);
            return UNDEF === val ?
                delprop(aval, akey) :
                setprop(aval, akey, val);
        }
    }
}
// Internal utilities
// ==================
// Update all references to target in inj.nodes.
function _updateAncestors(_inj, target, tkey, tval) {
    // SetProp is sufficient in TypeScript as target reference remains consistent even for lists.
    setprop(target, tkey, tval);
}
// Build a type validation error message.
function _invalidTypeMsg(path, needtype, vt, v, _whence) {
    let vs = null == v ? 'no value' : stringify(v);
    return 'Expected ' +
        (1 < path.length ? ('field ' + pathify(path, 1) + ' to be ') : '') +
        needtype + ', but found ' +
        (null != v ? vt + ': ' : '') + vs +
        // Uncomment to help debug validation errors.
        // ' [' + _whence + ']' +
        '.';
}
// Default inject handler for transforms. If the path resolves to a function,
// call the function passing the injection inj. This is how transforms operate.
const _injecthandler = (inj, val, ref, store) => {
    let out = val;
    const iscmd = isfunc(val) && (UNDEF === ref || ref.startsWith(S_DS));
    // Only call val function if it is a special command ($NAME format).
    if (iscmd) {
        out = val(inj, val, ref, store);
    }
    // Update parent with value. Ensures references remain in node tree.
    else if (S_MVAL === inj.mode && inj.full) {
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
            inj.setval(['`$EXACT`', val]);
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
        pathref = 3 < pathref.length ?
            pathref.replace(R_BT_ESCAPE, S_BT).replace(R_DS_ESCAPE, S_DS) :
            pathref;
        // Get the extracted path reference.
        out = getpath(store, pathref, inj);
    }
    else {
        // Check for injections within the string.
        const partial = (_m, ref) => {
            // Special escapes inside injection.
            ref = 3 < ref.length ? ref.replace(R_BT_ESCAPE, S_BT).replace(R_DS_ESCAPE, S_DS) : ref;
            if (inj) {
                inj.full = false;
            }
            const found = getpath(store, ref, inj);
            // Ensure inject value is a string.
            return UNDEF === found ? S_MT : S_string === typeof found ? found : JSON.stringify(found);
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
class StructUtility {
    constructor() {
        this.clone = clone;
        this.delprop = delprop;
        this.escre = escre;
        this.escurl = escurl;
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
        this.joinurl = joinurl;
        this.keysof = keysof;
        this.merge = merge;
        this.pad = pad;
        this.pathify = pathify;
        this.setprop = setprop;
        this.size = size;
        this.slice = slice;
        this.strkey = strkey;
        this.stringify = stringify;
        this.transform = transform;
        this.typify = typify;
        this.validate = validate;
        this.walk = walk;
    }
}
exports.StructUtility = StructUtility;
//# sourceMappingURL=struct.js.map