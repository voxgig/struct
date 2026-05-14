# JavaScript (js) - Review vs TypeScript Canonical

## Overview

The JavaScript version is significantly behind the TypeScript canonical version. It exports **27 functions** compared to TypeScript's **40+**, and uses an older API design pattern (separate positional parameters instead of the unified `injdef` object pattern).

---

## Missing Functions

The following functions present in the TypeScript canonical are **completely absent** from the JS version:

| Function | Category | Impact |
|----------|----------|--------|
| `delprop` | Property access | No way to delete properties cleanly |
| `getelem` | Property access | No negative-index list element access |
| `getdef` | Property access | No defined-or-default helper |
| `setpath` | Path operations | Cannot set values at nested paths |
| `select` | Query operations | No MongoDB-style query/filter on children |
| `size` | Collection | No unified size/length function |
| `slice` | Collection | No array/string slicing with negative indices |
| `flatten` | Collection | No nested array flattening |
| `filter` | Collection | No predicate-based filtering |
| `pad` | String | No string padding utility |
| `replace` | String | No unified string replace |
| `join` | String | No general join (only `joinurl`) |
| `jsonify` | Serialization | No JSON serialization with formatting |
| `typename` | Type system | No type-name-from-bitfield function |
| `jm` | JSON builders | No map builder |
| `jt` | JSON builders | No array/tuple builder |
| `checkPlacement` | Advanced | No placement validation for injectors |
| `injectorArgs` | Advanced | No injector argument validation |
| `injectChild` | Advanced | No child injection helper |

---

## API Signature Differences

### 1. `typify` returns strings instead of bitfield integers

- **TS**: Returns a numeric bitfield (e.g., `T_string`, `T_integer | T_number`). Enables bitwise type composition and checking.
- **JS**: Returns a simple string (`'null'`, `'string'`, `'number'`, `'boolean'`, `'function'`, `'array'`, `'object'`).
- **Impact**: The entire bitfield-based type system (`T_any`, `T_noval`, `T_boolean`, `T_decimal`, `T_integer`, `T_number`, `T_string`, `T_function`, `T_symbol`, `T_null`, `T_list`, `T_map`, `T_instance`, `T_scalar`, `T_node`) is missing. This prevents fine-grained type discrimination (e.g., distinguishing `integer` from `decimal`).

### 2. `walk` has a different signature

- **TS**: `walk(val, before?, after?, maxdepth?, key?, parent?, path?)` - supports separate `before` and `after` callbacks, and a `maxdepth` limit.
- **JS**: `walk(val, apply, key?, parent?, path?)` - single `apply` callback (post-order only), no `maxdepth`.
- **Impact**: Cannot apply transformations before descending into children; no depth protection against deeply nested structures.

### 3. `inject` uses positional parameters instead of `injdef`

- **TS**: `inject(val, store, injdef?)` where `injdef` is a `Partial<Injection>` with `modify`, `handler`, `extra`, `meta`, `errs` fields.
- **JS**: `inject(val, store, modify?, current?, state?)` - separate positional parameters.
- **Impact**: Less extensible; adding new options requires changing the function signature.

### 4. `transform` uses positional parameters instead of `injdef`

- **TS**: `transform(data, spec, injdef?)` - unified injection definition.
- **JS**: `transform(data, spec, extra?, modify?)` - separate params.
- **Impact**: Same extensibility concern as `inject`.

### 5. `validate` uses positional parameters instead of `injdef`

- **TS**: `validate(data, spec, injdef?)` - unified injection definition.
- **JS**: `validate(data, spec, extra?, collecterrs?)` - separate params.

### 6. `getpath` parameter order differs

- **TS**: `getpath(store, path, injdef?)` - store first.
- **JS**: `getpath(path, store, current?, state?)` - path first.
- **Impact**: Inconsistent with the rest of the TS API.

### 7. `joinurl` is a standalone function

- **TS**: Uses `join(arr, sep?, url?)` with a `url` parameter for URL mode.
- **JS**: Has a separate `joinurl(sarr)` function; no general `join`.
- **Impact**: Less unified API.

### 8. `setprop` deletion behavior differs

- **TS**: Has separate `delprop` function; `setprop` with `DELETE` marker deletes.
- **JS**: `setprop` with `undefined` value deletes the property.
- **Impact**: Conflates "set to undefined" with "delete".

---

## Validation Differences

