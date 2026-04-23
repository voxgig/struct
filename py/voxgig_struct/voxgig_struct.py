# Copyright (c) 2025 Voxgig Ltd. MIT LICENSE.
#
# Voxgig Struct
# =============
#
# Utility functions to manipulate in-memory JSON-like data structures.
# This Python version follows the same design and logic as the original
# TypeScript version, using "by-example" transformation of data.
#
# Main utilities
# - getpath: get the value at a key path deep inside an object.
# - merge: merge multiple nodes, overriding values in earlier nodes.
# - walk: walk a node tree, applying a function at each node and leaf.
# - inject: inject values from a data store into a new data structure.
# - transform: transform a data structure to an example structure.
# - validate: validate a data structure against a shape specification.
#
# Minor utilities
# - isnode, islist, ismap, iskey, isfunc: identify value kinds.
# - isempty: undefined values, or empty nodes.
# - keysof: sorted list of node keys (ascending).
# - haskey: true if key value is defined.
# - clone: create a copy of a JSON-like data structure.
# - items: list entries of a map or list as [key, value] pairs.
# - getprop: safely get a property value by key.
# - getelem: safely get a list element value by key/index.
# - setprop: safely set a property value by key.
# - size: get the size of a value (length for lists, strings; count for maps).
# - slice: return a part of a list or other value.
# - pad: pad a string to a specified length.
# - stringify: human-friendly string version of a value.
# - escre: escape a regular expresion string.
# - escurl: escape a url.
# - joinurl: join parts of a url, merging forward slashes.


from typing import *
from datetime import datetime
import urllib.parse
import json
import re
import math
import inspect

# Regex patterns for path processing
R_META_PATH = re.compile(r'^([^$]+)\$([=~])(.+)$')  # Meta path syntax.
R_DOUBLE_DOLLAR = re.compile(r'\$\$')               # Double dollar escape sequence.

# Mode value for inject step.
S_MKEYPRE =  'key:pre'
S_MKEYPOST =  'key:post'
S_MVAL =  'val'
S_MKEY =  'key'

M_KEYPRE = 1
M_KEYPOST = 2
M_VAL = 4
_MODE_TO_NUM = {S_MKEYPRE: M_KEYPRE, S_MKEYPOST: M_KEYPOST, S_MVAL: M_VAL}
_PLACEMENT = {M_VAL: 'value', M_KEYPRE: S_MKEY, M_KEYPOST: S_MKEY}
MODENAME = {M_VAL: 'val', M_KEYPRE: 'key:pre', M_KEYPOST: 'key:post'}

# Special keys.
S_DKEY =  '$KEY'
S_BANNO =  '`$ANNO`'
S_DTOP =  '$TOP'
S_DERRS =  '$ERRS'
S_DSPEC =  '$SPEC'
S_BMETA =  'meta'
S_BEXACT =  '`$EXACT`'
S_BVAL = '`$VAL`'
S_BKEY = '`$KEY`'

# General strings.
S_array =  'array'
S_integer = 'integer'
S_decimal = 'decimal'
S_map = 'map'
S_list = 'list'
S_nil = 'nil'
S_instance = 'instance'
S_node = 'node'
S_scalar = 'scalar'
S_any = 'any'
S_base =  'base'
S_boolean =  'boolean'
S_function =  'function'
S_number =  'number'
S_object =  'object'
S_string =  'string'
S_null =  'null'
S_key =  'key'
S_parent =  'parent'
S_MT =  ''
S_BT =  '`'
S_DS =  '$'
S_DT =  '.'
S_CM =  ','
S_CN =  ':'
S_FS =  '/'
S_KEY =  'KEY'


# Type bit flags (mirroring TypeScript)
_t = 31
T_any = (1 << _t) - 1
T_noval = 1 << (_t := _t - 1)
T_boolean = 1 << (_t := _t - 1)
T_decimal = 1 << (_t := _t - 1)
T_integer = 1 << (_t := _t - 1)
T_number = 1 << (_t := _t - 1)
T_string = 1 << (_t := _t - 1)
T_function = 1 << (_t := _t - 1)
T_symbol = 1 << (_t := _t - 1)
T_null = 1 << (_t := _t - 1)
_t -= 7
T_list = 1 << (_t := _t - 1)
T_map = 1 << (_t := _t - 1)
T_instance = 1 << (_t := _t - 1)
_t -= 4
T_scalar = 1 << (_t := _t - 1)
T_node = 1 << (_t := _t - 1)

TYPENAME = [
    S_any,
    S_nil,
    S_boolean,
    S_decimal,
    S_integer,
    S_number,
    S_string,
    S_function,
    'symbol',
    S_null,
    '', '', '',
    '', '', '', '',
    S_list,
    S_map,
    S_instance,
    '', '', '', '',
    S_scalar,
    S_node,
]

S_VIZ = ': '

# The standard undefined value for this language.
UNDEF = None
SKIP = {'`$SKIP`': True}
DELETE = {'`$DELETE`': True}


class Injection:
    """
    Injection state used for recursive injection into JSON-like data structures.
    """
    def __init__(
        self,
        mode: str,                    # Injection mode: key:pre, val, key:post.
        full: bool,                   # Transform escape was full key name.
        keyI: int,                    # Index of parent key in list of parent keys.
        keys: List[str],              # List of parent keys.
        key: str,                     # Current parent key.
        val: Any,                     # Current child value.
        parent: Any,                  # Current parent (in transform specification).
        path: List[str],              # Path to current node.
        nodes: List[Any],             # Stack of ancestor nodes
        handler: Any,                 # Custom handler for injections.
        errs: List[Any] = None,       # Error collector.
        meta: Dict[str, Any] = None,  # Custom meta data.
        base: Optional[str] = None,   # Base key for data in store, if any. 
        modify: Optional[Any] = None, # Modify injection output.
        extra: Optional[Any] = None   # Extra data for injection.
    ) -> None:
        self.mode = mode
        self.full = full
        self.keyI = keyI
        self.keys = keys
        self.key = key
        self.val = val
        self.parent = parent
        self.path = path
        self.nodes = nodes
        self.handler = handler
        self.errs = errs
        self.meta = meta or {}
        self.base = base
        self.modify = modify
        self.extra = extra
        self.prior = None
        self.dparent = UNDEF
        self.dpath = [S_DTOP]
        self.root = None  # Virtual root parent; set at top level so we can return it after transforms

    def descend(self):
        if '__d' not in self.meta:
            self.meta['__d'] = 0
        self.meta['__d'] += 1

        parentkey = getelem(self.path, -2)

        if self.dparent is UNDEF:
            if 1 < size(self.dpath):
                self.dpath = self.dpath + [parentkey]
        else:
            if parentkey is not None:
                self.dparent = getprop(self.dparent, parentkey)

                lastpart = getelem(self.dpath, -1)
                if lastpart == '$:' + str(parentkey):
                    self.dpath = slice(self.dpath, -1)
                else:
                    self.dpath = self.dpath + [parentkey]

        return self.dparent

    def child(self, keyI: int, keys: List[str]) -> 'Injection':
        """Create a child state object with the given key index and keys."""
        key = strkey(keys[keyI])
        val = self.val
        
        cinj = Injection(
            mode=self.mode,
            full=self.full,
            keyI=keyI,
            keys=keys,
            key=key,
            val=getprop(val, key),
            parent=val,
            path=self.path + [key],
            nodes=self.nodes + [val],
            handler=self.handler,
            errs=self.errs,
            meta=self.meta,
            base=self.base,
            modify=self.modify
        )
        cinj.prior = self
        cinj.dpath = self.dpath[:]
        cinj.dparent = self.dparent
        cinj.extra = self.extra  # Preserve extra (contains transform functions)
        cinj.root = getattr(self, 'root', None)
        
        return cinj

    def setval(self, val: Any, ancestor: Optional[int] = None) -> Any:
        """Set the value in the parent node at the specified ancestor level."""
        if ancestor is None or ancestor < 2:
            return setprop(self.parent, self.key, val)
        else:
            return setprop(getelem(self.nodes, 0 - ancestor), getelem(self.path, 0 - ancestor), val)


def getdef(val, alt):
    "Get a defined value. Returns alt if val is undefined."
    if val is UNDEF or val is None:
        return alt
    return val


def isnode(val: Any = UNDEF) -> bool:
    "Value is a node - defined, and a map (hash) or list (array)."
    return isinstance(val, (dict, list))


def ismap(val: Any = UNDEF) -> bool:
    "Value is a defined map (hash) with string keys."
    return isinstance(val, dict)


def islist(val: Any = UNDEF) -> bool:
    "Value is a defined list (array) with integer keys (indexes)."
    return isinstance(val, list)


def iskey(key: Any = UNDEF) -> bool:
    "Value is a defined string (non-empty) or integer key."
    if isinstance(key, str):
        return len(key) > 0
    # Exclude bool (which is a subclass of int)
    if isinstance(key, bool):
        return False
    if isinstance(key, int):
        return True
    if isinstance(key, float):
        return True
    return False


def size(val: Any = UNDEF) -> int:
    """Determine the size of a value (length for lists/strings, count for maps)"""
    if val is UNDEF:
        return 0
    if islist(val):
        return len(val)
    elif ismap(val):
        return len(val.keys())
    
    if isinstance(val, str):
        return len(val)
    elif isinstance(val, (int, float)):
        return math.floor(val)
    elif isinstance(val, bool):
        return 1 if val else 0
    elif isinstance(val, tuple):
        return len(val)
    else:
        return 0


