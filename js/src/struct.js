/* Copyright (c) 2025 Voxgig Ltd. */

/* Voxgig Struct
 * =============
 *
 * Utility functions to manipulate in-memory JSON-like data
 * structures.  The general design principle is
 * "by-example". Transform specifications mirror the desired output.
 * This implementation is desgined for porting to multiple language.
 *
 * - isnode, islist, islist, iskey: identify value kinds
 * - clone: create a copy of a JSON-like data structure
 * - items: list entries of a map or list as [key, value] pairs
 * - getprop: safely get a property value by key
 * - setprop: safely set a property value by key
 * - getpath: get the value at a key path deep inside an object
 * - merge: merge multiple nodes, overriding values in earlier nodes.
 * - walk: walk a node tree, applying a function at each node and leaf.
 * - inject: inject values from a data store into a new data structure.
 * - transform: transform a data structure to an example structure.
 */


// String constants.
const S = {
  MKEYPRE: 'key:pre',
  MKEYPOST: 'key:post',
  MVAL: 'val',
  MKEY: 'key',

  TKEY: '`$KEY`',
  TMETA: '`$META`',

  KEY: 'KEY',

  DTOP: '$TOP',

  object: 'object',
  number: 'number',
  string: 'string',
  function: 'function',
  empty: '',
  base: 'base',

  BT: '`',
  DS: '$',
  DT: '.',
}


// Value is a node - defined, and a map (hash) or list (array).
function isnode(val) {
  return null != val && S.object == typeof val
}


// Value is a defined map (hash) with string keys.
function ismap(val) {
  return null != val && S.object == typeof val && !Array.isArray(val)
}


// Value is a defined list (array) with integer keys (indexes).
function islist(val) {
  return Array.isArray(val)
}


// Value is a defined string (non-empty) or integer key.
function iskey(key) {
  const keytype = typeof key
  return (S.string === keytype && S.empty !== key) || S.number === keytype
}


// Check for an "empty" value - undefined, false, 0, empty string, array, object.
function isempty(val) {
  return null == val || S.empty === val || false === val || 0 === val ||
    (Array.isArray(val) && 0 === val.length) ||
    ('object' === typeof val && 0 === Object.keys(val).length)
}


