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


from typing import Any, List, Tuple, Optional, Callable, Dict, Union
from datetime import datetime
import urllib.parse
import json
import re
import math

# Constants
S_MT = ''  # Empty string
S_DT = '.'  # Dot
S_CN = ':'  # Colon
S_DS = '$'  # Dollar sign
S_DTOP = '$TOP'  # Top level key
S_DERRS = '$ERRS'  # Errors key
S_DMETA = '`$META`'  # Meta key
S_DREF = '$REF'  # Reference key
S_DMERGE = '$MERGE'  # Merge key
S_DCOPY = '$COPY'  # Copy key
S_DKEY = '`$KEY`'  # Key key
S_DEACH = '$EACH'  # Each key
S_DPACK = '$PACK'  # Pack key
S_DWHEN = '$WHEN'  # When key
S_DDELETE = '$DELETE'  # Delete key
S_DEXACT = '$EXACT'  # Exact key
S_DONE = '$ONE'  # One key
S_DCHILD = '$CHILD'  # Child key
S_DANY = '$ANY'  # Any key
S_DFUNCTION = '$FUNCTION'  # Function key
S_DOBJECT = '$OBJECT'  # Object key
S_DARRAY = '$ARRAY'  # Array key
S_DBOOLEAN = '$BOOLEAN'  # Boolean key
S_DNUMBER = '$NUMBER'  # Number key
S_DSTRING = '$STRING'  # String key
S_DNULL = '$NULL'  # Null key
S_SKIP = '$SKIP'  # Skip key

# Type definitions
class _UndefinedType:
    def __repr__(self):
        return 'UNDEF'

UNDEF = _UndefinedType()  # Undefined value

# Type aliases
Injector = Callable[[Any, Any, Any, Any, Any, Any], Any]
Modify = Callable[[Any, Any, Any, Any, Any, Any], Any]
WalkApply = Callable[[Any, Any, Any, Any], Any]

# Type strings
S_null = 'null'
S_string = 'string'
S_number = 'number'
S_boolean = 'boolean'
S_function = 'function'
S_array = 'array'
S_object = 'object'

# Mode strings
S_MVAL = 'val'
S_MKEYPRE = 'keypre'
S_MKEYPOST = 'keypost'

# Mode value for inject step.
S_MKEYPRE =  'key:pre'
S_MKEYPOST =  'key:post'
S_MVAL =  'val'
S_MKEY =  'key'

# General strings.
S_array =  'array'
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
S_FS =  '/'
S_KEY =  'KEY'


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
        dparent: Any = None,          # Data parent node
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
        self.meta = meta
        self.base = base
        self.modify = modify
        self.prior = None
        self.dparent = dparent

    def child(self, keyI: int, keys: List[str]) -> 'Injection':
        """Create a child state object with the given key index and keys."""
        return Injection(
            mode=self.mode,
            full=self.full,
            keyI=keyI,
            keys=keys,
            key=self.key,
            val=self.val,
            parent=self.parent,
            path=self.path,
            nodes=self.nodes,
            handler=self.handler,
            errs=self.errs,
            meta=self.meta,
            base=self.base,
            modify=self.modify,
            dparent=self.dparent
        )

    def setval(self, val: Any, ancestor: Optional[int] = None) -> Any:
        """Set the value in the parent node at the specified ancestor level."""
        if ancestor is None or ancestor < 2:
            return setprop(self.parent, self.key, val)
        else:
            return setprop(getelem(self.nodes, 0 - ancestor), getelem(self.path, 0 - ancestor), val)


def isnode(val: Any = UNDEF) -> bool:
    """
    Value is a node - defined, and a map (hash) or list (array).
    """
    return isinstance(val, (dict, list))


def ismap(val: Any = UNDEF) -> bool:
    """
    Value is a defined map (hash) with string keys.
    """
    return isinstance(val, dict)


def islist(val: Any = UNDEF) -> bool:
    """
    Value is a defined list (array) with integer keys (indexes).
    """
    return isinstance(val, list)


def iskey(key: Any = UNDEF) -> bool:
    """
    Value is a defined string (non-empty) or integer key.
    """
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


def size(val: Any) -> int:
    """
    The integer size of the value. For arrays and strings, the length,
    for numbers, the integer part, for boolean, true is 1 and false 0, for all other values, 0.
    """
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
    else:
        return 0


def slice(val: Any, start: Optional[int] = None, end: Optional[int] = None) -> Any:
    """
    Extract part of an array or string into a new value, from the start point to the end point.
    If no end is specified, extract to the full length of the value. Negative arguments count
    from the end of the value. For numbers, perform min and max bounding, where start is
    inclusive, and end is *exclusive*.
    """
    if isinstance(val, (int, float)):
        start = float('-inf') if start is None else start
        end = float('inf') if end is None else end - 1
        return min(max(val, start), end)

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
                end = vlen
        else:
            end = vlen

        if vlen < start:
            start = vlen

        if -1 < start and start <= end and end <= vlen:
            if islist(val):
                return val[start:end]
            elif isinstance(val, str):
                return val[start:end]
        else:
            if islist(val):
                return []
            elif isinstance(val, str):
                return S_MT

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
    """
    Convert different types of keys to string representation.
    String keys are returned as is.
    Number keys are converted to strings.
    Floats are truncated to integers.
    Booleans, objects, arrays, null, undefined all return empty string.
    """
    if UNDEF == key:
        return S_MT

    if isinstance(key, str):
        return key

    if isinstance(key, bool):
        return S_MT

    if isinstance(key, (int, float)):
        return str(int(key))

    return S_MT


def isempty(val: Any = UNDEF) -> bool:
    """
    Check for an 'empty' value - None, empty string, array, object.
    """
    if val is None:
        return True
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
    """
    Value is a function.
    """
    return callable(val)


def typify(value: Any = UNDEF) -> str:
    """
    Determine the type of a value as a string.
    Returns one of: 'null', 'string', 'number', 'boolean', 'function', 'array', 'object'
    Normalizes and simplifies JavaScript's type system for consistency.
    """
    if value is None or value is UNDEF:
        return S_null

    if isinstance(value, bool):
        return S_boolean
    if isinstance(value, (int, float)):
        return S_number
    if isinstance(value, str):
        return S_string
    if callable(value):
        return S_function
    if isinstance(value, list):
        return S_array
    if isinstance(value, dict):
        return S_object

    return S_null


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
                    key = len(val) + nkey
                out = val[key] if 0 <= key < len(val) else UNDEF
        except (ValueError, IndexError):
            pass

    if UNDEF == out:
        return alt

    return out


def getprop(val: Any = UNDEF, key: Any = UNDEF, alt: Any = None) -> Any:
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


def keysof(val: Any = UNDEF) -> List[str]:
    """
    Sorted keys of a map, or indexes of a list.
    """
    if not isnode(val):
        return []
    elif ismap(val):
        return sorted(val.keys())
    else:
        return [str(x) for x in list(range(len(val)))]


def haskey(val: Any = UNDEF, key: Any = UNDEF) -> bool:
    """
    Value of property with name key in node val is defined.
    """
    # Return False for undefined or None
    if UNDEF == val or val is None:
        return False
    # Map: check if string key exists
    if ismap(val):
        return str(key) in val
    # List: check if integer index exists
    if islist(val):
        try:
            nkey = int(key)
        except Exception:
            return False
        # only allow non-negative integer indices
        if isinstance(nkey, int) and str(key).isdigit():
            return 0 <= nkey < len(val)
        return False
    # Other types have no keys
    return False

    
def items(val: Any = UNDEF) -> List[Tuple[Any, Any]]:
    """
    List the keys of a map or list as an array of [key, value] tuples.
    """
    if ismap(val):
        return [(k, val[k]) for k in keysof(val)]
    elif islist(val):
        return [(i, val[i]) for i in list(range(len(val)))]
    else:
        return []
    

def escre(s: Any) -> str:
    """
    Escape regular expression.
    """
    if UNDEF == s:
        s = ""
    pattern = r'([.*+?^${}()|\[\]\\])'
    return re.sub(pattern, r'\\\1', s)


def escurl(s: Any) -> str:
    """
    Escape URLs.
    """
    if UNDEF == s:
        s = S_MT
    return urllib.parse.quote(s, safe="")


def joinurl(sarr: List[str]) -> str:
    """
    Concatenate url part strings, merging forward slashes as needed.
    """
    sarr = [s for s in sarr if s is not None and s != ""]

    transformed = []
    for i, s in enumerate(sarr):
        if i == 0:
            s = re.sub(r'/+$', '', s)
        else:
            s = re.sub(r'([^/])/{2,}', r'\1/', s)
            s = re.sub(r'^/+', '', s)
            s = re.sub(r'/+$', '', s)

        transformed.append(s)

    transformed = [s for s in transformed if s != ""]

    return "/".join(transformed)


def stringify(val: Any, maxlen: Optional[int] = None) -> str:
    """
    Safely stringify a value for printing (NOT JSON!).
    """
    valstr = S_MT    

    # Treat None as empty
    if val is None:
        return valstr
    if UNDEF == val:
        return valstr

    try:
        valstr = json.dumps(val, sort_keys=True, separators=(',', ':'))
    except Exception:
        valstr = str(val)
    
    valstr = valstr.replace('"', '')

    if maxlen is not None:
        json_len = len(valstr)
        valstr = valstr[:maxlen]
        
        if 3 < maxlen < json_len:
            valstr = valstr[:maxlen - 3] + '...'
    
    return valstr