def slice(val: Any, start: int = UNDEF, end: int = UNDEF, mutate: bool = False) -> Any:
    """Return a part of a list, string, or clamp a number"""
    # Handle numbers - acts like clamp function
    if isinstance(val, (int, float)):
        if start is None:
            start = float('-inf')
        if end is None:
            end = float('inf')
        else:
            end = end - 1  # TypeScript uses exclusive end, so subtract 1
        return max(start, min(val, end))
    
    if islist(val) or isinstance(val, str):
        vlen = size(val)
        if end is not None and start is None:
            start = 0
        if start is not None:
            if start < 0:
                end = vlen + start
                if end < 0:
                    end = 0
                start = 0
            elif end is not None:
                if end < 0:
                    end = vlen + end
                    if end < 0:
                        end = 0
                elif vlen < end:
                    end = len(val)
            else:
                end = len(val)

            if vlen < start:
                start = vlen

            if -1 < start and start <= end and end <= vlen:
                if islist(val) and mutate:
                    j = start
                    for i in range(end - start):
                        val[i] = val[j]
                        j += 1
                    del val[end - start:]
                    return val
                return val[start:end]
            else:
                if islist(val):
                    if mutate:
                        del val[:]
                    return val if mutate else []
                return ""

    # No slice performed; return original value unchanged
    return val


def pad(s: Any, padding: int = UNDEF, padchar: str = UNDEF) -> str:
    """Pad a string to a specified length"""
    s = stringify(s)
    padding = 44 if padding is UNDEF else padding
    padchar = ' ' if padchar is UNDEF else (padchar + ' ')[0]
    
    if padding > -1:
        return s.ljust(padding, padchar)
    else:
        return s.rjust(-padding, padchar)


def strkey(key: Any = UNDEF) -> str:
    if UNDEF == key:
        return S_MT

    if isinstance(key, str):
        return key

    if isinstance(key, bool):
        return S_MT

    if isinstance(key, int):
        return str(key)

    if isinstance(key, float):
        return str(int(key))

    return S_MT


def isempty(val: Any = UNDEF) -> bool:
    "Check for an 'empty' value - None, empty string, array, object."
    if UNDEF == val:
        return True
    
    if val == S_MT:
        return True
    
    if islist(val) and len(val) == 0:
        return True
    
    if ismap(val) and len(val) == 0:
        return True
    
    return False    


def isfunc(val: Any = UNDEF) -> bool:
    "Value is a function."
    return callable(val)


def _clz32(n):
    if n <= 0:
        return 32
    return 31 - n.bit_length() + 1


def typename(t):
    return getelem(TYPENAME, _clz32(t), TYPENAME[0])


_TYPIFY_NO_ARG = object()


def typify(value: Any = _TYPIFY_NO_ARG) -> int:
    if value is _TYPIFY_NO_ARG:
        return T_noval
    if value is None:
        return T_scalar | T_null
    if isinstance(value, bool):
        return T_scalar | T_boolean
    if isinstance(value, int):
        return T_scalar | T_number | T_integer
    if isinstance(value, float):
        import math
        if math.isnan(value):
            return T_noval
        return T_scalar | T_number | T_decimal
    if isinstance(value, str):
        return T_scalar | T_string
    if callable(value):
        return T_scalar | T_function
    if isinstance(value, list):
        return T_node | T_list
    if isinstance(value, dict):
        return T_node | T_map
    return T_node | T_instance


def getelem(val: Any, key: Any, alt: Any = UNDEF) -> Any:
    """
    Get a list element. The key should be an integer, or a string
    that can parse to an integer only. Negative integers count from the end of the list.
    """
    out = UNDEF

    if UNDEF == val or UNDEF == key:
        return alt

    if islist(val):
        try:
            nkey = int(key)
            if isinstance(nkey, int) and str(key).strip('-').isdigit():
                if nkey < 0:
                    nkey = len(val) + nkey
                out = val[nkey] if 0 <= nkey < len(val) else UNDEF
        except (ValueError, IndexError):
            pass

    if UNDEF == out:
        return alt() if 0 < (T_function & typify(alt)) else alt

    return out


def getprop(val: Any = UNDEF, key: Any = UNDEF, alt: Any = UNDEF) -> Any:
    """
    Safely get a property of a node. Undefined arguments return undefined.
    If the key is not found, return the alternative value.
    """
    if UNDEF == val:
        return alt

    if UNDEF == key:
        return alt

    out = alt
    
    if ismap(val):
        out = val.get(str(key), alt)
    
    elif islist(val):
        try:
            key = int(key)
        except:
            return alt

        if 0 <= key < len(val):
            return val[key]
        else:
            return alt

    if UNDEF == out:
        return alt
        
    return out


def keysof(val: Any = UNDEF) -> list[str]:
    "Sorted keys of a map, or indexes of a list."
    if not isnode(val):
        return []
    elif ismap(val):
        return sorted(val.keys())
    else:
        return [str(x) for x in list(range(len(val)))]


def haskey(val: Any = UNDEF, key: Any = UNDEF) -> bool:
    "Value of property with name key in node val is defined."
    return UNDEF != getprop(val, key)

    
def items(val: Any = UNDEF, apply=None):
    "List the keys of a map or list as an array of [key, value] tuples."
    if not isnode(val):
        return []
    keys = keysof(val)
    out = [[k, val[k] if ismap(val) else val[int(k)]] for k in keys]
    if apply is not None:
        out = [apply(item) for item in out]
    return out
    

def flatten(lst, depth=None):
    if depth is None:
        depth = 1
    if not islist(lst):
        return lst
    out = []
    for item in lst:
        if islist(item) and depth > 0:
            out.extend(flatten(item, depth - 1))
        else:
            out.append(item)
    return out


def filter(val, check):
    all_items = items(val)
    numall = size(all_items)
    out = []
    for i in range(numall):
        if check(all_items[i]):
            out.append(all_items[i][1])
    return out


def escre(s: Any):
    "Escape regular expression."
    if UNDEF == s:
        s = ""
    pattern = r'([.*+?^${}()|\[\]\\])'
    return re.sub(pattern, r'\\\1', s)


def escurl(s: Any):
    "Escape URLs."
    if UNDEF == s:
        s = S_MT
    return urllib.parse.quote(s, safe="")


def replace(s, from_pat, to_str):
    "Replace a search string (all), or a regexp, in a source string."
    rs = s
    ts = typify(s)
    if 0 == (T_string & ts):
        rs = stringify(s)
    elif 0 < ((T_noval | T_null) & ts):
        rs = S_MT
    else:
        rs = stringify(s)
    if isinstance(from_pat, str):
        return rs.replace(from_pat, str(to_str))
    else:
        return re.sub(from_pat, str(to_str), rs)


def join(arr, sep=UNDEF, url=UNDEF):
    if not islist(arr):
        return S_MT
    sepdef = S_CM if sep is UNDEF or sep is None else sep
    sepre = escre(sepdef) if 1 == size(sepdef) else UNDEF

    sarr = size(arr)
    filtered = [(i, s) for i, s in enumerate(arr)
                if isinstance(s, str) and S_MT != s]

    result = []
    for idx, s in filtered:
        if sepre is not UNDEF and S_MT != sepre:
            if url and 0 == idx:
                s = re.sub(sepre + '+$', S_MT, s)
                result.append(s)
                continue
            if 0 < idx:
                s = re.sub('^' + sepre + '+', S_MT, s)
            if idx < sarr - 1 or not url:
                s = re.sub(sepre + '+$', S_MT, s)
            s = re.sub('([^' + sepre + '])' + sepre + '+([^' + sepre + '])',
                        r'\1' + sepdef + r'\2', s)

        if S_MT != s:
            result.append(s)

    return sepdef.join(result)


def joinurl(sarr):
    "Concatenate url part strings, merging forward slashes as needed."
    return join(sarr, '/', True)


def delprop(parent: Any, key: Any):
    """
    Delete a property from a dictionary or list.
    For arrays, the element at the index is removed and remaining elements are shifted down.
    """
    if not iskey(key):
        return parent

    if ismap(parent):
        key = strkey(key)
        if key in parent:
            del parent[key]

    elif islist(parent):
        # Convert key to int
        try:
            key_i = int(key)
        except ValueError:
            return parent

        key_i = int(key_i)  # Floor the value

        # Delete list element at position key_i, shifting later elements down
        if 0 <= key_i < len(parent):
            for pI in range(key_i, len(parent) - 1):
                parent[pI] = parent[pI + 1]
            parent.pop()

    return parent


def jsonify(val: Any = UNDEF, flags: Dict[str, Any] = None) -> str:
    """
    Convert a value to a formatted JSON string.
    In general, the behavior of JavaScript's JSON.stringify(val, null, 2) is followed.
    """
    flags = flags or {}
    
    if val is UNDEF:
        return S_null
    
    indent = getprop(flags, 'indent', 2)
    
    try:
        json_str = json.dumps(val, indent=indent, separators=(',', ': ') if indent else (',', ':'))
    except Exception:
        return S_null
    
    if json_str is None:
        return S_null
    
    offset = getprop(flags, 'offset', 0)
    if 0 < offset:
        lines = json_str.split('\n')
        padded = [pad(n[1], 0 - offset - size(n[1])) for n in items(lines[1:])]
        json_str = '{\n' + '\n'.join(padded)
    
    return json_str


def jo(*kv: Any) -> Dict[str, Any]:
    """
    Define a JSON Object using function arguments.
    Arguments are treated as key-value pairs.
    """
    kvsize = len(kv)
    o = {}
    
    for i in range(0, kvsize, 2):
        k = kv[i] if i < kvsize else f'$KEY{i}'
        # Handle None specially to become "null" for keys
        if k is None:
            k = 'null'
        elif isinstance(k, str):
            k = k
        else:
            k = stringify(k)
        o[k] = kv[i + 1] if i + 1 < kvsize else None
    
    return o


def ja(*v: Any) -> List[Any]:
    """
    Define a JSON Array using function arguments.
    """
    vsize = len(v)
    a = [None] * vsize
    
    for i in range(vsize):
        a[i] = v[i] if i < vsize else None
    
    return a


# Aliases to match TS canonical names
jm = jo
jt = ja