// Safely stringify a value for printing (NOT JSON!).
function stringify(val, maxlen) {
  let json = S.empty

  try {
    json = JSON.stringify(val)
  }
  catch (err) {
    json = S.empty + val
  }

  json = 'string' !== typeof json ? S.empty + json : json
  json = json.replace(/"/g, '')

  if (null != maxlen) {
    let js = json.substring(0, maxlen)
    json = maxlen < json.length ? (js.substring(0, maxlen - 3) + '...') : json
  }

  return json
}


// Escape regular expression.
function escre(s) {
  s = null == s ? S.empty : s
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
}


// Escape URL.
function escurl(s) {
  s = null == s ? S.empty : s
  return encodeURIComponent(s)
}


// List the keys of a map or list as an array of tuples of the form [key, value].
function items(val) {
  return ismap(val) ? Object.entries(val) :
    islist(val) ? val.map((n, i) => [i, n]) :
      []
}


// Clone a JSON-like data structure.
function clone(val) {
  return undefined === val ? undefined : JSON.parse(JSON.stringify(val))
}


// Safely get a property of a node. Undefined arguments return undefined.
// If the key is not found, return the alternative value.
function getprop(val, key, alt) {
  let out = undefined === val ? alt : undefined === key ? alt : val[key]
  out = undefined === out ? alt : out
  return out
}


// Safely set a property. Undefined arguments and invalid keys are ignored.
// Returns the (possible modified) parent.
// If the value is undefined it the key will be deleted from the parent.
// If the parent is a list, and the key is negative, prepend the value.
// If the key is above the list size, append the value.
// If the value is undefined, remove the list element at index key, and shift the
// remaining elements down.  These rules avoids "holes" in the list.
function setprop(parent, key, val) {
  if (!iskey(key)) {
    return parent
  }

  if (ismap(parent)) {
    key = S.empty + key
    if (undefined === val) {
      delete parent[key]
    }
    else {
      parent[key] = val
    }
  }
  else if (islist(parent)) {
    // Ensure key is an integer.
    let keyI = +key

    if (isNaN(keyI)) {
      return parent
    }

    keyI = Math.floor(keyI)

    // Delete list element at position keyI, shifting later elements down.
    if (undefined === val) {
      if (0 <= keyI && keyI < parent.length) {
        for (let pI = keyI; pI < parent.length - 1; pI++) {
          parent[pI] = parent[pI + 1]
        }
        parent.length = parent.length - 1
      }
    }

    // Set or append value at position keyI, or append if keyI out of bounds.
    else if (0 <= keyI) {
      parent[parent.length < keyI ? parent.length : keyI] = val
    }

    // Prepend value if keyI is negative
    else {
      parent.unshift(val)
    }
  }

  return parent
}


// Walk a data structure depth first.
function walk(
  // These arguments are the public interface.
  val,
  apply,

  // These areguments are used for recursive state.
  key,
  parent,
  path
) {
  if (isnode(val)) {
    for (let [ckey, child] of items(val)) {
      setprop(val, ckey, walk(child, apply, ckey, val, [...(path || []), S.empty + ckey]))
    }
  }

  // Nodes are applied *after* their children.
  // For the root node, key and parent will be undefined.
  return apply(key, val, parent, path || [])
}


// Merge a list of values into each other. Later values have precedence.
// Nodes override scalars. Node kinds (list or map) override each other.
// The first element is modified.
function merge(objs) {
  let out = undefined

  if (!islist(objs)) {
    out = objs
  }
  else if (0 === objs.length) {
    out = undefined
  }
  else if (1 === objs.length) {
    out = objs[0]
  }
  else {

    out = getprop(objs, 0, {})

    // Merge remaining down onto first.
    for (let oI = 1; oI < objs.length; oI++) {
      let obj = objs[oI]

      if (!isnode(obj)) {
        // Nodes win.
        out = obj
      }
      else {
        // Nodes win, also over nodes of a different kind.
        if (!isnode(out) || (ismap(obj) && islist(out)) || (islist(obj) && ismap(out))) {
          out = obj
        }
        else {
          let cur = [out] // Node stack
          let cI = 0

          // Walk overriding node, creating paths in output as needed.
          walk(obj, (key, val, parent, path) => {
            if (null == key) {
              return val
            }

            let lenpath = path.length

            cI = lenpath - 1
            if (undefined === cur[cI]) {
              cur[cI] = getpath(path.slice(0, lenpath - 1), out)
            }

            // Create node if needed.
            if (!isnode(cur[cI])) {
              cur[cI] = islist(parent) ? [] : {}
            }

            // Node child is just ahead of us on the stack.
            if (isnode(val)) {
              setprop(cur[cI], key, cur[cI + 1])
              cur[cI + 1] = undefined
            }

            // Scalar child.
            else {
              setprop(cur[cI], key, val)
            }

            return val
          })
        }
      }
    }
  }

  return out
}


// Get a value deep inside a node using a key path.
// For example the path `a.b` gets the value 1 from {a:{b:1}}.
// The path can specified as a dotted string, or a string array.
// If the path starts with a dot (or the first element is ''), the path is considered local,
// and resolved against the `current` argument, if defined.
// Integer path parts are used as array indexes.
// The state argument allows for custom handling when called from `inject` or `transform`.
function getpath(path, store, current, state) {

  const parts = islist(path) ? path : S.string === typeof path ? path.split(S.DT) : undefined

  if (undefined === parts) {
    return undefined
  }

  let root = store
  let val = store

  // An empty path (incl empty string) just finds the store.
  if (null == path || null == store || (1 === parts.length && S.empty === parts[0])) {
    // The actual store data may be in a store sub property, defined by state.base.
    val = getprop(store, getprop(state, S.base), store)
  }
  else if (0 < parts.length) {
    let pI = 0

    // Relative path uses `current` argument.
    if (S.empty === parts[0]) {
      pI = 1
      root = current
    }

    let part = pI < parts.length ? parts[pI] : undefined
    let first = getprop(root, part)

    // At top level, check state.base, if provided
    val = (undefined === first && 0 === pI) ?
      getprop(getprop(root, getprop(state, S.base)), part) :
      first

    // Move along the path, trying to descend into the store.
    for (pI++; undefined !== val && pI < parts.length; pI++) {
      val = getprop(val, parts[pI])
    }

  }

  // State may provide a custom handler to modify found value.
  if (null != state && S.function === typeof state.handler) {
    val = state.handler(state, val, current, store)
  }

  return val
}


// Inject store values into a string. Not a public utility - used by `inject`.
// Inject are marked with `path` where path is resolved with getpath against the
// store or current (if defined) arguments. See `getpath`.
// Custom injection handling can be provided by state.handler (this is used for
// transform functions).
// The path can also have the special syntax $NAME999 where NAME is upper case letters only,
// and 999 is any digits, which are discarded. This syntax specifies the name of a transform,
// and optionally allows transforms to be ordered by alphanumeric sorting.
function injectstr(val, store, current, state) {
  if (S.string !== typeof val) {
    return S.empty
  }

  let out = val
  const m = val.match(/^`(\$[A-Z]+|[^`]+)[0-9]*`$/)

  // Full string is an injection.
  if (m) {
    if (state) {
      state.full = true
    }
    let ref = m[1]

    // Special escapes inside injection.
    ref = 3 < ref.length ? ref.replace(/\$BT/g, S.BT).replace(/\$DS/g, S.DS) : ref

    out = getpath(ref, store, current, state)
  }

  // Check for injections within the string.
  else {
    out = val.replace(/`([^`]+)`/g,
      (_m, ref) => {
        ref = 3 < ref.length ? ref.replace(/\$BT/g, S.BT).replace(/\$DS/g, S.DS) : ref
        if (state) {
          state.full = false
        }
        const found = getpath(ref, store, current, state)

        return undefined === found ? S.empty :
          S.object === typeof found ? JSON.stringify(found) :
            found
      })

    // Also call the handler on the entire string.
    if (state.handler) {
      state.full = true
      out = state.handler(state, out, current, store)
    }
  }

  return out
}