def pathify(val: Any = UNDEF, startin: Optional[int] = None, endin: Optional[int] = None) -> str:
    """
    Convert a path array or string to a dot-notation path string.
    """
    # Treat None input as undefined
    if val is None:
        val = UNDEF
    pathstr = UNDEF
    
    # Convert input to a path array
    path = val if islist(val) else \
        [val] if iskey(val) else \
        UNDEF

    # Determine starting index and ending index
    start = 0 if startin is None else startin if -1 < startin else 0
    end = 0 if endin is None else endin if -1 < endin else 0

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


def clone(val: Any = None) -> Any:
    """
    Clone a JSON-like data structure.
    NOTE: function value references are copied, *not* cloned.
    """
    # Handle None input
    if val is None:
        return None
    # Preserve internal UNDEF
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


def setprop(parent: Any, key: Any, val: Any) -> Any:
    """
    Safely set a property on a dictionary or list.
    - If `val` is UNDEF, delete the key from parent.
    - For lists, negative key -> prepend.
    - For lists, key > len(list) -> append.
    - For lists, UNDEF value -> remove and shift down.
    """
    if not iskey(key):
        return parent

    if ismap(parent):
        key = str(key)
        if UNDEF == val:
            parent.pop(key, UNDEF)
        else:
            parent[key] = val

    elif islist(parent):
        # Convert key to int
        try:
            key_i = int(key)
        except ValueError:
            return parent

        # Delete an element
        if UNDEF == val:
            if 0 <= key_i < len(parent):
                # Shift items left
                for pI in range(key_i, len(parent) - 1):
                    parent[pI] = parent[pI + 1]
                parent.pop()
        else:
            # Non-empty insert
            if key_i >= 0:
                if key_i >= len(parent):
                    # Append if out of range
                    parent.append(val)
                else:
                    parent[key_i] = val
            else:
                # Prepend if negative
                parent.insert(0, val)

    return parent


def walk(
        val: Any,
        apply: WalkApply,
        key: Any = UNDEF,
        parent: Any = UNDEF,
        path: Any = UNDEF
) -> Any:
    """
    Walk a data structure depth-first, calling apply at each node (after children).
    """
    if path is UNDEF:
        path = []
    if isnode(val):
        for (ckey, child) in items(val):
            setprop(val, ckey, walk(child, apply, ckey, val, path + [str(ckey)]))

    # Nodes are applied *after* their children.
    # For the root node, key and parent will be UNDEF.
    return apply(key, val, parent, path)


def merge(objs: List[Any] = None) -> Any:
    """
    Merge a list of values into each other. Later values have
    precedence.  Nodes override scalars. Node kinds (list or map)
    override each other, and do *not* merge.  The first element is
    modified.
    """
    # Handle edge cases.
    if not islist(objs):
        return objs
    if len(objs) == 0:
        return None
    if len(objs) == 1:
        return objs[0]
        
    # Merge a list of values.
    out = getprop(objs, 0, {})

    for i in range(1, len(objs)):
        obj = clone(objs[i])

        if not isnode(obj):
            out = obj

        else:
            # Nodes win, also over nodes of a different kind
            if (not isnode(out) or (ismap(obj) and islist(out)) or (islist(obj) and ismap(out))):
                out = obj
            else:
                cur = [out]
                cI = 0
                
                def merger(key, val, parent, path):
                    if UNDEF == key:
                        return val

                    # Get the curent value at the current path in obj.
                    # NOTE: this is not exactly efficient, and should be optimised.
                    lenpath = len(path)
                    cI = lenpath - 1

                    # Ensure the cur list has at least cI elements
                    cur.extend([UNDEF]*(1+cI-len(cur)))
                        
                    if UNDEF == cur[cI]:
                        cur[cI] = getpath(path[:-1], out)

                        # Create node if needed
                        if not isnode(cur[cI]):
                            cur[cI] = [] if islist(parent) else {}

                    # Node child is just ahead of us on the stack, since
                    # `walk` traverses leaves before nodes.
                    if isnode(val) and not isempty(val):
                        cur.extend([UNDEF] * (2+cI+len(cur)))
                
                        setprop(cur[cI], key, cur[cI + 1])
                        cur[cI + 1] = UNDEF

                    else:
                        # Scalar child.
                        setprop(cur[cI], key, val)

                    return val

                walk(obj, merger)

    return out


def getpath(path: Any, store: Any, current: Any = UNDEF, state: Any = UNDEF) -> Any:
    """
    Get the value at a key path deep inside an object.
    """
    # Special case: single dot "." refers to current
    if path == S_DT:
        return current
    
    # Operate on a string array.
    if isinstance(path, str):
        parts = path.split(S_DT)
    elif islist(path):
        parts = path[:]
    else:
        return None
    
    root = store
    val = store
    base = UNDEF if state is None or state is UNDEF else getattr(state, 'base', UNDEF)
    
    # An empty path (incl empty string) just finds the store.
    if path is UNDEF or store is UNDEF or (1 == len(parts) and parts[0] == S_MT):
        # The actual store data may be in a store sub property, defined by state.base.
        val = getprop(store, base, store)

    elif len(parts) > 0:
        pI = 0
        skip_remaining = False
             
        # Relative path uses `current` argument.
        if parts[0] == S_MT:
            pI = 1
            # If current is wrapped in a $TOP structure, unwrap it for relative path resolution
            if ismap(current) and S_DTOP in current:
                root = getprop(current, S_DTOP)
            else:
                root = current
            val = root  # Start from current for relative paths

        # Handle multiple empty parts as "go up levels" operations
        # Count consecutive empty parts after the first one
        up_levels = 0
        while pI < len(parts) and parts[pI] == S_MT:
            up_levels += 1
            pI += 1
        
        # Go up the specified number of levels by using the store
        if up_levels > 0:
            # Use dpath from state to navigate up levels
            if state and hasattr(state, 'dpath') and state.dpath:
                dpath = state.dpath
                # If we're at the last part of the path, we need one less ascend
                if pI == len(parts):
                    up_levels -= 1
                
                if up_levels == 0:
                    val = current
                    skip_remaining = True
                elif up_levels <= len(dpath):
                    # Navigate from store using the truncated path
                    fullpath = dpath[:-up_levels] + parts[pI:]
                    val = getpath(fullpath, store)
                    skip_remaining = True
                else:
                    val = None  # Going beyond root returns None
                    skip_remaining = True
            else:
                # Check if state has parent_data for ... navigation
                if state and hasattr(state, 'parent_data') and state.parent_data is not None:
                    # Use parent data and continue with remaining path
                    val = state.parent_data
                    # Continue processing remaining parts
                    while UNDEF != val and pI < len(parts):
                        part = parts[pI]
                        if part != S_MT:
                            val = getprop(val, part)
                        pI += 1
                    skip_remaining = True
                else:
                    # No proper context to go up levels
                    # If there are remaining parts after going up, we can't resolve them
                    if pI < len(parts):
                        val = None  # Can't resolve remaining path parts
                        skip_remaining = True
                    else:
                        # Fallback to original behavior only if no remaining parts
                        val = getprop(store, base, store)
        
        if not skip_remaining and up_levels == 0:
            part = parts[pI] if pI < len(parts) else UNDEF
            first = current if part == S_MT else getprop(root, part)

            # At top level, check state.base, if provided
            base_data = getprop(root, base) if base is not UNDEF else None
            val = getprop(base_data, part) if (UNDEF == first or first is None) and 0 == pI else first
             
            pI += 1
             
            # Move along the remaining path, trying to descend into the store.
            while UNDEF != val and pI < len(parts):
                part = parts[pI]
                if part != S_MT:
                    val = getprop(val, part)

                pI += 1
         
    # State may provide a custom handler to modify found value.
    if state is not None and state is not UNDEF and hasattr(state, 'handler') and isfunc(state.handler):
        ref = pathify(path)
        val = state.handler(state, val, current, ref, store)

    return val