def select_AND(state, _val, _ref, store):
    if S_MKEYPRE == state.mode:
        terms = getprop(state.parent, state.key)
        ppath = slice(state.path, -1)
        point = getpath(store, ppath)

        vstore = merge([{}, store], 1)
        vstore['$TOP'] = point

        for term in terms:
            terrs = []
            validate(point, term, {
                'extra': vstore,
                'errs': terrs,
                'meta': state.meta,
            })
            if 0 != len(terrs):
                state.errs.append(
                    'AND:' + pathify(ppath) + '\u2A2F' + stringify(point) +
                    ' fail:' + stringify(terms))

        gkey = getelem(state.path, -2)
        gp = getelem(state.nodes, -2)
        setprop(gp, gkey, point)

    return UNDEF


def select_OR(state, _val, _ref, store):
    if S_MKEYPRE == state.mode:
        terms = getprop(state.parent, state.key)
        ppath = slice(state.path, -1)
        point = getpath(store, ppath)

        vstore = merge([{}, store], 1)
        vstore['$TOP'] = point

        for term in terms:
            terrs = []
            validate(point, term, {
                'extra': vstore,
                'errs': terrs,
                'meta': state.meta,
            })
            if 0 == len(terrs):
                gkey = getelem(state.path, -2)
                gp = getelem(state.nodes, -2)
                setprop(gp, gkey, point)
                return UNDEF

        state.errs.append(
            'OR:' + pathify(ppath) + '\u2A2F' + stringify(point) +
            ' fail:' + stringify(terms))

    return UNDEF


def select_NOT(state, _val, _ref, store):
    if S_MKEYPRE == state.mode:
        term = getprop(state.parent, state.key)
        ppath = slice(state.path, -1)
        point = getpath(store, ppath)

        vstore = merge([{}, store], 1)
        vstore['$TOP'] = point

        terrs = []
        validate(point, term, {
            'extra': vstore,
            'errs': terrs,
            'meta': state.meta,
        })

        if 0 == len(terrs):
            state.errs.append(
                'NOT:' + pathify(ppath) + '\u2A2F' + stringify(point) +
                ' fail:' + stringify(term))

        gkey = getelem(state.path, -2)
        gp = getelem(state.nodes, -2)
        setprop(gp, gkey, point)

    return UNDEF


def select_CMP(state, _val, ref, store):
    if S_MKEYPRE == state.mode:
        term = getprop(state.parent, state.key)
        gkey = getelem(state.path, -2)
        ppath = slice(state.path, -1)
        point = getpath(store, ppath)

        pass_test = False

        if '$GT' == ref and point > term:
            pass_test = True
        elif '$LT' == ref and point < term:
            pass_test = True
        elif '$GTE' == ref and point >= term:
            pass_test = True
        elif '$LTE' == ref and point <= term:
            pass_test = True
        elif '$LIKE' == ref:
            import re as re_mod
            if re_mod.search(term, stringify(point)):
                pass_test = True

        if pass_test:
            gp = getelem(state.nodes, -2)
            setprop(gp, gkey, point)
        else:
            state.errs.append(
                'CMP: ' + pathify(ppath) + '\u2A2F' + stringify(point) +
                ' fail:' + ref + ' ' + stringify(term))

    return UNDEF


def select(children: Any, query: Any) -> List[Any]:
    """
    Select children from a top-level object that match a MongoDB-style query.
    Supports $and, $or, and equality comparisons.
    For arrays, children are elements; for objects, children are values.
    """
    if not isnode(children):
        return []
    
    if ismap(children):
        children = [setprop(v, S_DKEY, k) or v for k, v in items(children)]
    else:
        children = [setprop(n, S_DKEY, i) or n if ismap(n) else n for i, n in enumerate(children)]
    
    results = []
    injdef = {
        'errs': [],
        'meta': {S_BEXACT: True},
        'extra': {
            '$AND': select_AND,
            '$OR': select_OR,
            '$NOT': select_NOT,
            '$GT': select_CMP,
            '$LT': select_CMP,
            '$GTE': select_CMP,
            '$LTE': select_CMP,
            '$LIKE': select_CMP,
        }
    }
    
    q = clone(query)
    
    # Add $OPEN to all maps in the query
    def add_open(_k, v, _parent, _path):
        if ismap(v):
            setprop(v, '`$OPEN`', getprop(v, '`$OPEN`', True))
        return v
    
    walk(q, add_open)
    
    for child in children:
        injdef['errs'] = []
        validate(child, clone(q), injdef)
        
        if size(injdef['errs']) == 0:
            results.append(child)
    
    return results


def stringify(val: Any, maxlen: int = UNDEF, pretty: Any = None):
    "Safely stringify a value for printing (NOT JSON!)."

    pretty = bool(pretty)
    valstr = S_MT

    if UNDEF == val:
        return '<>' if pretty else valstr

    if isinstance(val, str):
        valstr = val
    else:
        try:
            valstr = json.dumps(val, sort_keys=True, separators=(',', ':'))
            valstr = valstr.replace('"', '')
        except Exception:
            valstr = '__STRINGIFY_FAILED__'

    if maxlen is not UNDEF and maxlen is not None and -1 < maxlen:
        js = valstr[:maxlen]
        valstr = (js[:maxlen - 3] + '...') if maxlen < len(valstr) else valstr

    if pretty:
        colors = [81, 118, 213, 39, 208, 201, 45, 190, 129, 51, 160, 121, 226, 33, 207, 69]
        c = ['\x1b[38;5;' + str(n) + 'm' for n in colors]
        r = '\x1b[0m'
        d = 0
        o = c[0]
        t = o
        for ch in valstr:
            if ch in ('{', '['):
                d += 1
                o = c[d % len(c)]
                t += o + ch
            elif ch in ('}', ']'):
                t += o + ch
                d -= 1
                o = c[d % len(c)]
            else:
                t += o + ch
        valstr = t + r

    return valstr


def pathify(val: Any = UNDEF, startin: int = UNDEF, endin: int = UNDEF) -> str:
    pathstr = UNDEF
    
    # Convert input to a path array
    path = val if islist(val) else \
        [val] if iskey(val) else \
        UNDEF

    # [val] if isinstance(val, str) else \
        # [val] if isinstance(val, (int, float)) else \

    
    # Determine starting index and ending index
    start = 0 if startin is UNDEF else startin if -1 < startin else 0
    end = 0 if endin is UNDEF else endin if -1 < endin else 0

    if UNDEF != path and 0 <= start:
        path = path[start:len(path)-end]

        if 0 == len(path):
            pathstr = "<root>"
        else:
            # Filter path parts to include only valid keys
            filtered_path = [p for p in path if iskey(p)]
            
            # Map path parts: convert numbers to strings and remove any dots
            mapped_path = []
            for p in filtered_path:
                if isinstance(p, (int, float)):
                    mapped_path.append(S_MT + str(int(p)))
                else:
                    mapped_path.append(str(p).replace('.', S_MT))
            
            pathstr = S_DT.join(mapped_path)

    # Handle the case where we couldn't create a path
    if UNDEF == pathstr:
        pathstr = f"<unknown-path{S_MT if UNDEF == val else S_CN+stringify(val, 47)}>"

    return pathstr


def clone(val: Any = UNDEF):
    """
    Clone a JSON-like data structure.
    NOTE: function value references are copied, *not* cloned.
    """
    if UNDEF == val:
        return UNDEF

    refs = []

    def replacer(item):
        if callable(item):
            refs.append(item)
            return f'`$FUNCTION:{len(refs) - 1}`'
        elif isinstance(item, dict):
            return {k: replacer(v) for k, v in item.items()}
        elif isinstance(item, (list, tuple)):
            return [replacer(elem) for elem in item]
        elif hasattr(item, 'to_json'):
            return item.to_json()
        elif hasattr(item, '__dict__'):
            return item.__dict__ 
        else:
            return item

    transformed = replacer(val)

    json_str = json.dumps(transformed, separators=(',', ':'))

    def reviver(item):
        if isinstance(item, str):
            match = re.match(r'^`\$FUNCTION:(\d+)`$', item)
            if match:
                index = int(match.group(1))
                return refs[index]
            else:
                return item
        elif isinstance(item, list):
            return [reviver(elem) for elem in item]
        elif isinstance(item, dict):
            return {k: reviver(v) for k, v in item.items()}
        else:
            return item

    parsed = json.loads(json_str)

    return reviver(parsed)


def setprop(parent: Any, key: Any, val: Any):
    """
    Safely set a property on a dictionary or list.
    - None value deletes the key/element (mirrors JS undefined behavior).
    - For lists, negative key -> prepend.
    - For lists, key > len(list) -> append.
    """
    if not iskey(key):
        return parent

    if ismap(parent):
        key = str(key)
        if val is None:
            parent.pop(key, None)
        else:
            parent[key] = val

    elif islist(parent):
        try:
            key_i = int(key)
        except ValueError:
            return parent

        if val is None:
            if 0 <= key_i < len(parent):
                for pI in range(key_i, len(parent) - 1):
                    parent[pI] = parent[pI + 1]
                parent.pop()
        else:
            if key_i >= 0:
                key_i = min(key_i, len(parent))
                if key_i >= len(parent):
                    parent.append(val)
                else:
                    parent[key_i] = val
            else:
                parent.insert(0, val)

    return parent


MAXDEPTH = 32