// Inject values from a data store into a node recursively, resolving paths against the store,
// or current if they are local. THe modify argument allows custom modification of the result.
// The state (InjectState) argument is used to maintain recursive state.
function inject(
  val,
  store,
  modify,
  current,
  state,
) {
  const valtype = typeof val

  // Create state if at root of injection.
  // The input value is placed inside a virtual parent holder
  // to simplify edge cases.
  if (undefined === state) {
    const parent = { [S.DTOP]: val }
    state = {
      mode: S.MVAL,
      full: false,
      keyI: 0,
      keys: [S.DTOP],
      key: S.DTOP,
      val,
      parent,
      path: [S.DTOP],
      nodes: [parent],
      handler: injecthandler,
      base: S.DTOP,
      modify,
    }
  }

  // Resolve current node in store for local paths.
  if (undefined === current) {
    current = { $TOP: store }
  }
  else {
    const parentkey = state.path[state.path.length - 2]
    current = null == parentkey ? current : getprop(current, parentkey)
  }

  // Desend into node.
  if (isnode(val)) {

    // Keys are sorted alphanumerically to ensure determinism.
    // Injection transforms ($FOO) are processed *after* other keys.
    // NOTE: the optional digits suffix of the transform can thsu be used to
    // order the transforms.
    const origkeys = ismap(val) ? [
      ...Object.keys(val).filter(k => !k.includes(S.DS)),
      ...Object.keys(val).filter(k => k.includes(S.DS)).sort(),
    ] : val.map((_n, i) => i)


    // Each child key-value pair is processed in three injection phases:
    // 1. state.mode='key:pre' - Key string is injected, returning a possibly altered key.
    // 2. state.mode='val' - The child value is injected.
    // 3. state.mode='key:post' - Key string is injected again, allowing child mutation.
    for (let okI = 0; okI < origkeys.length; okI++) {
      const origkey = S.empty + origkeys[okI]

      let childpath = [...(state.path || []), origkey]
      let childnodes = [...(state.nodes || []), val]

      const childstate = {
        mode: S.MKEYPRE,
        full: false,
        keyI: okI,
        keys: origkeys,
        key: origkey,
        val,
        parent: val,
        path: childpath,
        nodes: childnodes,
        handler: injecthandler,
        base: state.base,
      }

      const prekey = injectstr(origkey, store, current, childstate)

      // Prevent further processing by returning an undefined prekey
      if (null != prekey) {
        let child = val[prekey]
        childstate.mode = S.MVAL
        inject(
          child,
          store,
          modify,
          current,
          childstate,
        )

        childstate.mode = S.MKEYPOST
        injectstr(origkey, store, current, childstate)
      }
    }
  }

  // Inject paths into string scalars.
  else if (S.string === valtype) {
    state.mode = S.MVAL
    const newval = injectstr(val, store, current, state)
    val = newval

    setprop(state.parent, state.key, newval)
  }

  // Custom modification.
  if (modify) {
    modify(
      state.key,
      val,
      state.parent,
      state,
      current,
      store
    )
  }

  // Original val reference may no longer be correct.
  return getprop(state.parent, S.DTOP)
}