def inject(val: Any, store: Any, modify: Any = UNDEF, current: Any = UNDEF, state: Any = UNDEF) -> Any:
    """
    Inject values from `store` into `val` recursively, respecting backtick syntax.
    `modify` is an optional function(key, val, parent, state, current, store)
    that is called after each injection.
    """
    if state is UNDEF:
        # Create a root-level state
        parent = {S_DTOP: val}
        state = Injection(
            mode = S_MVAL,
            full = False,
            keyI = 0,
            keys = [S_DTOP],
            key = S_DTOP,
            val = val,
            parent = parent,
            path = [S_DTOP],
            nodes = [parent],
            handler = _injecthandler,
            base = S_DTOP,
            modify = modify,
            meta = {},
            errs = getprop(store, S_DERRS, []),
            dparent = parent
        )

    # For local paths, we keep track of the current node in `current`.
    if current is UNDEF:
        current = {S_DTOP: store}
    elif state.path == [S_DTOP]:
        # Only apply the parent key navigation logic at the root level
        # Get parent key from path, but handle edge cases where path is too short
        parentkey = getprop(state.path, len(state.path)-2) if len(state.path) > 2 else UNDEF
        current = current if UNDEF == parentkey else getprop(current, parentkey)

    # Descend into node
    if isnode(val):
        # Sort keys (transforms with `$...` go last).
        if ismap(val):
            normal_keys = [k for k in val.keys() if S_DS not in k]
            normal_keys.sort()
            transform_keys = [k for k in val.keys() if S_DS in k]
            transform_keys.sort()
            nodekeys = normal_keys + transform_keys
            
        else:
            nodekeys = list(range(len(val)))

        nkI = 0
        while nkI < len(nodekeys):
            nodekey = str(nodekeys[nkI])

            childpath = state.path + [nodekey]
            childnodes = state.nodes + [val]
            childval = getprop(val, nodekey)

            # Create child state for key-pre phase
            childstate = Injection(
                mode = S_MKEYPRE,
                full = False,
                keyI = nkI,
                keys = nodekeys,
                key = nodekey,
                val = childval,
                parent = val,
                path = childpath,
                nodes = childnodes,
                handler = state.handler,  # Inherit handler from parent state
                base = state.base,
                errs = state.errs,
                meta = state.meta,
                dparent = state.dparent
            )
            
            # Inherit parent_data from parent state if it exists
            if hasattr(state, 'parent_data'):
                childstate.parent_data = state.parent_data

            prekey = _injectstr(str(nodekey), store, current, childstate)

            # The injection may modify child processing.
            nkI = childstate.keyI
            
            # Log EACH transform processing
            if 'EACH' in str(nodekey):
                print(f"INJECT LOG: Processing EACH transform key: {nodekey}")
                print(f"INJECT LOG: Pre-key result: {prekey}")
                print(f"INJECT LOG: Child state after key-pre: keyI={childstate.keyI}")

            if prekey is not UNDEF:
                # Phase 2: val
                child_val = getprop(val, prekey)
                childstate.mode = S_MVAL

                # Compute the current context for the child by navigating to the corresponding data path
                child_current = current
                if current is not UNDEF and ismap(current) and S_DTOP in current:
                    # Navigate to the data path corresponding to the child path
                    data_root = getprop(current, S_DTOP)
                    # Skip $TOP in the path and navigate to the current level
                    child_path = childstate.path[1:]  # Remove $TOP from path
                    child_data = data_root
                    for path_segment in child_path[:-1]:  # Navigate to parent, not to the child itself
                        child_data = getprop(child_data, path_segment)
                        if child_data is UNDEF or child_data is None:
                            break
                    # Update current to point to the data at this level
                    if child_data is not UNDEF and child_data is not None:
                        child_current = {S_DTOP: child_data}

                # Perform the val mode injection on the child value.
                # NOTE: return value is not used.
                inject(child_val, store, modify, child_current, childstate)

                # The injection may modify child processing.
                nkI = childstate.keyI
                
                # Phase 3: key-post
                childstate.mode = S_MKEYPOST
                _injectstr(nodekey, store, current, childstate)

                # The injection may modify child processing.
                nkI = childstate.keyI

            nkI = nkI+1
            
    elif isinstance(val, str):
        state.mode = S_MVAL
        
        # Compute the current context for string injection similar to node recursion
        string_current = current
        if current is not UNDEF and ismap(current) and S_DTOP in current:
            # Navigate to the data path corresponding to the current path
            data_root = getprop(current, S_DTOP)
            # Skip $TOP in the path and navigate to the current level
            current_path = state.path[1:]  # Remove $TOP from path
            current_data = data_root
            for path_segment in current_path[:-1]:  # Navigate to parent, not to the current key itself
                current_data = getprop(current_data, path_segment)
                if current_data is UNDEF or current_data is None:
                    break
            # Update current to point to the data at this level
            if current_data is not UNDEF and current_data is not None:
                string_current = {S_DTOP: current_data}
        
        val = _injectstr(val, store, string_current, state)
        setprop(state.parent, state.key, val)

    # Custom modification
    if UNDEF != modify and modify is not None:
        mkey = state.key
        mparent = state.parent
        mval = getprop(mparent, mkey)
        modify(
            mval,
            mkey,
            mparent,
            state,
            current,
            store
        )

    return getprop(state.parent, S_DTOP)


# Default inject handler for transforms. If the path resolves to a function,
# call the function passing the injection state. This is how transforms operate.
def _injecthandler(state, val, current, ref, store):
    out = val
    iscmd = isfunc(val) and (UNDEF == ref or (isinstance(ref, str) and ref.startswith(S_DS)))

    # Only call val function if it is a special command ($NAME format).
    if iscmd:
        out = val(state, val, current, ref, store)

    # Update parent with value. Ensures references remain in node tree.
    else:
        if state.mode == S_MVAL and state.full:
            state.setval(val)

    return out


# -----------------------------------------------------------------------------
# Transform helper functions (these are injection handlers).


def transform_DELETE(state: Injection, _val: Any, _current: Any, _ref: str, _store: Any) -> Any:
    """
    Injection handler to delete a key from a map/list.
    """
    state.setval(UNDEF)
    return UNDEF


def transform_COPY(state: Injection, _val: Any, current: Any, _ref: str, _store: Any) -> Any:
    """
    Injection handler to copy a value from source data under the same key.
    """
    mode = state.mode
    key = state.key
    parent = state.parent

    out = UNDEF
    if mode.startswith('key'):
        out = key
    else:
        # Find the source data
        if current is not None:
            # Check if current contains the store structure with $TOP
            if ismap(current) and S_DTOP in current:
                # Current contains the store, which has the source data under $TOP
                data = getprop(current, S_DTOP)
            else:
                # Current is the direct data item
                data = current
        else:
            # Navigate using the store and state path to find the correct data
            data = getprop(_store, S_DTOP)
            # Remove the last element (key) and navigate to the parent data
            parent_path = state.path[1:-1]  # Skip $TOP and the current key
            for path_segment in parent_path:
                data = getprop(data, path_segment)
        
        # Handle root-level $COPY (where key is $TOP)
        if key == S_DTOP:
            out = data
        else:
            out = getprop(data, key)
        
        state.setval(out)

    return out


def transform_KEY(state: Injection, _val: Any, current: Any, _ref: str, _store: Any) -> Any:
    """
    Injection handler to inject the parent's key (or a specified key).
    """
    print(f"\n!!! transform_KEY CALLED !!!")
    print(f"KEY LOG: State mode: {state.mode}")
    print(f"KEY LOG: State path: {state.path}")
    print(f"KEY LOG: Parent: {stringify(state.parent)}")
    print(f"KEY LOG: Current: {stringify(current)}")
    print(f"KEY LOG: S_DKEY constant: {S_DKEY}")
    
    mode = state.mode
    path = state.path
    parent = state.parent

    if mode != S_MVAL:
        print(f"KEY LOG: Not in val mode, returning UNDEF")
        return UNDEF

    keyspec = getprop(parent, S_DKEY)
    print(f"KEY LOG: keyspec from parent[{S_DKEY}]: {keyspec}")
    
    if keyspec is not UNDEF:
        # Need to use setprop directly here since we're removing a specific key (S_DKEY)
        # not the current state's key
        print(f"KEY LOG: Found keyspec '{keyspec}', removing {S_DKEY} from parent")
        setprop(parent, S_DKEY, UNDEF)
        result = getprop(current, keyspec)
        print(f"KEY LOG: getprop(current, '{keyspec}') = {result}")
        print("=== transform_KEY Exit (keyspec path) ===\n")
        return result

    meta = getprop(parent, S_DMETA)
    print(f"KEY LOG: No keyspec, checking meta: {stringify(meta)}")
    fallback_key = getprop(path, len(path) - 2)
    print(f"KEY LOG: Fallback key from path[{len(path) - 2}]: {fallback_key}")
    result = getprop(meta, S_KEY, fallback_key)
    print(f"KEY LOG: Final result: {result}")
    print("=== transform_KEY Exit (meta path) ===\n")
    return result


def transform_META(state: Injection, _val: Any, _current: Any, _ref: str, _store: Any) -> Any:
    """
    Injection handler that removes the `'$META'` key (after capturing if needed).
    """
    print(f"\n=== transform_META Entry ===")
    print(f"META LOG: S_DMETA constant: {S_DMETA}")
    print(f"META LOG: Parent before: {stringify(state.parent)}")
    
    parent = state.parent
    setprop(parent, S_DMETA, UNDEF)
    
    print(f"META LOG: Parent after: {stringify(parent)}")
    print("=== transform_META Exit ===\n")
    return UNDEF


def transform_MERGE(state: Injection, _val: Any, current: Any, _ref: str, store: Any) -> Any:
    """
    Injection handler to merge a list of objects onto the parent object.
    If the transform data is an empty string, merge the top-level store.
    """
    mode = state.mode
    key = state.key
    parent = state.parent

    if mode == S_MKEYPRE:
        return key

    if mode == S_MKEYPOST:
        args = getprop(parent, key)
        
        if args == S_MT:
            args = [store[S_DTOP]]
        elif not islist(args):
            args = [args]

        state.setval(UNDEF)  # Using setval instead of setprop

        # Merge them on top of parent
        mergelist = [parent] + args + [clone(parent)]
        merge(mergelist)
        return key

    return UNDEF