def walk(
        val: Any,
        apply: Any = None,
        key: Any = UNDEF,
        parent: Any = UNDEF,
        path: Any = UNDEF,
        *,
        before: Any = None,
        after: Any = None,
        maxdepth: Any = None,
        pool: Any = UNDEF,
):
    """
    Walk a data structure depth-first.
    Supports before (pre-descent) and after (post-descent) callbacks.
    For backward compat, `apply` is treated as the after callback.

    The `path` argument passed to the before/after callbacks is a single
    mutable list per depth, shared across all callback invocations for
    the lifetime of this top-level walk call. Callbacks that need to
    store the path MUST clone it (e.g. ``path[:]`` or ``list(path)``);
    the contents will otherwise be overwritten by subsequent visits.
    """
    if pool is UNDEF:
        pool = [[]]
    if path is UNDEF:
        path = pool[0]

    _before = before
    _after = after if after is not None else apply

    depth = len(path)

    out = val if _before is None else _before(key, val, parent, path)

    md = maxdepth if maxdepth is not None and 0 <= maxdepth else MAXDEPTH
    if 0 == md or (0 < md and md <= depth):
        return out

    if isnode(out):
        child_depth = depth + 1
        # Grow pool on demand: pool[n] is a reusable path list of length n.
        # Appending at index i creates a list of length i, matching index.
        while len(pool) <= child_depth:
            pool.append([None] * len(pool))
        child_path = pool[child_depth]
        # Sync prefix [0..depth-1] from the current path. Only needed once
        # per parent: siblings share the same prefix and will each
        # overwrite slot [depth] below.
        for i in range(depth):
            child_path[i] = path[i]

        for (ckey, child) in items(out):
            child_path[depth] = str(ckey)
            result = walk(
                child, key=ckey, parent=out,
                path=child_path,
                before=_before, after=_after, maxdepth=md,
                pool=pool,
            )
            if ismap(out):
                out[str(ckey)] = result
            elif islist(out):
                out[int(ckey)] = result

    if _after is not None:
        out = _after(key, out, parent, path)

    return out


def merge(objs: List[Any] = None, maxdepth: Any = None) -> Any:
    """
    Merge a list of values into each other. Later values have
    precedence.  Nodes override scalars. Node kinds (list or map)
    override each other, and do *not* merge.  The first element is
    modified.
    """

    md = MAXDEPTH if maxdepth is None else max(maxdepth, 0)

    if not islist(objs):
        return objs

    lenlist = len(objs)

    if 0 == lenlist:
        return UNDEF
    if 1 == lenlist:
        return objs[0]

    out = getprop(objs, 0, {})

    for oI in range(1, lenlist):
        obj = objs[oI]

        if not isnode(obj):
            out = obj
        else:
            cur = [out]
            dst = [out]

            def before(key, val, _parent, path):
                pI = size(path)

                if md <= pI:
                    cur_len = len(cur)
                    if pI >= cur_len:
                        cur.extend([UNDEF] * (pI + 1 - cur_len))
                    cur[pI] = val
                    if pI > 0 and pI - 1 < len(cur):
                        setprop(cur[pI - 1], key, val)
                    return UNDEF

                elif not isnode(val):
                    cur_len = len(cur)
                    if pI >= cur_len:
                        cur.extend([UNDEF] * (pI + 1 - cur_len))
                    cur[pI] = val

                else:
                    dst_len = len(dst)
                    if pI >= dst_len:
                        dst.extend([UNDEF] * (pI + 1 - dst_len))
                    cur_len = len(cur)
                    if pI >= cur_len:
                        cur.extend([UNDEF] * (pI + 1 - cur_len))

                    dst[pI] = getprop(dst[pI - 1], key) if 0 < pI else dst[pI]
                    tval = dst[pI]

                    if UNDEF == tval:
                        cur[pI] = [] if islist(val) else {}
                    elif (islist(val) and islist(tval)) or (ismap(val) and ismap(tval)):
                        cur[pI] = tval
                    else:
                        cur[pI] = val
                        val = UNDEF

                return val

            def after(key, _val, _parent, path):
                cI = size(path)
                if cI < 1:
                    return cur[0] if len(cur) > 0 else _val

                target = cur[cI - 1] if cI - 1 < len(cur) else UNDEF
                value = cur[cI] if cI < len(cur) else UNDEF

                setprop(target, key, value)
                return value

            out = walk(obj, before=before, after=after)

    if 0 == md:
        out = getprop(objs, lenlist - 1, UNDEF)
        out = [] if islist(out) else {} if ismap(out) else out

    return out


def getpath(store, path, injdef=UNDEF):
    """
    Get a value from the store using a path.
    Supports relative paths (..), escaping ($$), and special syntax.
    """
    # Operate on a string array.
    if islist(path):
        parts = path[:]
    elif isinstance(path, str):
        parts = path.split(S_DT)
    elif isinstance(path, (int, float)) and not isinstance(path, bool):
        parts = [strkey(path)]
    else:
        return UNDEF
    
    val = store
    # Support both dict-style injdef and Injection instance
    if isinstance(injdef, Injection):
        base = injdef.base
        dparent = injdef.dparent
        inj_meta = injdef.meta
        inj_key = injdef.key
        dpath = injdef.dpath
    else:
        base = getprop(injdef, S_base) if injdef else UNDEF
        dparent = getprop(injdef, 'dparent') if injdef else UNDEF
        inj_meta = getprop(injdef, 'meta') if injdef else UNDEF
        inj_key = getprop(injdef, 'key') if injdef else UNDEF
        dpath = getprop(injdef, 'dpath') if injdef else UNDEF

    src = getprop(store, base, store) if base else store
    numparts = size(parts)
    
    # An empty path (incl empty string) just finds the store.
    if path is UNDEF or store is UNDEF or (1 == numparts and parts[0] == S_MT) or numparts == 0:
        val = src
        return val
    elif numparts > 0:
        
        # Check for $ACTIONs
        if 1 == numparts:
            val = getprop(store, parts[0])
        
        if not isfunc(val):
            val = src
            
            # Check for meta path syntax
            m = R_META_PATH.match(parts[0]) if parts[0] else None
            if m and inj_meta:
                val = getprop(inj_meta, m.group(1))
                parts[0] = m.group(3)
            
            
            for pI in range(numparts):
                if val is UNDEF:
                    break
                    
                part = parts[pI]
                
                # Handle special path components
                if injdef and part == S_DKEY:
                    part = inj_key if inj_key is not UNDEF else part
                elif isinstance(part, str) and part.startswith('$GET:'):
                    # $GET:path$ -> get store value, use as path part (string)
                    part = stringify(getpath(src, part[5:-1]))
                elif isinstance(part, str) and part.startswith('$REF:'):
                    # $REF:refpath$ -> get spec value, use as path part (string)
                    part = stringify(getpath(getprop(store, S_DSPEC), part[5:-1]))
                elif injdef and isinstance(part, str) and part.startswith('$META:'):
                    # $META:metapath$ -> get meta value, use as path part (string)
                    part = stringify(getpath(inj_meta, part[6:-1]))
                
                # $$ escapes $ (path parts can be int e.g. list indices)
                if isinstance(part, str):
                    part = R_DOUBLE_DOLLAR.sub('$', part)
                else:
                    part = strkey(part)
                
                if part == S_MT:
                    ascends = 0
                    while pI + 1 < len(parts) and parts[pI + 1] == S_MT:
                        ascends += 1
                        pI += 1

                    if injdef and 0 < ascends:
                        if pI == len(parts) - 1:
                            ascends -= 1

                        if 0 == ascends:
                            val = dparent
                        else:
                            fullpath = flatten(
                                [slice(dpath, 0 - ascends), parts[pI + 1:]])
                            if ascends <= size(dpath):
                                val = getpath(store, fullpath)
                            else:
                                val = UNDEF
                            break
                    else:
                        val = dparent
                else:
                    val = getprop(val, part)
    
    # Injdef may provide a custom handler to modify found value.
    handler = injdef.handler if isinstance(injdef, Injection) else (getprop(injdef, 'handler') if injdef else UNDEF)
    if handler and isfunc(handler):
        ref = pathify(path)
        val = handler(injdef, val, ref, store)
    
    return val


def setpath(store, path, val, injdef=UNDEF):
    pathType = typify(path)

    if 0 < (T_list & pathType):
        parts = path
    elif 0 < (T_string & pathType):
        parts = path.split(S_DT)
    elif 0 < (T_number & pathType):
        parts = [path]
    else:
        return UNDEF

    base = getprop(injdef, S_base) if injdef else UNDEF
    numparts = size(parts)
    parent = getprop(store, base, store) if base else store

    for pI in range(numparts - 1):
        partKey = getelem(parts, pI)
        nextParent = getprop(parent, partKey)
        if not isnode(nextParent):
            nextPart = getelem(parts, pI + 1)
            nextParent = [] if 0 < (T_number & typify(nextPart)) else {}
            setprop(parent, partKey, nextParent)
        parent = nextParent

    if DELETE is val:
        delprop(parent, getelem(parts, -1))
    else:
        setprop(parent, getelem(parts, -1), val)

    return parent