// Default inject handler for transforms. If the path resolves to a function,
// call the function passing the injection state. This is how transforms operate.
const injecthandler = (state, val, current, store) => {
  let out = val

  if (S.function === typeof val) {
    out = val(state, val, current, store)
  }
  else if (S.MVAL === state.mode && state.full) {
    setprop(state.parent, state.key, val)
  }

  return out
}


// The transform_* functions are define inject handlers (see InjectHandler).


// Delete a key from a map or list.
const transform_DELETE = (state) => {
  const { key, parent } = state
  setprop(parent, key, undefined)
  return undefined
}


// Copy value from source data.
const transform_COPY = (state, _val, current) => {
  const { mode, key, parent } = state

  let out
  if (mode.startsWith(S.MKEY)) {
    out = key
  }
  else {
    out = getprop(current, key)
    setprop(parent, key, out)
  }

  return out
}


// As a value, inject the key of the parent node.
// As a key, defined the name of the key property in the source object.
const transform_KEY = (state, _val, current) => {
  const { mode, path, parent } = state

  if (S.MVAL !== mode) {
    return undefined
  }

  const keyspec = getprop(parent, S.TKEY)
  if (undefined !== keyspec) {
    setprop(parent, S.TKEY, undefined)
    return getprop(current, keyspec)
  }

  return getprop(getprop(parent, S.TMETA), S.KEY, getprop(path, path.length - 2))
}


// Store meta data about a node.
const transform_META = (state) => {
  const { parent } = state
  setprop(parent, S.TMETA, undefined)
  return undefined
}


// Merge a list of objects into the current object. 
// Must be a key in an object. The value is merged over the current object.
// If the value is an array, the elements are first merged using `merge`. 
// If the value is the empty string, merge the top level store.
// Format: { '`$MERGE`': '`source-path`' | ['`source-paths`', ...] }
const transform_MERGE = (
  state, _val, store
) => {
  const { mode, key, parent } = state

  if (S.MKEYPRE === mode) { return key }

  // Operate after child values have been transformed.
  if (S.MKEYPOST === mode) {

    let args = getprop(parent, key)
    args = S.empty === args ? [store.$TOP] : Array.isArray(args) ? args : [args]

    setprop(parent, key, undefined)

    // Literals in the parent have precedence.
    const mergelist = [parent, ...args, clone(parent)]

    merge(mergelist)

    return key
  }

  return undefined
}


// Convert a node to a list.
// Format: ['`$EACH`', '`source-path-of-node`', child-template]
const transform_EACH = (
  state,
  _val,
  current,
  store
) => {
  const { mode, keys, path, parent, nodes } = state

  // Remove arguments to avoid spurious processing.
  if (keys) {
    keys.length = 1
  }

  // Defensive context checks.
  if (S.MVAL !== mode || null == path || null == nodes) {
    return undefined
  }

  // Get arguments.
  const srcpath = parent[1] // Path to source data.
  const child = clone(parent[2]) // Child template.

  // Source data
  const src = getpath(srcpath, store, current, state)

  // Create parallel data structures:
  // source entries :: child templates
  let tcurrent = []
  let tval = []

  const tkey = path[path.length - 2]
  const target = nodes[path.length - 2] || nodes[path.length - 1]

  if (isnode(src)) {
    if (islist(src)) {
      tval = src.map(() => clone(child))
    }
    else {
      tval = Object.entries(src).map(n => ({
        ...clone(child),

        // Make a note of the key for $KEY transforms
        [S.TMETA]: { KEY: n[0] }
      }))
    }

    tcurrent = Object.values(src)
  }

  // Parent structure.
  tcurrent = { $TOP: tcurrent }

  // Build the substructure.
  tval = inject(
    tval,
    store,
    state.modify,
    tcurrent,
  )

  setprop(target, tkey, tval)

  // Prevent callee from damaging first list entry (since we are in `val` mode).
  return tval[0]
}