def transform_EACH(state: Injection, _val: Any, current: Any, _ref: str, store: Any) -> Any:
    """
    Injection handler to convert the current node into a list by iterating over
    a source node. Format: ['`$EACH`','`source-path`', child-template]
    """
    mode = state.mode
    keys_ = state.keys
    path = state.path
    parent = state.parent
    nodes_ = state.nodes

    print(f"\n=== transform_EACH Entry ===")
    print(f"EACH LOG: mode: {mode}")
    print(f"EACH LOG: keys_: {keys_}")
    print(f"EACH LOG: path: {path}")
    print(f"EACH LOG: parent: {stringify(parent)}")
    print(f"EACH LOG: nodes_: {nodes_}")
    print(f"EACH LOG: current: {stringify(current)}")
    print(f"EACH LOG: store keys: {list(store.keys()) if store else 'None'}")

    if keys_ is not UNDEF:
        # Only keep the transform item (first). Avoid further spurious keys.
        keys_[:] = keys_[:1]

    print(f"EACH LOG: keys_ after: {keys_}")

    if mode != S_MVAL or path is UNDEF or nodes_ is UNDEF:
        print(f"EACH LOG: Early return - mode={mode}, path={path}, nodes_={nodes_}")
        return UNDEF

    print(f"EACH LOG: path after: {path}")
    print(f"EACH LOG: nodes_ after: {nodes_}")

    # parent here is the array [ '$EACH', 'source-path', {... child ...} ]
    srcpath = parent[1] if len(parent) > 1 else UNDEF
    child_template = clone(parent[2]) if len(parent) > 2 else UNDEF

    print(f"EACH LOG: srcpath: {srcpath}")
    print(f"EACH LOG: child_template: {stringify(child_template)}")
    
    # Source data
    srcstore = getprop(store, state.base, store)
    print(f"EACH LOG: state.base: {state.base}")
    print(f"EACH LOG: srcstore: {stringify(srcstore)}")
    
    src = getpath(srcpath, srcstore, current)
    print(f"EACH LOG: getpath('{srcpath}', srcstore, current) = {stringify(src)}")
    
    # Create result array
    tval = []

    tkey = path[-2] if len(path) >= 2 else UNDEF
    target = nodes_[-2] if len(nodes_) >= 2 else nodes_[-1]

    print(f"EACH LOG: tkey: {tkey}")
    print(f"EACH LOG: target: {stringify(target)}")

    if isnode(src):
        print(f"EACH LOG: src is node")
        if islist(src):
            print(f"EACH LOG: src is list with {len(src)} items")
            # For each item in source array, inject with that specific item as current
            for i, src_item in enumerate(src):
                print(f"\n--- EACH LOG: Processing list item {i} ---")
                print(f"EACH LOG: src_item: {stringify(src_item)}")
                # Clone the child template for this item
                item_template = clone(child_template)
                print(f"EACH LOG: item_template: {stringify(item_template)}")
                # Use the individual item directly as current
                item_current = src_item
                print(f"EACH LOG: item_current: {stringify(item_current)}")
                # Create proper injection state that provides access to parent data
                item_parent = {S_DTOP: item_template}
                print(f"EACH LOG: item_parent: {stringify(item_parent)}")
                item_state = Injection(
                    mode = S_MVAL,
                    full = False,
                    keyI = 0,
                    keys = [S_DTOP],
                    key = S_DTOP,
                    val = item_template,
                    parent = item_parent,
                    path = [S_DTOP],
                    nodes = [item_parent],
                    handler = state.handler,
                    base = state.base,
                    modify = state.modify,
                    meta = {},
                    errs = state.errs,
                    dparent = state.dparent
                )
                print(f"EACH LOG: item_state created with mode={item_state.mode}, handler={item_state.handler}")
                # Set up parent access for ... navigation
                item_state.parent_data = srcstore
                print(f"EACH LOG: item_state.parent_data: {stringify(item_state.parent_data)}")
                print(f"DEBUG EACH: About to call inject() for item {i}")
                print(f"DEBUG EACH: item_template = {stringify(item_template)}")
                print(f"DEBUG EACH: store keys = {list(store.keys())}")
                print(f"DEBUG EACH: item_current = {stringify(item_current)}")
                print(f"DEBUG EACH: item_state.handler = {item_state.handler}")
                
                # Inject this specific item template
                injected_item = inject(item_template, store, state.modify, item_current, item_state)
                print(f"DEBUG EACH: inject() returned: {stringify(injected_item)}")
                tval.append(injected_item)
                print(f"--- EACH LOG: Finished processing list item {i} ---\n")
        else:
            print(f"EACH LOG: src is object with keys: {list(src.keys()) if ismap(src) else 'not a map'}")
            # Convert dict to a list of child templates
            for idx, (k, v) in enumerate(src.items()):
                print(f"\n--- EACH LOG: Processing object item {idx}: key='{k}' ---")
                print(f"EACH LOG: object value v: {stringify(v)}")
                # Clone child template
                item_template = clone(child_template)
                print(f"EACH LOG: cloned item_template: {stringify(item_template)}")
                # Keep key in meta for usage by `$KEY`
                item_template[S_DMETA] = {S_KEY: k}
                print(f"EACH LOG: added meta to template: {stringify(item_template)}")
                
                # Use the individual item directly as current
                item_current = v
                print(f"EACH LOG: item_current: {stringify(item_current)}")
                
                # Create proper injection state that provides access to parent data
                item_parent = {S_DTOP: item_template}
                print(f"EACH LOG: item_parent: {stringify(item_parent)}")
                item_state = Injection(
                    mode = S_MVAL,
                    full = False,
                    keyI = 0,
                    keys = [S_DTOP],
                    key = S_DTOP,
                    val = item_template,
                    parent = item_parent,
                    path = [S_DTOP],
                    nodes = [item_parent],
                    handler = state.handler,
                    base = state.base,
                    modify = state.modify,
                    meta = {},
                    errs = state.errs,
                    dparent = state.dparent
                )
                print(f"EACH LOG: item_state created with mode={item_state.mode}, handler={item_state.handler}")
                # Set up parent access for ... navigation
                item_state.parent_data = srcstore
                print(f"EACH LOG: item_state.parent_data: {stringify(item_state.parent_data)}")
                print(f"DEBUG EACH: About to call inject() for object item '{k}'")
                print(f"DEBUG EACH: item_template = {stringify(item_template)}")
                print(f"DEBUG EACH: store keys = {list(store.keys())}")
                print(f"DEBUG EACH: item_current = {stringify(item_current)}")
                print(f"DEBUG EACH: item_state.handler = {item_state.handler}")
                
                # Inject this specific item template
                injected_item = inject(item_template, store, state.modify, item_current, item_state)
                print(f"DEBUG EACH: inject() returned: {stringify(injected_item)}")
                tval.append(injected_item)
                print(f"--- EACH LOG: Finished processing object item '{k}' ---\n")
    else:
        print(f"EACH LOG: src is not a node: {stringify(src)}")

    _updateAncestors(state, target, tkey, tval)

    print(f"EACH LOG: final tval: {stringify(tval)}")
    
    # Prevent callee from damaging first list entry (since we are in `val` mode).
    result = tval[0] if tval else UNDEF

    print(f"EACH LOG: final result: {stringify(result)}")
    print("=== transform_EACH Exit ===\n")
    
    return result


def transform_PACK(state: Injection, _val: Any, current: Any, _ref: str, store: Any) -> Any:
    """
    Injection handler to convert the current node into a dict by "packing"
    a source list or dict. Format: { '`$PACK`': [ 'source-path', {... child ...} ] }
    """
    mode = state.mode
    key = state.key
    path = state.path
    parent = state.parent
    nodes_ = state.nodes

    if (mode != S_MKEYPRE or not isinstance(key, str) or path is UNDEF or nodes_ is UNDEF):
        return UNDEF

    args = parent[key]
    if not args or not islist(args):
        return UNDEF

    srcpath = args[0] if len(args) > 0 else UNDEF
    child_template = clone(args[1]) if len(args) > 1 else UNDEF

    tkey = path[-2] if len(path) >= 2 else UNDEF
    target = nodes_[-2] if len(nodes_) >= 2 else nodes_[-1]

    # source data
    srcstore = getprop(store, state.base, store)
    src = getpath(srcpath, srcstore, current)

    # Prepare source as a list
    if islist(src):
        pass
    elif ismap(src):
        new_src = []
        for k, v in src.items():
            if ismap(v):
                # Keep KEY meta
                v_copy = clone(v)
                v_copy[S_DMETA] = {S_KEY: k}
                new_src.append(v_copy)
        src = new_src
    else:
        return UNDEF

    if src is UNDEF:
        return UNDEF

    # Child key from template
    childkey = getprop(child_template, S_DKEY)
    # Remove the transform key from template
    setprop(child_template, S_DKEY, UNDEF)

    # Build a new dict in parallel with the source
    tval = {}
    for elem in src:
        if childkey is not UNDEF:
            kn = getprop(elem, childkey)
        else:
            # fallback
            kn = getprop(elem, S_KEY)
        if kn is UNDEF:
            # Possibly from meta
            meta = getprop(elem, S_DMETA, {})
            kn = getprop(meta, S_KEY, UNDEF)

        if kn is not UNDEF:
            # Create child state for each key
            child_state = state.child(0, [kn])
            tval[kn] = clone(child_template)
            # Transfer meta if present
            tmeta = getprop(elem, S_DMETA)
            if tmeta is not UNDEF:
                tval[kn][S_DMETA] = tmeta

    # Build parallel "current"
    tcurrent = {}
    for elem in src:
        if childkey is not UNDEF:
            kn = getprop(elem, childkey)
        else:
            kn = getprop(elem, S_KEY)
        if kn is UNDEF:
            meta = getprop(elem, S_DMETA, {})
            kn = getprop(meta, S_KEY, UNDEF)
        if kn is not UNDEF:
            tcurrent[kn] = elem

    tcurrent = {S_DTOP: tcurrent}

    # Build substructure
    tval = inject(tval, store, state.modify, tcurrent)
    
    _updateAncestors(state, target, tkey, tval)

    # Drop the transform key
    return UNDEF