def inject(val, store, injdef=UNDEF):
    """
    Inject values from `store` into `val` recursively, respecting backtick syntax.
    """
    valtype = type(val)

    # Reuse existing injection state during recursion; otherwise create a new one.
    if isinstance(injdef, Injection):
        inj = injdef
    else:
        inj = injdef  # may be dict/UNDEF; used below via getprop
        # Create state if at root of injection. The input value is placed
        # inside a virtual parent holder to simplify edge cases.
        parent = {S_DTOP: val}
        inj = Injection(
            mode=S_MVAL,
            full=False,
            keyI=0,
            keys=[S_DTOP],
            key=S_DTOP,
            val=val,
            parent=parent,
            path=[S_DTOP],
            nodes=[parent],
            handler=_injecthandler,
            base=S_DTOP,
            modify=getprop(injdef, 'modify') if injdef else None,
            meta=getprop(injdef, 'meta', {}),
            errs=getprop(store, S_DERRS, [])
        )
        inj.dparent = store
        inj.dpath = [S_DTOP]
        inj.root = parent  # Virtual root so we can return it after $EACH etc. replace it

        if injdef is not UNDEF:
            if getprop(injdef, 'extra'):
                inj.extra = getprop(injdef, 'extra')
            if getprop(injdef, 'handler'):
                inj.handler = getprop(injdef, 'handler')
            if getprop(injdef, 'dparent'):
                inj.dparent = getprop(injdef, 'dparent')
            if getprop(injdef, 'dpath'):
                inj.dpath = getprop(injdef, 'dpath')

    inj.descend()

    # Descend into node.
    if isnode(val):
        # Keys are sorted alphanumerically to ensure determinism.
        # Injection transforms ($FOO) are processed *after* other keys.
        if ismap(val):
            normal_keys = [k for k in val.keys() if S_DS not in k]
            normal_keys.sort()
            transform_keys = [k for k in val.keys() if S_DS in k]
            transform_keys.sort()
            nodekeys = normal_keys + transform_keys
        else:
            nodekeys = list(range(len(val)))

        # Each child key-value pair is processed in three injection phases:
        # 1. inj.mode='key:pre' - Key string is injected, returning a possibly altered key.
        # 2. inj.mode='val' - The child value is injected.
        # 3. inj.mode='key:post' - Key string is injected again, allowing child mutation.
        nkI = 0
        while nkI < len(nodekeys):
            childinj = inj.child(nkI, nodekeys)
            nodekey = childinj.key
            childinj.mode = S_MKEYPRE

            # Perform the key:pre mode injection on the child key.
            prekey = _injectstr(nodekey, store, childinj)

            # The injection may modify child processing.
            nkI = childinj.keyI
            nodekeys = childinj.keys

            # Prevent further processing by returning an undefined prekey
            if prekey is not UNDEF:
                childinj.val = getprop(val, prekey)
                childinj.mode = S_MVAL

                # Perform the val mode injection on the child value.
                inject(childinj.val, store, childinj)

                # The injection may modify child processing.
                nkI = childinj.keyI
                nodekeys = childinj.keys

                # Perform the key:post mode injection on the child key.
                childinj.mode = S_MKEYPOST
                _injectstr(nodekey, store, childinj)

                # The injection may modify child processing.
                nkI = childinj.keyI
                nodekeys = childinj.keys

            nkI += 1

    # Inject paths into string scalars.
    elif isinstance(val, str):
        inj.mode = S_MVAL
        val = _injectstr(val, store, inj)
        if val is not SKIP:
            inj.setval(val)

    # Custom modification.
    if inj.modify and val is not SKIP:
        mkey = inj.key
        mparent = inj.parent
        mval = getprop(mparent, mkey)

        inj.modify(mval, mkey, mparent, inj)

    inj.val = val

    # Return the (possibly transform-replaced) root only at top level (prior is None).
    if getattr(inj, 'prior', None) is None and getattr(inj, 'root', None) is not None and haskey(inj.root, S_DTOP):
        return getprop(inj.root, S_DTOP)
    if inj.key == S_DTOP and inj.parent is not UNDEF and haskey(inj.parent, S_DTOP):
        return getprop(inj.parent, S_DTOP)
    return val


# Default inject handler for transforms. If the path resolves to a function,
# call the function passing the injection state. This is how transforms operate.
def _injecthandler(inj, val, ref, store):
    out = val
    iscmd = isfunc(val) and (UNDEF == ref or (isinstance(ref, str) and ref.startswith(S_DS)))

    # Only call val function if it is a special command ($NAME format).
    if iscmd:
        try:
            num_params = len(inspect.signature(val).parameters)
        except (ValueError, TypeError):
            num_params = 4
        if num_params >= 5:
            out = val(inj, val, inj.dparent, ref, store)
        else:
            out = val(inj, val, ref, store)

    # Update parent with value. Ensures references remain in node tree.
    else:
        if inj.mode == S_MVAL and inj.full:
            inj.setval(val)

    return out


# -----------------------------------------------------------------------------
# Transform helper functions (these are injection handlers).


def transform_DELETE(inj, val, ref, store):
    """
    Injection handler to delete a key from a map/list.
    """
    inj.setval(UNDEF)
    return UNDEF


def transform_COPY(inj, val, ref, store):
    """
    Injection handler to copy a value from source data under the same key.
    """
    mode = inj.mode
    key = inj.key
    parent = inj.parent

    out = UNDEF
    if mode.startswith('key'):
        out = key
    else:
        # If dparent is a scalar (not a node): at root (path length 1) use whole data; when nested
        # (path length > 2) use dparent; at first level (path length 2): if key is a list index
        # we're at a list item (dparent already indexed) -> use dparent; else omit key (UNDEF).
        if not isnode(inj.dparent):
            if len(inj.path) != 2:
                out = inj.dparent
            else:
                try:
                    int(key)  # list index -> we're at the list item value
                    out = inj.dparent
                except (ValueError, TypeError):
                    out = UNDEF
        else:
            out = getprop(inj.dparent, key)
            # If getprop returned UNDEF and key looks like a list index,
            # we might be at the item level already - return dparent itself
            if out is UNDEF and key is not None:
                try:
                    int(key)  # key is a list index
                    # We're at the item level, key is the list index
                    # This shouldn't happen normally, but handle it
                    out = inj.dparent
                except (ValueError, TypeError):
                    pass
        inj.setval(out)

    return out


def transform_KEY(inj, val, ref, store):
    """
    Injection handler to inject the parent's key (or a specified key).
    """
    mode = inj.mode
    path = inj.path
    parent = inj.parent

    if mode == S_MKEYPRE:
        # Preserve the key during pre phase so value phase runs
        return inj.key
    if mode != S_MVAL:
        return UNDEF

    keyspec = getprop(parent, S_BKEY)
    if keyspec is not UNDEF:
        # Need to use setprop directly here since we're removing a specific key (S_DKEY)
        # not the current state's key
        setprop(parent, S_BKEY, UNDEF)
        return getprop(inj.dparent, keyspec)

    # If no explicit keyspec, and current data has a field matching this key,
    # use that value (common case: { k: '`$KEY`' } to pull dparent['k']).
    if ismap(inj.dparent) and inj.key is not UNDEF and haskey(inj.dparent, inj.key):
        return getprop(inj.dparent, inj.key)

    meta = getprop(parent, S_BANNO)
    return getprop(meta, S_KEY, getprop(path, len(path) - 2))


def transform_ANNO(inj, val, ref, store):
    """
    Annotate node. Does nothing itself, just used by other injectors, and is removed when called.
    """
    parent = inj.parent
    setprop(parent, S_BANNO, UNDEF)
    return UNDEF


def transform_MERGE(inj, val, ref, store):
    """
    Injection handler to merge a list of objects onto the parent object.
    If the transform data is an empty string, merge the top-level store.
    """
    mode = inj.mode
    key = inj.key
    parent = inj.parent

    out = UNDEF

    if mode == S_MKEYPRE:
        out = key

    # Operate after child values have been transformed.
    elif mode == S_MKEYPOST:
        out = key

        args = getprop(parent, key)
        args = args if islist(args) else [args]

        # Remove the $MERGE command from a parent map.
        inj.setval(UNDEF)

        # Literals in the parent have precedence, but we still merge onto
        # the parent object, so that node tree references are not changed.
        mergelist = [parent] + args + [clone(parent)]

        merge(mergelist)

    # List syntax: parent is an array like ['`$MERGE`', ...]
    elif mode == S_MVAL and islist(parent):
        # Only act on the transform element at index 0
        if strkey(inj.key) == '0' and size(parent) > 0:
            # Drop the command element so remaining args become the list content
            del parent[0]
            # Return the new first element as the injected scalar
            out = getprop(parent, 0)
        else:
            out = getprop(parent, inj.key)

    return out


def transform_EACH(inj, val, ref, store):
    """
    Injection handler to convert the current node into a list by iterating over
    a source node. Format: ['`$EACH`','`source-path`', child-template]
    """
    mode = inj.mode
    keys_ = inj.keys
    path = inj.path
    parent = inj.parent
    nodes_ = inj.nodes

    if keys_ is not UNDEF:
        # Only keep the transform item (first). Avoid further spurious keys.
        keys_[:] = keys_[:1]

    if mode != S_MVAL or path is UNDEF or nodes_ is UNDEF:
        return UNDEF

    # parent here is the array [ '$EACH', 'source-path', {... child ...} ]
    srcpath = parent[1] if len(parent) > 1 else UNDEF
    child_template = clone(parent[2]) if len(parent) > 2 else UNDEF

    # Source data
    srcstore = getprop(store, inj.base, store)
    src = getpath(srcstore, srcpath, inj)
    
    # Create parallel data structures:
    # source entries :: child templates
    tcurrent = []
    tval = []

    tkey = path[-2] if len(path) >= 2 else UNDEF
    target = nodes_[-2] if len(nodes_) >= 2 else nodes_[-1]

    rval = []
    
    if isnode(src):
        if islist(src):
            tval = [clone(child_template) for _ in src]
        else:
            # Convert dict to a list of child templates
            tval = []
            for k, v in src.items():
                # Keep key in meta for usage by `$KEY`
                copy_child = clone(child_template)
                if ismap(copy_child):
                    setprop(copy_child, S_BANNO, {S_KEY: k})
                tval.append(copy_child)
        tcurrent = list(src.values()) if ismap(src) else src
        
        if 0 < size(tval):
            # Build tcurrent structure matching TypeScript approach
            ckey = getelem(path, -2) if len(path) >= 2 else UNDEF
            tpath = path[:-1] if len(path) > 0 else []
            
            # Build dpath: [S_DTOP, ...srcpath parts, '$:' + ckey]
            dpath = [S_DTOP]
            if isinstance(srcpath, str) and srcpath:
                for part in srcpath.split(S_DT):
                    if part != S_MT:
                        dpath.append(part)
            if ckey is not UNDEF:
                dpath.append('$:' + str(ckey))
            
            tcur = {ckey: tcurrent}

            if 1 < size(tpath):
                pkey = getelem(path, -3, S_DTOP)
                tcur = {pkey: tcur}
                dpath.append('$:' + str(pkey))
            
            # Create child injection state
            tinj = inj.child(0, [ckey] if ckey is not UNDEF else [])
            tinj.path = tpath
            tinj.nodes = nodes_[:-1] if len(nodes_) > 0 else []
            tinj.parent = getelem(tinj.nodes, -1) if len(tinj.nodes) > 0 else UNDEF
            
            if ckey is not UNDEF and tinj.parent is not UNDEF:
                setprop(tinj.parent, ckey, tval)
            
            tinj.val = tval
            tinj.dpath = dpath
            tinj.dparent = tcur
            
            # Inject the entire list at once
            inject(tval, store, tinj)
            rval = tinj.val

    setprop(target, tkey, rval)

    return rval[0] if islist(rval) and 0 < size(rval) else UNDEF