// Convert a node to a map.
// Format: { '`$PACK`':['`source-path`', child-template]}
const transform_PACK = (
  state,
  _val,
  current,
  store
) => {
  const { mode, key, path, parent, nodes } = state

  // Defensive context checks.
  if (S.MKEYPRE !== mode || S.string !== typeof key || null == path || null == nodes) {
    return undefined
  }

  // Get arguments.
  const args = parent[key]
  const srcpath = args[0] // Path to source data.
  const child = clone(args[1]) // Child template.

  // Find key and target node.
  const keyprop = child[S.TKEY]
  const tkey = path[path.length - 2]
  const target = nodes[path.length - 2] || nodes[path.length - 1]

  // Source data
  let src = getpath(srcpath, store, current, state)

  // Prepare source as a list.
  src = islist(src) ? src :
    ismap(src) ? Object.entries(src)
      .reduce((a, n) =>
        (n[1][S.TMETA] = { KEY: n[0] }, a.push(n[1]), a), []) :
      undefined

  if (null == src) {
    return undefined
  }

  // Get key if specified.
  let childkey = getprop(child, S.TKEY)
  let keyname = undefined === childkey ? keyprop : childkey
  setprop(child, S.TKEY, undefined)

  // Build parallel target object.
  let tval = {}
  tval = src.reduce((a, n) => {
    let kn = getprop(n, keyname)
    setprop(a, kn, clone(child))
    const nchild = getprop(a, kn)
    setprop(nchild, S.TMETA, getprop(n, S.TMETA))
    return a
  }, tval)

  // Build parallel source object.
  let tcurrent = {}
  src.reduce((a, n) => {
    let kn = getprop(n, keyname)
    setprop(a, kn, n)
    return a
  }, tcurrent)

  tcurrent = { $TOP: tcurrent }

  // Build substructure.
  tval = inject(
    tval,
    store,
    state.modify,
    tcurrent,
  )

  setprop(target, tkey, tval)

  // Drop transform key.
  return undefined
}


// Transform data using spec.
// Only operates on static JSON-like data.
// Arrays are treated as if they are objects with indices as keys.
function transform(
  data, // Source data to transform into new data (original not mutated)
  spec, // Transform specification; output follows this shape
  extra, // Additional store of data and transforms.
  modify // Optionally modify individual values.
) {
  const extraTransforms = {}
  const extraData = null == extra ? {} : items(extra)
    .reduce((a, n) =>
      (n[0].startsWith(S.DS) ? extraTransforms[n[0]] = n[1] : (a[n[0]] = n[1]), a), {})

  const dataClone = merge([
    clone(undefined === extraData ? {} : extraData),
    clone(undefined === data ? {} : data),
  ])

  // Define a top level store that provides transform operations.
  const store = {

    // Custom extra transforms, if any.
    ...extraTransforms,

    // The inject function recognises this special location for the root of the source data.
    // NOTE: to escape data that contains "`$FOO`" keys at the top level,
    // place that data inside a holding map: { myholder: mydata }.
    $TOP: dataClone,

    // Escape backtick (this also works inside backticks).
    $BT: () => S.BT,

    // Escape dollar sign (this also works inside backticks).
    $DS: () => S.DS,

    // Insert current date and time as an ISO string.
    $WHEN: () => new Date().toISOString(),

    $DELETE: transform_DELETE,
    $COPY: transform_COPY,
    $KEY: transform_KEY,
    $META: transform_META,
    $MERGE: transform_MERGE,
    $EACH: transform_EACH,
    $PACK: transform_PACK,
  }

  const out = inject(spec, store, modify, store)

  return out
}


module.exports = {
  clone,
  escre,
  escurl,
  getpath,
  getprop,
  inject,
  isempty,
  iskey,
  islist,
  ismap,
  isnode,
  items,
  merge,
  setprop,
  stringify,
  transform,
  walk,
}