def transform_REF(state: Injection, _val: Any, _current: Any, _ref: str, store: Any) -> Any:
    """
    Reference original spec (enables recursive transformations)
    Format: ['`$REF`', '`spec-path`']
    """
    nodes = state.nodes
    modify = state.modify

    if state.mode != S_MVAL:
        return UNDEF

    # Get arguments: ['`$REF`', 'ref-path']
    refpath = getprop(state.parent, 1)
    state.keyI = len(state.keys)

    # Spec reference
    spec_func = getprop(store, S_DSPEC)
    if not callable(spec_func):
        return UNDEF
    spec = spec_func()
    ref = getpath(refpath, spec)

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

    cpath = slice(state.path, 0, len(state.path)-3)
    tpath = slice(state.path, 0, len(state.path)-1)
    tcur = getpath(cpath, store)
    tval = getpath(tpath, store)
    rval = UNDEF

    if not hasSubRef or tval is not UNDEF:
        # Create child state for the next level
        child_state = state.child(0, [getelem(tpath, -1)])
        child_state.path = tpath
        child_state.nodes = slice(state.nodes, 0, len(state.nodes)-1)
        child_state.parent = getelem(nodes, -2)
        child_state.val = tref

        # Inject with child state
        inject(tref, store, modify, tcur, child_state)
        rval = child_state.val
    else:
        rval = UNDEF

    # Set the value in grandparent, using setval
    state.setval(rval, 2)
    
    # Handle lists by decrementing keyI
    if islist(state.parent) and state.prior:
        state.prior.keyI -= 1

    return _val


def transform(
        data: Any,
        spec: Any,
        extra: Any = UNDEF,
        modify: Any = UNDEF
) -> Any:
    """
    Transform data using spec.
    Only operates on static JSON-like data.
    Arrays are treated as if they are objects with indices as keys.
    """

    # Clone the spec so that the clone can be modified in place as the transform result.
    spec = clone(spec)

    extraTransforms = {}
    extraData = {} if UNDEF == extra else {}
    
    if UNDEF != extra:
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
        
        # Escape backtick (this also works inside backticks).
        '$BT': lambda state, val, current, ref, store: S_BT,
        
        # Escape dollar sign (this also works inside backticks).
        '$DS': lambda state, val, current, ref, store: S_DS,
        
        # Insert current date and time as an ISO string.
        '$WHEN': lambda state, val, current, ref, store: datetime.utcnow().isoformat(),

        '$DELETE': transform_DELETE,
        '$COPY': transform_COPY,
        '$KEY': transform_KEY,
        '$META': transform_META,
        '$MERGE': transform_MERGE,
        '$EACH': transform_EACH,
        '$PACK': transform_PACK,
        '$REF': transform_REF,
    }

    # Add validation handlers to store if they exist in extra
    if isinstance(extra, dict) and 'extra' in extra:
        validation_store = extra['extra']
        if isinstance(validation_store, dict):
            for k, v in validation_store.items():
                if k.startswith('$') and callable(v):
                    store[k] = v
                # Also copy the error array if it exists
                elif k == '$ERRS':
                    store[k] = v

    # Add any custom extra transforms
    store.update(extraTransforms)

    # Check if a custom handler was provided in extra
    custom_handler = None
    if isinstance(extra, dict) and 'handler' in extra:
        custom_handler = extra['handler']

    # Create initial state with custom handler if provided
    if custom_handler:
        parent = {S_DTOP: spec}
        dparent = extra.get('dparent', parent) if isinstance(extra, dict) else parent
        
        state = Injection(
            mode = S_MVAL,
            full = False,
            keyI = 0,
            keys = [S_DTOP],
            key = S_DTOP,
            val = spec,
            parent = parent,
            path = [S_DTOP],
            nodes = [parent],
            handler = custom_handler,
            base = S_DTOP,
            modify = modify,
            meta = {},
            errs = getprop(store, S_DERRS, []),
            dparent = dparent
        )
        out = inject(spec, store, modify, store, state)
    else:
        # Pass the store as current so that transforms can access the data via store[$TOP]
        out = inject(spec, store, modify, store)
    
    return out


def validate_STRING(state: Injection, _val: Any, current: Any, _ref: str, store: Any) -> Any:
    """
    A required string value. Rejects empty strings.
    """
    # Use the _val parameter which contains the actual data value
    out = _val
    
    # Handle null/undefined values specially
    if out is None or out is UNDEF:
        state.errs.append("Expected string, but found no value.")
        return UNDEF

    t = typify(out)

    if t == S_string:
        if out == S_MT:
            state.errs.append(f"Empty string at {pathify(state.path,1)}")
            return UNDEF
        else:
            return out
    else:
        state.errs.append(_invalidTypeMsg(state.path, S_string, t, out, 'V1010'))
        return UNDEF


def validate_NUMBER(state: Injection, _val: Any, current: Any, _ref: str, store: Any) -> Any:
    """
    A required number value (int or float).
    """
    # Get the actual value from the data parent
    data_root = getprop(state.dparent, S_DTOP, state.dparent)
    
    # If we're at the root level ($TOP), use the data directly
    if state.key == S_DTOP:
        out = data_root
    else:
        out = getprop(data_root, state.key)
    
    t = typify(out)

    if t != S_number:
        error_msg = _invalidTypeMsg(state.path, S_number, t, out, 'V1020')
        state.errs.append(error_msg)
        return UNDEF
    
    return out


def validate_BOOLEAN(state: Injection, _val: Any, current: Any, _ref: str, store: Any) -> Any:
    """
    A required boolean value.
    """
    # Get the actual value from the data parent
    data_root = getprop(state.dparent, S_DTOP, state.dparent)
    
    # If we're at the root level ($TOP), use the data directly
    if state.key == S_DTOP:
        out = data_root
    else:
        out = getprop(data_root, state.key)
    
    t = typify(out)

    if t != S_boolean:
        state.errs.append(_invalidTypeMsg(state.path, S_boolean, t, out, 'V1030'))
        return UNDEF
    return out


def validate_OBJECT(state: Injection, _val: Any, current: Any, _ref: str, store: Any) -> Any:
    """
    A required object (dict), contents not further validated by this step.
    """
    # Get the actual value from the data parent
    data_root = getprop(state.dparent, S_DTOP, state.dparent)
    
    # If we're at the root level ($TOP), use the data directly
    if state.key == S_DTOP:
        out = data_root
    else:
        out = getprop(data_root, state.key)
    
    t = typify(out)

    if out is UNDEF or t != S_object:
        state.errs.append(_invalidTypeMsg(state.path, S_object, t, out, 'V1040'))
        return UNDEF
    return out


def validate_ARRAY(state: Injection, _val: Any, current: Any, _ref: str, store: Any) -> Any:
    """
    A required list, contents not further validated by this step.
    """
    # Get the actual value from the data parent
    data_root = getprop(state.dparent, S_DTOP, state.dparent)
    
    # If we're at the root level ($TOP), use the data directly
    if state.key == S_DTOP:
        out = data_root
    else:
        out = getprop(data_root, state.key)
    
    t = typify(out)

    if t != S_array:
        state.errs.append(_invalidTypeMsg(state.path, S_array, t, out, 'V1050'))
        return UNDEF
    return out


def validate_FUNCTION(state: Injection, _val: Any, current: Any, _ref: str, store: Any) -> Any:
    """
    A required function (callable in Python).
    """
    # Get the actual value from the data parent
    data_root = getprop(state.dparent, S_DTOP, state.dparent)
    
    # If we're at the root level ($TOP), use the data directly
    if state.key == S_DTOP:
        out = data_root
    else:
        out = getprop(data_root, state.key)
    
    t = typify(out)

    if t != S_function:
        state.errs.append(_invalidTypeMsg(state.path, S_function, t, out, 'V1060'))
        return UNDEF
    return out


def validate_ANY(state: Injection, _val: Any, current: Any, _ref: str, store: Any) -> Any:
    """
    Allow any value.
    """
    # Get the actual value from the data parent
    data_root = getprop(state.dparent, S_DTOP, state.dparent)
    
    # If we're at the root level ($TOP), use the data directly
    if state.key == S_DTOP:
        return data_root
    else:
        return getprop(data_root, state.key)