def transform_PACK(inj, val, ref, store):
    mode = inj.mode
    key = inj.key
    path = inj.path
    parent = inj.parent
    nodes_ = inj.nodes

    if (mode != S_MKEYPRE or not isinstance(key, str) or path is UNDEF or nodes_ is UNDEF):
        return UNDEF

    args_val = getprop(parent, key)
    if not islist(args_val) or size(args_val) < 2:
        return UNDEF

    srcpath = args_val[0]
    origchildspec = args_val[1]

    tkey = getelem(path, -2)
    pathsize = size(path)
    target = getelem(nodes_, pathsize - 2, lambda: getelem(nodes_, pathsize - 1))

    srcstore = getprop(store, inj.base, store)
    src = getpath(srcstore, srcpath, inj)

    if not islist(src):
        if ismap(src):
            src_items = items(src)
            new_src = []
            for item in src_items:
                setprop(item[1], S_BANNO, {S_KEY: item[0]})
                new_src.append(item[1])
            src = new_src
        else:
            src = UNDEF

    if src is UNDEF:
        return UNDEF

    keypath = getprop(origchildspec, S_BKEY)
    childspec = delprop(origchildspec, S_BKEY)

    child = getprop(childspec, S_BVAL, childspec)

    tval = {}
    for item in items(src):
        srckey = item[0]
        srcnode = item[1]

        k = srckey
        if keypath is not UNDEF:
            if isinstance(keypath, str) and keypath.startswith(S_BT):
                k = inject(keypath, merge([{}, store, {S_DTOP: srcnode}], 1))
            else:
                k = getpath(srcnode, keypath, inj)

        tchild = clone(child)
        setprop(tval, k, tchild)

        anno = getprop(srcnode, S_BANNO)
        if anno is UNDEF:
            delprop(tchild, S_BANNO)
        else:
            setprop(tchild, S_BANNO, anno)

    rval = {}

    if not isempty(tval):
        tsrc = {}
        for i, n in enumerate(src):
            if keypath is UNDEF:
                kn = i
            elif isinstance(keypath, str) and keypath.startswith(S_BT):
                kn = inject(keypath, merge([{}, store, {S_DTOP: n}], 1))
            else:
                kn = getpath(n, keypath, inj)
            setprop(tsrc, kn, n)

        tpath = slice(inj.path, -1)
        ckey = getelem(inj.path, -2)
        dpath = flatten([S_DTOP, srcpath.split(S_DT), '$:' + str(ckey)])

        tcur = {ckey: tsrc}

        if 1 < size(tpath):
            pkey = getelem(inj.path, -3, S_DTOP)
            tcur = {pkey: tcur}
            dpath.append('$:' + str(pkey))

        tinj = inj.child(0, [ckey])
        tinj.path = tpath
        tinj.nodes = slice(inj.nodes, -1)
        tinj.parent = getelem(tinj.nodes, -1)
        tinj.val = tval
        tinj.dpath = dpath
        tinj.dparent = tcur

        inject(tval, store, tinj)
        rval = tinj.val

    setprop(target, tkey, rval)

    return UNDEF


def transform_REF(inj, val, _ref, store):
    """
    Reference original spec (enables recursive transformations)
    Format: ['`$REF`', '`spec-path`']
    """
    nodes = inj.nodes
    modify = inj.modify

    if inj.mode != S_MVAL:
        return UNDEF

    # Get arguments: ['`$REF`', 'ref-path']
    refpath = getprop(inj.parent, 1)
    inj.keyI = len(inj.keys)

    # Spec reference
    spec_func = getprop(store, S_DSPEC)
    if not callable(spec_func):
        return UNDEF
    spec = spec_func()
    ref = getpath(spec, refpath)

    # Check if ref has another $REF inside
    hasSubRef = False
    if isnode(ref):
        def check_subref(k, v, parent, path):
            nonlocal hasSubRef
            if v == '`$REF`':
                hasSubRef = True
            return v

        walk(ref, check_subref)

    tref = clone(ref)

    cpath = slice(inj.path, 0, len(inj.path)-3)
    tpath = slice(inj.path, 0, len(inj.path)-1)
    tcur = getpath(store, cpath)
    tval = getpath(store, tpath)
    rval = UNDEF

    # When ref target not found, omit the key (setval UNDEF). Do not inject UNDEF.
    if ref is not UNDEF and (not hasSubRef or tval is not UNDEF):
        # Create child state for the next level
        child_state = inj.child(0, [getelem(tpath, -1)])
        child_state.path = tpath
        child_state.nodes = slice(inj.nodes, 0, len(inj.nodes)-1)
        child_state.parent = getelem(nodes, -2)
        child_state.val = tref

        # Inject with child state
        child_state.dparent = tcur
        inject(tref, store, child_state)
        rval = child_state.val
    else:
        rval = UNDEF

    # Set the value in grandparent, using setval
    inj.setval(rval, 2)
    
    # Handle lists by decrementing keyI
    if islist(inj.parent) and inj.prior:
        inj.prior.keyI -= 1

    return val


def _fmt_number(_k, v, *_args):
    if isnode(v):
        return v
    try:
        n = float(v)
    except (ValueError, TypeError):
        n = 0
    if n != n:
        n = 0
    return int(n) if n == int(n) else n


def _fmt_integer(_k, v, *_args):
    if isnode(v):
        return v
    try:
        n = float(v)
    except (ValueError, TypeError):
        n = 0
    if n != n:
        n = 0
    return int(n)


def _jsstr(v):
    if v is None:
        return 'null'
    if isinstance(v, bool):
        return 'true' if v else 'false'
    return str(v)


FORMATTER = {
    'identity': lambda _k, v, *_a: v,
    'upper': lambda _k, v, *_a: v if isnode(v) else _jsstr(v).upper(),
    'lower': lambda _k, v, *_a: v if isnode(v) else _jsstr(v).lower(),
    'string': lambda _k, v, *_a: v if isnode(v) else _jsstr(v),
    'number': _fmt_number,
    'integer': _fmt_integer,
    'concat': lambda k, v, *_a: join(
        items(v, lambda n: '' if isnode(n[1]) else _jsstr(n[1])), '') if k is None and islist(v) else v,
}


def checkPlacement(modes, ijname, parentTypes, inj):
    mode_num = _MODE_TO_NUM.get(inj.mode, 0)
    if 0 == (modes & mode_num):
        allowed = [m for m in [M_KEYPRE, M_KEYPOST, M_VAL] if modes & m]
        placements = join(
            items(allowed, lambda n: _PLACEMENT.get(n[1], '')), ',')
        inj.errs.append('$' + ijname + ': invalid placement as ' +
                         _PLACEMENT.get(mode_num, '') +
                         ', expected: ' + placements + '.')
        return False
    if not isempty(parentTypes):
        ptype = typify(inj.parent)
        if 0 == (parentTypes & ptype):
            inj.errs.append('$' + ijname + ': invalid placement in parent ' +
                             typename(ptype) + ', expected: ' + typename(parentTypes) + '.')
            return False
    return True


def injectorArgs(argTypes, args):
    numargs = size(argTypes)
    found = [UNDEF] * (1 + numargs)
    found[0] = UNDEF
    for argI in range(numargs):
        arg = getelem(args, argI)
        argType = typify(arg)
        if 0 == (argTypes[argI] & argType):
            found[0] = ('invalid argument: ' + stringify(arg, 22) +
                        ' (' + typename(argType) + ' at position ' + str(1 + argI) +
                        ') is not of type: ' + typename(argTypes[argI]) + '.')
            break
        found[1 + argI] = arg
    return found


def injectChild(child, store, inj):
    cinj = inj
    if inj.prior is not UNDEF and inj.prior is not None:
        if inj.prior.prior is not UNDEF and inj.prior.prior is not None:
            cinj = inj.prior.prior.child(inj.prior.keyI, inj.prior.keys)
            cinj.val = child
            setprop(cinj.parent, inj.prior.key, child)
        else:
            cinj = inj.prior.child(inj.keyI, inj.keys)
            cinj.val = child
            setprop(cinj.parent, inj.key, child)
    inject(child, store, cinj)
    return cinj


def transform_FORMAT(inj, _val, _ref, store):
    slice(inj.keys, 0, 1, True)

    if S_MVAL != inj.mode:
        return UNDEF

    name = getprop(inj.parent, 1)
    child = getprop(inj.parent, 2)

    tkey = getelem(inj.path, -2)
    target = getelem(inj.nodes, -2, lambda: getelem(inj.nodes, -1))

    cinj = injectChild(child, store, inj)
    resolved = cinj.val

    formatter = name if 0 < (T_function & typify(name)) else getprop(FORMATTER, name)

    if formatter is UNDEF:
        inj.errs.append('$FORMAT: unknown format: ' + str(name) + '.')
        return UNDEF

    out = walk(resolved, formatter)

    setprop(target, tkey, out)

    return out


def transform_APPLY(inj, _val, _ref, store):
    ijname = 'APPLY'

    if not checkPlacement(M_VAL, ijname, T_list, inj):
        return UNDEF

    err_apply_child = injectorArgs([T_function, T_any], slice(inj.parent, 1))
    err = err_apply_child[0]
    apply_fn = err_apply_child[1]
    child = err_apply_child[2] if len(err_apply_child) > 2 else UNDEF

    if UNDEF != err:
        inj.errs.append('$' + ijname + ': ' + err)
        return UNDEF

    tkey = getelem(inj.path, -2)
    target = getelem(inj.nodes, -2, lambda: getelem(inj.nodes, -1))

    cinj = injectChild(child, store, inj)
    resolved = cinj.val

    try:
        out = apply_fn(resolved, store, cinj)
    except TypeError:
        try:
            out = apply_fn(resolved, store)
        except TypeError:
            out = apply_fn(resolved)

    setprop(target, tkey, out)

    return out