- **TS**: Uses `$MAP`, `$LIST`, `$INTEGER`, `$DECIMAL`, `$NIL`, `$INSTANCE` validators.
- **JS**: Uses `$OBJECT`, `$ARRAY` (no `$MAP`/`$LIST` aliases). Missing `$INTEGER`, `$DECIMAL`, `$NIL`, `$INSTANCE` validators.
- **Impact**: Less granular validation; cannot distinguish integer from decimal numbers.

---

## Transform Differences

- **TS**: Supports `$ANNO`, `$FORMAT`, `$APPLY`, `$REF`, `$BT`, `$DS`, `$WHEN` transform commands.
- **JS**: Missing `$ANNO`, `$FORMAT`, `$APPLY`, `$REF` (some may be partially present). Has `$BT`, `$DS`, `$WHEN`.
- **Impact**: Fewer transformation capabilities.

---

## Structural/Architectural Differences

### No Injection Class
- **TS**: Has a full `Injection` class with methods (`descend()`, `child()`, `setval()`, `toString()`).
- **JS**: Uses plain objects for state management.
- **Impact**: Less structured state management; harder to debug injection processing.

### No Type Constants
- **TS**: Exports `T_any`, `T_noval`, `T_boolean`, `T_decimal`, `T_integer`, etc. as bitfield constants.
- **JS**: No type constants at all.

### No SKIP/DELETE Sentinels
- **TS**: Exports `SKIP` and `DELETE` sentinel objects.
- **JS**: Not exported (may be used internally).

### No `merge` maxdepth parameter
- **TS**: `merge(val, maxdepth?)` supports depth limiting.
- **JS**: `merge(val)` has no depth limit.

---

## Significant Language Difference Issues

1. **No issues** - JavaScript and TypeScript share the same runtime semantics, so there are no fundamental language barriers. All differences are implementation gaps.

---

## Test Coverage Gaps

Tests missing for: `setpath`, `select`, `size`, `slice`, `flatten`, `filter`, `pad`, `jsonify`, `delprop`, `getelem`, `typename`, `jm`, `jt`, `walk-depth`, `walk-copy`, `merge-depth`, `getpath-special`, `getpath-handler`, `transform-ref`, `transform-format`, `transform-apply`, `validate-special`, `validate-edge`, `select-*`.

---

## Alignment Plan

### Phase 1: Core Missing Functions (High Priority)
1. Add `delprop(parent, key)` function
2. Add `getelem(val, key, alt)` with negative index support
3. Add `getdef(val, alt)` helper
4. Add `setpath(store, path, val, injdef)` function
5. Add `size(val)` function
6. Add `select(children, query)` with operator support

### Phase 2: Type System Alignment
7. Convert `typify` to return bitfield integers matching TS constants
8. Add all type constants (`T_any`, `T_noval`, `T_boolean`, etc.)
9. Add `typename(t)` function
10. Export `SKIP` and `DELETE` sentinels

### Phase 3: Collection Functions
11. Add `slice(val, start, end, mutate)` function
12. Add `flatten(list, depth)` function
13. Add `filter(val, check)` function
14. Add `pad(str, padding, padchar)` function
15. Add `replace(s, from, to)` function
16. Add `join(arr, sep, url)` (general join, deprecate standalone `joinurl`)
17. Add `jsonify(val, flags)` function
18. Add `jm(...kv)` and `jt(...v)` JSON builders

### Phase 4: API Signature Alignment
19. Refactor `walk` to support `before`/`after` callbacks and `maxdepth`
20. Refactor `inject` to use `injdef` object parameter
21. Refactor `transform` to use `injdef` object parameter
22. Refactor `validate` to use `injdef` object parameter
23. Align `getpath` parameter order to `(store, path, injdef)`
24. Add `merge` `maxdepth` parameter

### Phase 5: Injection System
25. Create `Injection` class with `descend()`, `child()`, `setval()` methods
26. Add `checkPlacement`, `injectorArgs`, `injectChild` functions

### Phase 6: Validation/Transform Parity
27. Add `$MAP`, `$LIST`, `$INTEGER`, `$DECIMAL`, `$NIL`, `$INSTANCE` validators
28. Add `$ANNO`, `$FORMAT`, `$APPLY`, `$REF` transform commands

### Phase 7: Test Alignment
29. Add tests for all new functions using shared `test.json` spec
30. Ensure all test categories from TS are passing