def validate_CHILD(state: Injection, _val: Any, current: Any, _ref: str, store: Any) -> Any:
    """Validate each child of an object or array against a template, matching TS logic."""
    mode = state.mode
    parent = state.parent
    keys_ = state.keys
    path = state.path
    keyI = state.keyI

    # Extract the actual data to validate from the validation context
    if hasattr(state, 'dparent') and state.dparent is not None:
        data_root = getprop(state.dparent, S_DTOP, state.dparent)
        
        if state.key == S_DTOP:
            actual_current = data_root
        elif mode == S_MKEYPRE and str(state.key).startswith('`$'):
            # In key:pre mode, if we're processing a validator key like `$CHILD`,
            # we need to extract the parent field, not the validator directive
            if len(state.path) >= 2:
                field_name = state.path[-2]  # Get the parent field name (e.g., 'q')
                actual_current = getprop(data_root, field_name)
            else:
                actual_current = data_root
        elif mode == S_MKEYPOST and str(state.key).startswith('`$'):
            # In key:post mode, the validation has already been done in key:pre mode
            # Just return without doing anything to avoid duplication
            return None
        else:
            actual_current = getprop(data_root, state.key)
    else:
        # Fallback to trying to extract from current
        if isinstance(current, dict) and S_DTOP in current:
            actual_current = current[S_DTOP]
        else:
            actual_current = current

    # Handle both key:pre mode (when $CHILD is a key) and val mode (when $CHILD is array element)
    if S_MVAL == mode:
        if not islist(parent) or 0 != keyI:
            state.errs.append('The $CHILD validator at field ' +
                            pathify(state.path, 1, 1) +
                            ' must be the first element of an array.')
            return None
            
        state.keyI = len(state.keys)
        
        state.path = state.path[:-1]
        state.key = state.path[-1]
        
        # Get the child template (second element of the array)
        childtm = parent[1] if len(parent) > 1 else UNDEF
        
        if childtm is UNDEF:
            state.errs.append('The $CHILD validator at field ' +
                            pathify(state.path, 1, 1) +
                            ' must have a child template.')
            return None

    elif mode == S_MKEYPRE:  # key:pre mode
        # In key:pre mode, we're processing $CHILD as a key in an object
        # We need to transform this into the array-based syntax and process it
        # Check for both "`$CHILD`" (with backticks) and "$CHILD" (without backticks)
        child_key = "`$CHILD`" if "`$CHILD`" in parent else (S_DCHILD if S_DCHILD in parent else None)
        
        if ismap(parent) and child_key:
            childtm = parent[child_key]
            
            # Update path to remove the $CHILD key part
            state.path = state.path[:-1]  # Remove the $CHILD part
            # Don't change state.key here - it will be handled properly in the parent
            
        else:
            state.errs.append('The $CHILD validator at field ' +
                            pathify(state.path, 1, 1) +
                            ' is malformed.')
            return None
            
    elif mode == S_MKEYPOST:  # key:post mode
        # In key:post mode, the validation has already been done in key:pre mode
        # Just return without doing anything to avoid duplication
        return None
    else:
        state.setval(UNDEF)
        return None

    # Common validation logic for both modes
    
    # Ensure we have a child template
    if 'childtm' not in locals():
        state.errs.append('The $CHILD validator at field ' +
                        pathify(state.path, 1, 1) +
                        ' must have a child template.')
        return None

    # Validate based on the type of data
    if ismap(actual_current):
        validated_obj = {}
        for child_key, child_val in actual_current.items():
            # Create a new validation store for this child
            vstore = {
                "$DELETE": UNDEF,
                "$COPY": UNDEF,
                "$KEY": UNDEF,
                "$META": UNDEF,
                "$MERGE": UNDEF,
                "$EACH": UNDEF,
                "$PACK": UNDEF,
                "$STRING": validate_STRING,
                "$NUMBER": validate_NUMBER,
                "$BOOLEAN": validate_BOOLEAN,
                "$OBJECT": validate_OBJECT,
                "$ARRAY": validate_ARRAY,
                "$FUNCTION": validate_FUNCTION,
                "$ANY": validate_ANY,
                "$CHILD": validate_CHILD,
                "$ONE": validate_ONE,
                "$EXACT": validate_EXACT,
                S_DTOP: child_val
            }
            
            # Add any extra validators from the original store
            if UNDEF != store:
                for k, v in store.items():
                    if k not in vstore:
                        vstore[k] = v
            
            # Validate the child against the template
            try:
                validated = validate(child_val, childtm, vstore, [])
                validated_obj[child_key] = validated
            except ValueError as e:
                # If validation failed, preserve the original value
                validated_obj[child_key] = child_val

        # Set the validated result
        if mode == S_MVAL:
            state.setval(validated_obj, 2)
        elif mode == S_MKEYPRE:
            # In key:pre mode, don't setval here - let the parent handle it
            return validated_obj
        else:
            # For key:post mode, set the value directly 
            state.setval(validated_obj)
        return validated_obj

    elif islist(actual_current):
        validated_arr = []
        for i, child_val in enumerate(actual_current):
            # Create a new validation store for this child
            vstore = {
                "$DELETE": UNDEF,
                "$COPY": UNDEF,
                "$KEY": UNDEF,
                "$META": UNDEF,
                "$MERGE": UNDEF,
                "$EACH": UNDEF,
                "$PACK": UNDEF,
                "$STRING": validate_STRING,
                "$NUMBER": validate_NUMBER,
                "$BOOLEAN": validate_BOOLEAN,
                "$OBJECT": validate_OBJECT,
                "$ARRAY": validate_ARRAY,
                "$FUNCTION": validate_FUNCTION,
                "$ANY": validate_ANY,
                "$CHILD": validate_CHILD,
                "$ONE": validate_ONE,
                "$EXACT": validate_EXACT,
                S_DTOP: child_val
            }
            
            # Add any extra validators from the original store
            if UNDEF != store:
                for k, v in store.items():
                    if k not in vstore:
                        vstore[k] = v
            
            # Validate the element against the template
            try:
                validated = validate(child_val, childtm, vstore, [])
                validated_arr.append(validated)
            except ValueError as e:
                # If validation failed, preserve the original value
                validated_arr.append(child_val)

        # Set the validated result
        if mode == S_MVAL:
            state.setval(validated_arr, 2)
        elif mode == S_MKEYPRE:
            # In key:pre mode, don't setval here - let the parent handle it
            return validated_arr
        else:
            # For key:post mode, set the value directly
            state.setval(validated_arr)
        return validated_arr

    else:
        state.errs.append(_invalidTypeMsg(
            state.path, 'object or array', typify(actual_current), actual_current, 'VCHILD'))
        return None


def validate_ONE(state: Injection, _val: Any, current: Any, _ref: str, store: Any) -> Any:
    """
    Match at least one of the specified shapes.
    Syntax: ['`$ONE`', alt0, alt1, ...]
    """
    mode = state.mode
    parent = state.parent
    path = state.path
    keyI = state.keyI
    nodes = state.nodes

    # Extract the actual data to validate from the validation context
    if hasattr(state, 'dparent') and state.dparent is not None:
        data_root = getprop(state.dparent, S_DTOP, state.dparent)
        
        # For $ONE validation, we need to extract the specific field being validated
        # The path structure is typically ['$TOP', 'field_name', '0'] where '0' is the $ONE index
        # Special case: if path is ['$TOP', '0'], we're validating the top-level data directly
        if state.key == S_DTOP:
            actual_current = data_root
        elif len(state.path) == 2 and state.path[0] == S_DTOP and str(state.key).isdigit():
            # Top-level $ONE validation: path is ['$TOP', '0']
            actual_current = data_root
        elif isinstance(state.key, (int, str)) and str(state.key).isdigit() and len(state.path) >= 3:
            # Field-level $ONE validation - extract the field being validated
            # The field name is the second-to-last element in the path
            field_name = state.path[-2]
            actual_current = getprop(data_root, field_name, UNDEF)
        else:
            actual_current = data_root
    else:
        actual_current = getprop(current, S_DTOP, current)

    print(f"VALIDATE ONE: Extracted - mode={mode}, keyI={keyI}")
    print(f"VALIDATE ONE: parent = {stringify(parent)}")
    print(f"VALIDATE ONE: nodes = {stringify(nodes)}")

    # Only operate in val mode, since parent is a list.
    if S_MVAL == mode:
        print("VALIDATE ONE: Operating in val mode")
        
        if not islist(parent) or 0 != keyI:
            print(f"VALIDATE ONE: Error - parent is not list ({islist(parent)}) or keyI != 0 ({keyI})")
            state.errs.append('The $ONE validator at field ' +
                            pathify(state.path, 1, 1) +
                            ' must be the first element of an array.')
            return None
            
        state.keyI = len(state.keys)
        
        # Clean up structure, replacing [$ONE, ...] with current
        state.setval(actual_current, 2)
        
        state.path = state.path[:-1]
        state.key = state.path[-1]
        
        tvals = parent[1:]
        
        if 0 == len(tvals):
            state.errs.append('The $ONE validator at field ' +
                            pathify(state.path, 1, 1) +
                            ' must have at least one argument.')
            return None
            
        for i, tval in enumerate(tvals):
            # Create a new validation store for this attempt - SHARE the error array from parent
            vstore = {
                "$DELETE": UNDEF,
                "$COPY": UNDEF,
                "$KEY": UNDEF,
                "$META": UNDEF,
                "$MERGE": UNDEF,
                "$EACH": UNDEF,
                "$PACK": UNDEF,
                "$STRING": validate_STRING,
                "$NUMBER": validate_NUMBER,
                "$BOOLEAN": validate_BOOLEAN,
                "$OBJECT": validate_OBJECT,
                "$ARRAY": validate_ARRAY,
                "$FUNCTION": validate_FUNCTION,
                "$ANY": validate_ANY,
                "$CHILD": validate_CHILD,
                "$ONE": validate_ONE,
                "$EXACT": validate_EXACT,
                S_DTOP: actual_current
            }
            
            # Add any extra validators from the original store
            if UNDEF != store:
                for k, v in store.items():
                    if k not in vstore:
                        vstore[k] = v
            
            # Create a new error list for this attempt - BUT separate from parent errors
            # We only propagate errors to parent if ALL alternatives fail
            terrs = []
            vstore["$ERRS"] = terrs
            
            # Try to validate against this alternative
            try:
                # If the alternative is an object with a single key, wrap actual_current accordingly
                if ismap(tval) and len(tval) == 1:
                    key = list(tval.keys())[0]
                    if ismap(actual_current) and key in actual_current:
                        data_to_validate = {key: actual_current[key]}
                    else:
                        data_to_validate = actual_current
                else:
                    data_to_validate = actual_current
                
                vcurrent = validate(data_to_validate, tval, vstore, terrs)
                
                # If no errors, we found a match
                if 0 == len(terrs):
                    # Return only the validated data, not the entire store
                    if ismap(vcurrent) and S_DTOP in vcurrent:
                        result = vcurrent[S_DTOP]
                        return result
                    return vcurrent
                    
            except ValueError as e:
                continue
                
        # There was no match - NOW we propagate errors to parent
        valdesc = ", ".join(stringify(v) for v in tvals)
        valdesc = re.sub(r"`\$([A-Z]+)`", lambda m: m.group(1).lower(), valdesc)
        
        # If we're validating against an array spec but got a non-array value,
        # add a more specific error message
        if islist(tvals[0]) and not islist(actual_current):
            state.errs.append(_invalidTypeMsg(
                state.path,
                S_array,
                typify(actual_current), actual_current, 'V0210'))
        else:
            state.errs.append(_invalidTypeMsg(
                state.path,
                (1 < len(tvals) and "one of " or "") + valdesc,
                typify(actual_current), actual_current, 'V0210'))
    else:
        state.setval(UNDEF)
        
    return None