# Transform data using spec.
# Only operates on static JSON-like data.
# Arrays are treated as if they are objects with indices as keys.
def transform(
        data,
        spec,
        injdef=UNDEF
):
    # Clone the spec so that the clone can be modified in place as the transform result.
    origspec = spec
    spec = clone(spec)

    extra = getprop(injdef, 'extra') if injdef else UNDEF

    collect = getprop(injdef, 'errs') is not None and getprop(injdef, 'errs') is not UNDEF if injdef else False
    errs = getprop(injdef, 'errs') if collect else []

    extraTransforms = {}
    extraData = {} if UNDEF == extra else {}
    
    if extra:
        for k, v in items(extra):
            if isinstance(k, str) and k.startswith(S_DS):
                extraTransforms[k] = v
            else:
                extraData[k] = v

    # Combine extra data with user data
    data_clone = merge([
        clone(extraData) if not isempty(extraData) else UNDEF,
        clone(data)
    ])

    # Top-level store used by inject
    store = {
        # The inject function recognises this special location for the root of the source data.
        # NOTE: to escape data that contains "`$FOO`" keys at the top level,
        # place that data inside a holding map: { myholder: mydata }.
        S_DTOP: data_clone,

        # Original spec (before clone) for $REF to resolve refpath.
        S_DSPEC: lambda: origspec,
        
        # Escape backtick (this also works inside backticks).
        '$BT': lambda *args, **kwargs: S_BT,
        
        # Escape dollar sign (this also works inside backticks).
        '$DS': lambda *args, **kwargs: S_DS,
        
        # Insert current date and time as an ISO string.
        '$WHEN': lambda *args, **kwargs: datetime.utcnow().isoformat(),

        '$DELETE': transform_DELETE,
        '$COPY': transform_COPY,
        '$KEY': transform_KEY,
        '$ANNO': transform_ANNO,
        '$MERGE': transform_MERGE,
        '$EACH': transform_EACH,
        '$PACK': transform_PACK,
        '$REF': transform_REF,
        '$FORMAT': transform_FORMAT,
        '$APPLY': transform_APPLY,

        # Custom extra transforms, if any.
        **extraTransforms,

        S_DERRS: errs,
    }

    if injdef is UNDEF or injdef is None:
        injdef = {}
    if not isinstance(injdef, dict):
        injdef = {}
    injdef = {**injdef, 'errs': errs}

    out = inject(spec, store, injdef)

    generr = 0 < size(errs) and not collect
    if generr:
        raise ValueError(join(errs, ' | '))

    return out


def validate_STRING(inj, _val=UNDEF, _ref=UNDEF, _store=UNDEF):
    out = getprop(inj.dparent, inj.key)
    t = typify(out)

    if 0 == (T_string & t):
        inj.errs.append(_invalidTypeMsg(inj.path, S_string, t, out, 'V1010'))
        return UNDEF

    if S_MT == out:
        inj.errs.append('Empty string at ' + pathify(inj.path, 1))
        return UNDEF

    return out


TYPE_CHECKS = {
    S_number: lambda v: isinstance(v, (int, float)) and not isinstance(v, bool),
    S_integer: lambda v: isinstance(v, int) and not isinstance(v, bool),
    S_decimal: lambda v: isinstance(v, float),
    S_boolean: lambda v: isinstance(v, bool),
    S_null: lambda v: v is None,
    S_nil: lambda v: v is UNDEF,
    S_map: lambda v: isinstance(v, dict),
    S_list: lambda v: isinstance(v, list),
    S_function: lambda v: callable(v) and not isinstance(v, type),
    S_instance: lambda v: (not isinstance(v, (dict, list, str, int, float, bool))
                           and v is not None and v is not UNDEF),
}


def validate_TYPE(inj, _val=UNDEF, ref=UNDEF, _store=UNDEF):
    tname = slice(ref, 1).lower() if isinstance(ref, str) and len(ref) > 1 else S_any
    typev = 1 << (31 - TYPENAME.index(tname)) if tname in TYPENAME else 0
    if tname == S_nil:
        typev = typev | T_null
    out = getprop(inj.dparent, inj.key)
    t = typify(out)

    if 0 == (t & typev):
        inj.errs.append(_invalidTypeMsg(inj.path, tname, t, out, 'V1001'))
        return UNDEF

    return out


def validate_ANY(inj, _val=UNDEF, _ref=UNDEF, _store=UNDEF):
    return getprop(inj.dparent, inj.key)


def validate_CHILD(inj, _val=UNDEF, _ref=UNDEF, _store=UNDEF):
    mode = inj.mode
    key = inj.key
    parent = inj.parent
    path = inj.path
    keys = inj.keys

    # Map syntax.
    if S_MKEYPRE == mode:
        childtm = getprop(parent, key)

        pkey = getelem(path, -2)
        tval = getprop(inj.dparent, pkey)

        if UNDEF == tval:
            tval = {}
        elif not ismap(tval):
            inj.errs.append(_invalidTypeMsg(
                path[:-1], S_object, typify(tval), tval, 'V0220'))
            return UNDEF

        ckeys = keysof(tval)
        for ckey in ckeys:
            setprop(parent, ckey, clone(childtm))
            keys.append(ckey)

        inj.setval(UNDEF)
        return UNDEF

    # List syntax.
    if S_MVAL == mode:

        if not islist(parent):
            inj.errs.append('Invalid $CHILD as value')
            return UNDEF

        childtm = getprop(parent, 1)

        if UNDEF == inj.dparent:
            del parent[:]
            return UNDEF

        if not islist(inj.dparent):
            msg = _invalidTypeMsg(
                path[:-1], S_list, typify(inj.dparent), inj.dparent, 'V0230')
            inj.errs.append(msg)
            inj.keyI = size(parent)
            return inj.dparent

        for n in items(inj.dparent):
            setprop(parent, n[0], clone(childtm))
        del parent[len(inj.dparent):]
        inj.keyI = 0

        out = getprop(inj.dparent, 0)
        return out

    return UNDEF


def validate_ONE(inj, _val=UNDEF, _ref=UNDEF, store=UNDEF):
    mode = inj.mode
    parent = inj.parent
    keyI = inj.keyI

    if S_MVAL == mode:
        if not islist(parent) or 0 != keyI:
            inj.errs.append('The $ONE validator at field ' +
                            pathify(inj.path, 1, 1) +
                            ' must be the first element of an array.')
            return None

        inj.keyI = size(inj.keys)

        inj.setval(inj.dparent, 2)

        inj.path = inj.path[:-1]
        inj.key = getelem(inj.path, -1)

        tvals = parent[1:]
        if 0 == size(tvals):
            inj.errs.append('The $ONE validator at field ' +
                            pathify(inj.path, 1, 1) +
                            ' must have at least one argument.')
            return None

        for tval in tvals:
            terrs = []

            vstore = merge([{}, store], 1)
            vstore[S_DTOP] = inj.dparent

            vcurrent = validate(inj.dparent, tval, {
                'extra': vstore,
                'errs': terrs,
                'meta': inj.meta,
            })

            inj.setval(vcurrent, -2)

            if 0 == size(terrs):
                return None

        valdesc = ', '.join(stringify(n[1]) for n in items(tvals))
        valdesc = re.sub(r'`\$([A-Z]+)`', lambda m: m.group(1).lower(), valdesc)

        inj.errs.append(_invalidTypeMsg(
            inj.path,
            ('one of ' if 1 < size(tvals) else '') + valdesc,
            typify(inj.dparent), inj.dparent, 'V0210'))


def validate_EXACT(inj, _val=UNDEF, _ref=UNDEF, _store=UNDEF):
    mode = inj.mode
    parent = inj.parent
    key = inj.key
    keyI = inj.keyI

    if S_MVAL == mode:
        if not islist(parent) or 0 != keyI:
            inj.errs.append('The $EXACT validator at field ' +
                pathify(inj.path, 1, 1) +
                ' must be the first element of an array.')
            return None

        inj.keyI = size(inj.keys)

        inj.setval(inj.dparent, 2)

        inj.path = inj.path[:-1]
        inj.key = getelem(inj.path, -1)

        tvals = parent[1:]
        if 0 == size(tvals):
            inj.errs.append('The $EXACT validator at field ' +
                pathify(inj.path, 1, 1) +
                ' must have at least one argument.')
            return None

        currentstr = None
        for tval in tvals:
            exactmatch = tval == inj.dparent

            if not exactmatch and isnode(tval):
                currentstr = stringify(inj.dparent) if currentstr is None else currentstr
                tvalstr = stringify(tval)
                exactmatch = tvalstr == currentstr

            if exactmatch:
                return None

        valdesc = ', '.join(stringify(n[1]) for n in items(tvals))
        valdesc = re.sub(r'`\$([A-Z]+)`', lambda m: m.group(1).lower(), valdesc)

        inj.errs.append(_invalidTypeMsg(
            inj.path,
            ('' if 1 < size(inj.path) else 'value ') +
            'exactly equal to ' + ('' if 1 == size(tvals) else 'one of ') + valdesc,
            typify(inj.dparent), inj.dparent, 'V0110'))
    else:
        delprop(parent, key)

        