def validate_EXACT(state: Injection, _val: Any, current: Any, _ref: str, store: Any) -> Any:
    """
    Match exactly one of the specified values.
    Syntax: ['`$EXACT`', val0, val1, ...]
    """
    mode = state.mode
    parent = state.parent
    key = state.key
    keyI = state.keyI
    path = state.path
    nodes = state.nodes

    # Extract the actual data to validate from the validation context
    if hasattr(state, 'dparent') and state.dparent is not None:
        data_root = getprop(state.dparent, S_DTOP, state.dparent)
        
        # For $EXACT validation at root level, we often have state.key as array index (0, 1, etc.)
        # but we want to validate against the entire data_root
        if state.key == S_DTOP:
            actual_current = data_root
        elif isinstance(state.key, (int, str)) and str(state.key).isdigit():
            # This is likely a $EXACT validation at root level where key is array index
            actual_current = data_root
        else:
            actual_current = getprop(data_root, state.key)
    else:
        # Fallback to trying to extract from current
        if isinstance(current, dict) and S_DTOP in current:
            actual_current = current[S_DTOP]
        else:
            actual_current = current

    # Only operate in val mode, since parent is a list.
    if S_MVAL == mode:
        if not islist(parent) or 0 != keyI:
            state.errs.append('The $EXACT validator at field ' +
                pathify(state.path, 1, 1) +
                ' must be the first element of an array.')
            return None

        state.keyI = len(state.keys)

        # Clean up structure, replacing [$EXACT, ...] with current
        state.setval(actual_current, 2)
        state.path = state.path[:-1]
        state.key = state.path[-1]

        tvals = parent[1:]
        if 0 == len(tvals):
            state.errs.append('The $EXACT validator at field ' +
                pathify(state.path, 1, 1) +
                ' must have at least one argument.')
            return None

        # See if we can find an exact value match.
        currentstr = None
        for tval in tvals:
            exactmatch = tval == actual_current

            if not exactmatch and isnode(tval):
                currentstr = stringify(actual_current) if currentstr is None else currentstr
                tvalstr = stringify(tval)
                exactmatch = tvalstr == currentstr

            if exactmatch:
                return None

        valdesc = ", ".join(stringify(v) for v in tvals)
        valdesc = re.sub(r"`\$([A-Z]+)`", lambda m: m.group(1).lower(), valdesc)

        state.errs.append(_invalidTypeMsg(
            state.path,
            ('' if 1 < len(state.path) else 'value ') +
            'exactly equal to ' + ('' if 1 == len(tvals) else 'one of ') + valdesc,
            typify(actual_current), actual_current, 'V0110'))
    else:
        state.setval(UNDEF)  # Using setval instead of setprop


def _validatehandler(state: Injection, val: Any, current: Any, ref: str, store: Any) -> Any:
    """
    Handler for validation transforms. Similar to _injecthandler but with special
    handling for validation functions.
    """
    out = val
    iscmd = isfunc(val) and (UNDEF == ref or (isinstance(ref, str) and ref.startswith(S_DS)))

    # Check for meta path pattern
    m = re.match(r'^([^$]+)\$=(.+)$', ref)
    ismetapath = m is not None

    if ismetapath:
        state.setval(['`$EXACT`', val])
        state.keyI = -1
        out = S_SKIP
    elif iscmd:
        # This is a validator function - call it with the actual data value
        # Get the actual value to validate from the data parent
        if hasattr(state, 'dparent') and state.dparent is not None:
            data_root = getprop(state.dparent, S_DTOP, state.dparent)
            
            # Handle the case where data_root is still wrapped (nested structure)
            if ismap(data_root) and S_DTOP in data_root:
                # Unwrap one more level
                data_root = getprop(data_root, S_DTOP, data_root)
            
            # If we're at the root level ($TOP), use the data directly
            if state.key == S_DTOP:
                actual_value = data_root
            else:
                actual_value = getprop(data_root, state.key)
        else:
            # Fallback to current
            actual_value = current
        
        # Call the validator with the actual value
        validator_result = val(state, actual_value, current, ref, store)
        
        # If validator returned a valid value, use it; otherwise preserve the original data
        if validator_result is not UNDEF and validator_result is not None:
            state.setval(validator_result)
            out = validator_result
        else:
            # Validator failed or returned None/UNDEF - preserve original data
            state.setval(actual_value)
            out = actual_value
    else:
        # Update parent with value if in val mode and full injection
        if state.mode == S_MVAL and state.full:
            state.setval(val)

    return out


def validate(data: Any, spec: Any, extra: Any = UNDEF, collecterrs: Any = UNDEF) -> Any:
    """
    Validate a data structure against a shape specification. The shape
    specification follows the "by example" principle. Plain data in
    the shape is treated as default values that also specify the
    required type. Thus shape {a:1} validates {a:2}, since the types
    (number) match, but not {a:'A'}. Shape {a:1} against data {}
    returns {a:1} as a=1 is the default value of the a key. Special
    validation commands (in the same syntax as transform) are also
    provided to specify required values. Thus shape {a:'`$STRING`'}
    validates {a:'A'} but not {a:1}. Empty map or list means the node
    is open, and if missing an empty default is inserted.
    """
    # Handle extra parameters like TypeScript version
    if isinstance(extra, dict) and 'errs' in extra:
        collecterrs = extra.get('errs')
        extra = extra.get('extra', UNDEF)
    
    errs = [] if UNDEF == collecterrs else collecterrs
    collect = collecterrs is not None

    store = {
        "$DELETE": UNDEF,
        "$COPY": UNDEF,
        "$KEY": UNDEF,
        "$META": UNDEF,
        "$MERGE": UNDEF,
        "$EACH": UNDEF,
        "$PACK": UNDEF,

        "$STRING": validate_STRING,
        "$NUMBER": validate_NUMBER,
        "$BOOLEAN": validate_BOOLEAN,
        "$OBJECT": validate_OBJECT,
        "$ARRAY": validate_ARRAY,
        "$FUNCTION": validate_FUNCTION,
        "$ANY": validate_ANY,
        "$CHILD": validate_CHILD,
        "$ONE": validate_ONE,
        "$EXACT": validate_EXACT,
    }

    if UNDEF != extra:
        store.update(extra)

    # A special top level value to collect errors.
    store["$ERRS"] = errs
        
    # Pass parameters like TypeScript version
    out = transform(data, spec, {
        'meta': extra.get('meta') if isinstance(extra, dict) else UNDEF,
        'extra': store,
        'handler': _validatehandler,
        'dparent': {S_DTOP: data}  # Set the data parent for validation
    }, _validation)

    if 0 < len(errs) and not collect:
        raise ValueError("Invalid data: " + " | ".join(errs))

    # Strip out validation metadata from the result
    def clean_validation_artifacts(obj):
        if isinstance(obj, dict):
            cleaned = {}
            for key, value in obj.items():
                # Skip validation command keys like `$CHILD`, `$ONE`, etc.
                if isinstance(key, str) and key.startswith('`$'):
                    continue
                # Only remove known internal keys, not user data
                elif isinstance(key, str) and key.startswith('$'):
                    known_internal = ['$TOP', '$BT', '$DS', '$WHEN', '$DELETE', '$COPY', 
                                    '$KEY', '$META', '$MERGE', '$EACH', '$PACK', '$REF',
                                    '$STRING', '$NUMBER', '$BOOLEAN', '$OBJECT', '$ARRAY',
                                    '$FUNCTION', '$ANY', '$CHILD', '$ONE', '$EXACT', '$ERRS',
                                    'extra', 'handler', 'meta', 'modify', 'dparent']
                    if key in known_internal:
                        continue
                
                # Recursively clean nested objects
                cleaned[key] = clean_validation_artifacts(value)
            return cleaned
        elif isinstance(obj, list):
            return [clean_validation_artifacts(item) for item in obj]
        else:
            return obj

    if isinstance(out, dict):
        # If the result is just the data under $TOP, return that
        if len(out) == 1 and S_DTOP in out:
            out = out[S_DTOP]
        
        # Clean all validation artifacts recursively
        out = clean_validation_artifacts(out)

    return out