def _validation(
        pval,
        key,
        parent,
        inj
):
    if UNDEF == inj:
        return

    if pval == SKIP:
        return

    # select needs exact matches
    exact = getprop(inj.meta, S_BEXACT, False)

    # Current val to verify.
    cval = getprop(inj.dparent, key)

    if UNDEF == inj or (not exact and UNDEF == cval):
        return

    ptype = typify(pval)

    if 0 < (T_string & ptype) and S_DS in str(pval):
        return

    ctype = typify(cval)

    if ptype != ctype and UNDEF != pval:
        inj.errs.append(_invalidTypeMsg(inj.path, typename(ptype), ctype, cval, 'V0010'))
        return

    if ismap(cval):
        if not ismap(pval):
            inj.errs.append(_invalidTypeMsg(inj.path, typename(ptype), ctype, cval, 'V0020'))
            return

        ckeys = keysof(cval)
        pkeys = keysof(pval)

        # Empty spec object {} means object can be open (any keys).
        if 0 < len(pkeys) and True != getprop(pval, '`$OPEN`'):
            badkeys = []
            for ckey in ckeys:
                if not haskey(pval, ckey):
                    badkeys.append(ckey)
            if 0 < size(badkeys):
                msg = 'Unexpected keys at field ' + pathify(inj.path, 1) + S_VIZ + join(badkeys, ', ')
                inj.errs.append(msg)
        else:
            # Object is open, so merge in extra keys.
            merge([pval, cval])
            if isnode(pval):
                delprop(pval, '`$OPEN`')

    elif islist(cval):
        if not islist(pval):
            inj.errs.append(_invalidTypeMsg(inj.path, typename(ptype), ctype, cval, 'V0030'))

    elif exact:
        if cval != pval:
            pathmsg = 'at field ' + pathify(inj.path, 1) + ': ' if 1 < size(inj.path) else ''
            inj.errs.append('Value ' + pathmsg + str(cval) +
                ' should equal ' + str(pval) + '.')

    else:
        # Spec value was a default, copy over data
        setprop(parent, key, cval)

    return


# Validate a data structure against a shape specification.  The shape
# specification follows the "by example" principle.  Plain data in
# teh shape is treated as default values that also specify the
# required type.  Thus shape {a:1} validates {a:2}, since the types
# (number) match, but not {a:'A'}.  Shape {a;1} against data {}
# returns {a:1} as a=1 is the default value of the a key.  Special
# validation commands (in the same syntax as transform ) are also
# provided to specify required values.  Thus shape {a:'`$STRING`'}
# validates {a:'A'} but not {a:1}. Empty map or list means the node
# is open, and if missing an empty default is inserted.
def validate(data, spec, injdef=UNDEF):
    extra = getprop(injdef, 'extra')

    collect = getprop(injdef, 'errs') is not None and getprop(injdef, 'errs') is not UNDEF
    errs = getprop(injdef, 'errs') if collect else []
    
    store = merge([
        {
            "$DELETE": None,
            "$COPY": None,
            "$KEY": None,
            "$META": None,
            "$MERGE": None,
            "$EACH": None,
            "$PACK": None,

            "$STRING": validate_STRING,
            "$NUMBER": validate_TYPE,
            "$INTEGER": validate_TYPE,
            "$DECIMAL": validate_TYPE,
            "$BOOLEAN": validate_TYPE,
            "$NULL": validate_TYPE,
            "$NIL": validate_TYPE,
            "$MAP": validate_TYPE,
            "$LIST": validate_TYPE,
            "$FUNCTION": validate_TYPE,
            "$INSTANCE": validate_TYPE,
            "$ANY": validate_ANY,
            "$CHILD": validate_CHILD,
            "$ONE": validate_ONE,
            "$EXACT": validate_EXACT,
        },

        ({} if extra is UNDEF or extra is None else extra),

        {
            "$ERRS": errs,
        }
    ], 1)

    meta = getprop(injdef, 'meta', {})
    setprop(meta, S_BEXACT, getprop(meta, S_BEXACT, False))

    out = transform(data, spec, {
        'meta': meta,
        'extra': store,
        'modify': _validation,
        'handler': _validatehandler,
        'errs': errs,
    })

    generr = 0 < len(errs) and not collect
    if generr:
        raise ValueError(' | '.join(errs))

    return out



# Internal utilities
# ==================

def _validatehandler(inj, val, ref, store):
    out = val
    
    m = R_META_PATH.match(ref) if ref else None
    ismetapath = m is not None
    
    if ismetapath:
        if m.group(2) == '=':
            inj.setval([S_BEXACT, val])
        else:
            inj.setval(val)
        inj.keyI = -1
        
        out = SKIP
    else:
        out = _injecthandler(inj, val, ref, store)
    
    return out


# Set state.key property of state.parent node, ensuring reference consistency
# when needed by implementation language.
def _setparentprop(state, val):
    setprop(state.parent, state.key, val)
    
    
# Update all references to target in state.nodes.
def _updateAncestors(_state, target, tkey, tval):
    # SetProp is sufficient in Python as target reference remains consistent even for lists.
    setprop(target, tkey, tval)


# Inject values from a data store into a string. Not a public utility - used by
# `inject`.  Inject are marked with `path` where path is resolved
# with getpath against the store or current (if defined)
# arguments. See `getpath`.  Custom injection handling can be
# provided by state.handler (this is used for transform functions).
# The path can also have the special syntax $NAME999 where NAME is
# upper case letters only, and 999 is any digits, which are
# discarded. This syntax specifies the name of a transform, and
# optionally allows transforms to be ordered by alphanumeric sorting.
def _injectstr(val, store, inj=UNDEF):
    # Can't inject into non-strings
    full_re = re.compile(r'^`(\$[A-Z]+|[^`]*)[0-9]*`$')
    part_re = re.compile(r'`([^`]*)`')

    if not isinstance(val, str) or S_MT == val:
        return S_MT

    out = val
    
    # Pattern examples: "`a.b.c`", "`$NAME`", "`$NAME1`"
    m = full_re.match(val)
    
    # Full string of the val is an injection.
    if m:
        if UNDEF != inj:
            inj.full = True

        pathref = m.group(1)

        # Special escapes inside injection.
        if 3 < len(pathref):
            pathref = pathref.replace(r'$BT', S_BT).replace(r'$DS', S_DS)

        # Get the extracted path reference.
        out = getpath(store, pathref, inj)

    else:
        
        # Check for injections within the string.
        def partial(mobj):
            ref = mobj.group(1)

            # Special escapes inside injection.
            if 3 < len(ref):
                ref = ref.replace(r'$BT', S_BT).replace(r'$DS', S_DS)
                
            if UNDEF != inj:
                inj.full = False

            found = getpath(store, ref, inj)
            
            # Ensure inject value is a string.
            if UNDEF == found:
                return S_MT
                
            if isinstance(found, str):
                # Convert test NULL marker to JSON 'null' when injecting into strings
                if found == '__NULL__':
                    return 'null'
                return found
                
            if isfunc(found):
                return found

            try:
                return json.dumps(found, separators=(',', ':'))
            except (TypeError, ValueError):
                return stringify(found)

        out = part_re.sub(partial, val)

        # Also call the inj handler on the entire string, providing the
        # option for custom injection.
        if UNDEF != inj and isfunc(inj.handler):
            inj.full = True
            out = inj.handler(inj, out, val, store)

    return out


def _invalidTypeMsg(path, needtype, vt, v, _whence=None):
    vs = 'no value' if v is None or v is UNDEF else stringify(v)
    return (
        'Expected ' +
        ('field ' + pathify(path, 1) + ' to be ' if 1 < size(path) else '') +
        str(needtype) + ', but found ' +
        (typename(vt) + S_VIZ if v is not None and v is not UNDEF else '') + vs +
        '.'
    )


# Create a StructUtils class with all utility functions as attributes
class StructUtility:
    def __init__(self):
        self.clone = clone
        self.delprop = delprop
        self.escre = escre
        self.escurl = escurl
        self.filter = filter
        self.flatten = flatten
        self.getdef = getdef
        self.getelem = getelem
        self.getpath = getpath
        self.getprop = getprop
        self.haskey = haskey
        self.inject = inject
        self.isempty = isempty
        self.isfunc = isfunc
        self.iskey = iskey
        self.islist = islist
        self.ismap = ismap
        self.isnode = isnode
        self.items = items
        self.jm = jm
        self.jt = jt
        self.jo = jo
        self.ja = ja
        self.join = join
        self.joinurl = joinurl
        self.jsonify = jsonify
        self.keysof = keysof
        self.merge = merge
        self.pad = pad
        self.pathify = pathify
        self.replace = replace
        self.select = select
        self.setpath = setpath
        self.setprop = setprop
        self.size = size
        self.slice = slice
        self.stringify = stringify
        self.strkey = strkey
        self.transform = transform
        self.typify = typify
        self.typename = typename
        self.validate = validate
        self.walk = walk

        self.SKIP = SKIP
        self.DELETE = DELETE
        self.tn = typename

        self.T_any = T_any
        self.T_noval = T_noval
        self.T_boolean = T_boolean
        self.T_decimal = T_decimal
        self.T_integer = T_integer
        self.T_number = T_number
        self.T_string = T_string
        self.T_function = T_function
        self.T_symbol = T_symbol
        self.T_null = T_null
        self.T_list = T_list
        self.T_map = T_map
        self.T_instance = T_instance
        self.T_scalar = T_scalar
        self.T_node = T_node

        self.checkPlacement = checkPlacement
        self.injectorArgs = injectorArgs
        self.injectChild = injectChild
    

__all__ = [
    'Injection',
    'StructUtility',
    'checkPlacement',
    'clone',
    'delprop',
    'escre',
    'escurl',
    'filter',
    'flatten',
    'getdef',
    'getelem',
    'getpath',
    'getprop',
    'haskey',
    'inject',
    'injectChild',
    'injectorArgs',
    'isempty',
    'isfunc',
    'iskey',
    'islist',
    'ismap',
    'isnode',
    'items',
    'ja',
    'jm',
    'jo',
    'join',
    'joinurl',
    'jsonify',
    'jt',
    'keysof',
    'merge',
    'pad',
    'pathify',
    'replace',
    'select',
    'setpath',
    'setprop',
    'size',
    'slice',
    'stringify',
    'strkey',
    'transform',
    'typename',
    'typify',
    'validate',
    'walk',
    'SKIP',
    'DELETE',
    'T_any',
    'T_noval',
    'T_boolean',
    'T_decimal',
    'T_integer',
    'T_number',
    'T_string',
    'T_function',
    'T_symbol',
    'T_null',
    'T_list',
    'T_map',
    'T_instance',
    'T_scalar',
    'T_node',
    'M_KEYPRE',
    'M_KEYPOST',
    'M_VAL',
    'MODENAME',
]