# Internal utilities
# ==================


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
def _injectstr(val: Any, store: Any, current: Any = UNDEF, state: Any = UNDEF) -> str:
    """
    Inject values from a data store into a string. Not a public utility - used by
    `inject`.  Inject are marked with `path` where path is resolved
    with getpath against the store or current (if defined)
    arguments. See `getpath`.  Custom injection handling can be
    provided by state.handler (this is used for transform functions).
    The path can also have the special syntax $NAME999 where NAME is
    upper case letters only, and 999 is any digits, which are
    discarded. This syntax specifies the name of a transform, and
    optionally allows transforms to be ordered by alphanumeric sorting.
    """
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
        if UNDEF != state:
            state.full = True

        pathref = m.group(1)

        # Special escapes inside injection.
        if 3 < len(pathref):
            pathref = pathref.replace(r'$BT', S_BT).replace(r'$DS', S_DS)

        # Get the extracted path reference.
        if pathref.startswith(S_DS) and UNDEF != state and isfunc(state.handler):
            # This is a transform function, call the handler
            transform_func = getprop(store, pathref)
            if isfunc(transform_func):
                out = state.handler(state, transform_func, current, pathref, store)
            else:
                out = getpath(pathref, store, current, state)
        else:
            out = getpath(pathref, store, current, state)
        
        # If path resolution returns None (missing), treat as UNDEF to delete key
        if out is None:
            out = UNDEF 

    else:
        
        # Check for injections within the string.
        def partial(mobj):
            ref = mobj.group(1)

            # Special escapes inside injection.
            if 3 < len(ref):
                ref = ref.replace(r'$BT', S_BT).replace(r'$DS', S_DS)
                
            if UNDEF != state:
                state.full = False

            found = getpath(ref, store, current, state)
            
            # Ensure inject value is a string.
            if UNDEF == found or found is None:
                return S_MT
                
            if isinstance(found, str):
                return found

            return json.dumps(found, separators=(',', ':'))

        out = part_re.sub(partial, val)

        # Also call the state handler on the entire string, providing the
        # option for custom injection.
        if UNDEF != state and isfunc(state.handler):
            state.full = True
            out = state.handler(state, out, current, val, store)

    return out


def _invalidTypeMsg(path: List[str], needtype: str, vt: str, v: Any, _whence: Optional[str] = None) -> str:
    """
    Create an error message for type mismatch.
    """
    vs = 'no value' if UNDEF == v else stringify(v)
    return (
        'Expected ' +
        (f"field {pathify(path,1)} to be " if 1 < len(path) else '') +
        f"{needtype}, but found " +
        (f"{vt}: " if UNDEF != v else '') + vs +

        # Uncomment to help debug validation errors.
        # ' [' + str(_whence) + ']' +

        '.'
    )


def delprop(parent: Any, key: Any) -> Any:
    """
    Delete a property from a dictionary or list.
    For lists, this will shift elements down to fill the gap.
    """
    if not iskey(key):
        return parent

    if ismap(parent):
        key = str(key)
        parent.pop(key, UNDEF)
    elif islist(parent):
        try:
            key_i = int(key)
            if 0 <= key_i < len(parent):
                # Shift items left
                for pI in range(key_i, len(parent) - 1):
                    parent[pI] = parent[pI + 1]
                parent.pop()
        except ValueError:
            pass

    return parent


# Create a StructUtility class with all utility functions as attributes
class StructUtility:
    def __init__(self):
        self.clone = clone
        self.delprop = delprop
        self.escre = escre
        self.escurl = escurl
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
        self.joinurl = joinurl
        self.keysof = keysof
        self.merge = merge
        self.pad = pad
        self.pathify = pathify
        self.setprop = setprop
        self.size = size
        self.slice = slice
        self.strkey = strkey
        self.stringify = stringify
        self.transform = transform
        self.typify = typify
        self.validate = validate
        self.walk = walk
    

__all__ = [
    'Injection',
    'Injector',
    'Modify',
    'WalkApply',
    'StructUtility',
    'clone',
    'delprop',
    'escre',
    'escurl',
    'getelem',
    'getpath',
    'getprop',
    'haskey',
    'inject',
    'isempty',
    'isfunc',
    'iskey',
    'islist',
    'ismap',
    'isnode',
    'items',
    'joinurl',
    'keysof',
    'merge',
    'pad',
    'pathify',
    'setprop',
    'size',
    'slice',
    'strkey',
    'stringify',
    'transform',
    'typify',
    'validate',
    'walk',
]


def _validation(
        pval: Any,
        key: Optional[str],
        parent: Optional[Any],
        state: Optional[Injection],
        current: Optional[Any],
        _store: Optional[Any]
) -> None:
    """
    This is the "modify" argument to inject. Use this to perform
    generic validation. Runs *after* any special commands.
    """
    if UNDEF == state:
        return

    if S_SKIP == pval:
        return

    # Skip validation if the spec value is a special command - these are handled by _validatehandler
    if isinstance(pval, str) and S_DS in str(pval):
        return

    # Current val to verify.
    # Get the actual value from the data parent
    data_root = getprop(state.dparent, S_DTOP, state.dparent)
    
    # Handle root level validation correctly
    if key == S_DTOP:
        cval = data_root
    else:
        cval = getprop(data_root, key)
    
    # Handle null/undefined data values
    if cval is None or cval is UNDEF:
        # If spec has a default value, use it
        if pval is not None and pval is not UNDEF:
            setprop(parent, key, pval)
        return

    ptype = typify(pval)
    ctype = typify(cval)

    # Type mismatch.
    if ptype != ctype and UNDEF != pval:
        state.errs.append(_invalidTypeMsg(state.path, ptype, ctype, cval, 'V0010'))
        return

    if ismap(cval):
        if not ismap(pval):
            state.errs.append(_invalidTypeMsg(state.path, ptype, ctype, cval, 'V0020'))
            return

        ckeys = keysof(cval)
        pkeys = keysof(pval)

        # Empty spec object {} means object can be open (any keys).
        if 0 < len(pkeys) and True != getprop(pval, '`$OPEN`'):
            badkeys = []
            for ckey in ckeys:
                if not haskey(pval, ckey):
                    badkeys.append(ckey)
            if 0 < len(badkeys):
                msg = f"Unexpected keys at field {pathify(state.path,1)}: {', '.join(badkeys)}"
                state.errs.append(msg)
        else:
            # Object is open, so merge in extra keys.
            merge([pval, cval])
            if isnode(pval):
                delprop(pval, '`$OPEN`')
    elif islist(cval):
        if not islist(pval):
            state.errs.append(_invalidTypeMsg(state.path, ptype, ctype, cval, 'V0030'))
        else:
            # Check if the spec array contains a validator command
            if len(pval) > 0 and isinstance(pval[0], str) and pval[0].startswith('`$') and pval[0].endswith('`'):
                # This is an array-based validator command - call the validator directly
                validator_name = pval[0][2:-1]  # Remove `$ and `
                validator_func = _store.get(f'${validator_name}')
                
                if validator_func and callable(validator_func):
                    # Create a temporary state for the validator
                    temp_state = Injection(
                        mode=S_MVAL,
                        full=False,
                        keyI=0,
                        keys=['0'] + [str(i) for i in range(1, len(pval))],
                        key='0',
                        val=pval[0],
                        parent=pval,
                        path=state.path,
                        nodes=state.nodes,
                        handler=state.handler,
                        base=state.base,
                        errs=state.errs,
                        meta=state.meta,
                        modify=state.modify,
                        dparent=state.dparent
                    )
                    
                    # Call the validator
                    result = validator_func(temp_state, pval[0], {S_DTOP: cval}, f'${validator_name}', _store)
                    
                    # Set the validated result
                    if result is not None and result is not UNDEF:
                        setprop(parent, key, result)
                    else:
                        setprop(parent, key, cval)
                else:
                    # Unknown validator, treat as regular array
                    setprop(parent, key, cval)
    else:
        # Spec value was a default, copy over data
        setprop(parent, key, cval)

    return

