# Ruby (rb) - Review vs TypeScript Canonical

## Overview

The Ruby version is **partially complete**. It implements the basic utility functions and the core operations (inject, transform, validate), but many tests are **skipped**, suggesting the implementations may be incomplete or broken. Several functions present in TS are missing entirely. The API uses an older positional-parameter pattern rather than the unified `injdef` object.

---

## Missing Functions

| Function | Category | Impact |
|----------|----------|--------|
| `getelem` | Property access | No negative-index element access |
| `getdef` | Property access | No defined-or-default helper |
| `delprop` | Property access | No dedicated property deletion |
| `setpath` | Path operations | Cannot set values at nested paths |
| `select` | Query operations | No MongoDB-style query/filter |
| `size` | Collection | No unified size function |
| `slice` | Collection | No array/string slicing |
| `flatten` | Collection | No array flattening |
| `filter` | Collection | No predicate filtering |
| `pad` | String | No string padding |
| `replace` | String | No unified string replace |
| `join` | String | No general join (only `joinurl`) |
| `jsonify` | Serialization | No JSON serialization with formatting |
| `typename` | Type system | No type name function |
| `jm`/`jt` | JSON builders | No JSON builder functions |
| `checkPlacement` | Advanced | No placement validation |
| `injectorArgs` | Advanced | No injector argument validation |
| `injectChild` | Advanced | No child injection helper |

---

## `typify` Returns Strings Instead of Bitfield

- **TS**: Returns numeric bitfield with constants (`T_string`, `T_integer | T_number`, etc.).
- **Ruby**: Returns simple strings (`"null"`, `"string"`, `"number"`, `"boolean"`, `"function"`, `"array"`, `"object"`).
- **Impact**: The entire bitfield type system is missing. Cannot distinguish integer from decimal, no composite type checks, no `T_scalar`/`T_node` groupings.

---

## No Type Constants

The Ruby version has **no bitfield type constants** (`T_any`, `T_noval`, `T_boolean`, `T_decimal`, `T_integer`, `T_number`, `T_string`, `T_function`, `T_symbol`, `T_null`, `T_list`, `T_map`, `T_instance`, `T_scalar`, `T_node`).

---

## API Signature Differences

### 1. `inject` uses positional parameters

- **TS**: `inject(val, store, injdef?)`.
- **Ruby**: `inject(val, store, modify=nil, current=nil, state=nil, flag=nil)`.
- **Impact**: Less extensible; harder to add new options.

### 2. `transform` uses positional parameters

- **TS**: `transform(data, spec, injdef?)`.
- **Ruby**: `transform(data, spec, extra=nil, modify=nil)`.

### 3. `validate` uses positional parameters

- **TS**: `validate(data, spec, injdef?)`.
- **Ruby**: `validate(data, spec, extra=nil, collecterrs=nil)`.

### 4. `getpath` parameter order differs

- **TS**: `getpath(store, path, injdef?)`.
- **Ruby**: `getpath(path, store, current=nil, state=nil)`.
- **Impact**: Different parameter order.

### 5. `walk` has no `before`/`after` or `maxdepth`

- **TS**: `walk(val, before?, after?, maxdepth?, key?, parent?, path?)`.
- **Ruby**: `walk(val, apply, key=nil, parent=nil, path=[])` - single callback, no depth limit.
- **Impact**: Post-order only, no depth protection.

### 6. `setprop` overloads deletion

- **TS**: Has separate `delprop`.
- **Ruby**: `setprop(parent, key, val=:no_val_provided)` - omitting val deletes.
- **Impact**: Different deletion semantics.

### 7. `haskey` accepts variable arguments

- **Ruby**: `haskey(*args)` accepts either `[val, key]` array or `(val, key)` separate args.
- **TS**: `haskey(val, key)` - always two parameters.
- **Impact**: Non-standard overloading.

---

## Validation Differences

- **TS**: Uses `$MAP`, `$LIST`, `$STRING`, `$NUMBER`, `$INTEGER`, `$DECIMAL`, `$BOOLEAN`, `$NULL`, `$NIL`, `$FUNCTION`, `$INSTANCE`, `$ANY`, `$CHILD`, `$ONE`, `$EXACT`.
- **Ruby**: Uses `$OBJECT`, `$ARRAY`, `$STRING`, `$NUMBER`, `$BOOLEAN`, `$FUNCTION`, `$ANY`, `$CHILD`, `$ONE`, `$EXACT`.
- **Missing**: `$MAP`, `$LIST`, `$INTEGER`, `$DECIMAL`, `$NULL`, `$NIL`, `$INSTANCE`.

---

## Transform Differences

- **TS**: Full set: `$DELETE`, `$COPY`, `$KEY`, `$ANNO`, `$MERGE`, `$EACH`, `$PACK`, `$REF`, `$FORMAT`, `$APPLY`, `$BT`, `$DS`, `$WHEN`.
- **Ruby**: Has `$DELETE`, `$COPY`, `$KEY`, `$META`, `$MERGE`, `$EACH`, `$PACK`. Missing: `$ANNO`, `$REF`, `$FORMAT`, `$APPLY`, `$BT`, `$DS`, `$WHEN`.
- **Impact**: Significantly fewer transform capabilities.

---

## Skipped Tests (Critical Issue)

The following tests are **explicitly skipped** in the test suite, indicating incomplete or broken implementations:

- `test_transform_paths` - Path-based transforms
- `test_transform_cmds` - Command parsing
- `test_transform_each` - $EACH command
- `test_transform_pack` - $PACK command
- `test_transform_modify` - Custom modifier
- `test_transform_extra` - Custom handlers
- `test_validate_basic` - Basic validation
- `test_validate_child` - Nested validation
- `test_validate_one` - One-of validator
- `test_validate_exact` - Exact value matching
- `test_validate_invalid` - Error collection

This means **most transform and all validate tests are skipped**, suggesting these implementations are incomplete.

---

## Structural/Architectural Gaps

### No Injection Class
- Uses plain hashes/state objects instead of a dedicated class.
- State management through `state` hash parameter.

### Extra Helper Functions
- `deep_merge(a, b)` - Exposed as module function (TS keeps merge internal).
- `sorted(val)` - Recursive hash key sorting (TS handles this in stringify).
- `conv(val)` - UNDEF-to-nil conversion helper.
- `log(msg)` - Debug logging helper.

### Internal Functions Exposed
- `_injectstr`, `_injecthandler`, `_setparentprop` are exposed (prefixed with `_` but still accessible).

---

## Significant Language Difference Issues

### 1. No `undefined` vs `null` Distinction

- **Issue**: Ruby has only `nil`.
- **Workaround**: Uses `UNDEF = Object.new.freeze` as sentinel object.
- **Impact**: Better than string sentinel approaches (Python/PHP) since it's a unique object. Cannot accidentally match a real data value.

### 2. Hash vs Array Distinction

- **Issue**: Ruby clearly distinguishes `Hash` from `Array`, which is better than Lua/PHP.
- **Impact**: `ismap`/`islist` are straightforward. No ambiguity issues.

### 3. Symbols vs Strings for Keys

- **Issue**: Ruby Hashes can use either `:symbol` or `"string"` keys. JSON parsing typically produces string keys.
- **Impact**: All key operations must handle string keys. Symbol keys from Ruby-native code could cause issues.
- **Recommendation**: Ensure all key comparisons use string keys consistently.

### 4. No Integer/Float Distinction in `typify`

- **Issue**: Ruby has `Integer` and `Float` classes, but `typify` returns just `"number"` for both.
- **Impact**: Cannot distinguish integer from decimal at the type system level.
- **Recommendation**: When adding bitfield type system, use `val.is_a?(Integer)` vs `val.is_a?(Float)`.

### 5. Procs vs Lambdas vs Methods

- **Issue**: Ruby has multiple callable types: `Proc`, `Lambda`, `Method`, and blocks.
- **Impact**: `isfunc` uses `val.respond_to?(:call)`, which catches all callable types. This is correct behavior.

### 6. `inject` Name Conflict

- **Issue**: Ruby's `Enumerable#inject` (aka `reduce`) is a core method. The library's `inject` module function shadows this conceptually.
- **Impact**: No actual conflict since the library function is on the `VoxgigStruct` module, but it may confuse Ruby developers.

---

## Test Coverage

Tests use Minitest framework. Coverage is **incomplete**:
- Minor function tests: Present and passing
- Walk tests: Present and passing
- Merge tests: Present and passing  
- Getpath tests: Present and passing
- Inject tests: Present and passing
- Transform tests: **Mostly skipped**
- Validate tests: **All skipped**
- Select tests: **Not present** (no `select` function)

---

## Alignment Plan

### Phase 1: Complete Transform Implementation (Critical)
1. Fix/complete `transform` to pass `transform-paths` tests
2. Fix/complete `transform` to pass `transform-cmds` tests
3. Fix/complete `transform_each` to pass `transform-each` tests
4. Fix/complete `transform_pack` to pass `transform-pack` tests
5. Add `transform_anno` ($ANNO command)
6. Add `transform_ref` ($REF command)
7. Add `transform_format` ($FORMAT command)
8. Add `transform_apply` ($APPLY command)
9. Add `$BT`, `$DS`, `$WHEN` support
10. Fix `transform-modify` and `transform-extra` support
11. Unskip all transform tests and ensure they pass

### Phase 2: Complete Validate Implementation (Critical)
12. Fix/complete `validate` to pass `validate-basic` tests
13. Fix/complete `validate_child` to pass `validate-child` tests
14. Fix/complete `validate_one` to pass `validate-one` tests
15. Fix/complete `validate_exact` to pass `validate-exact` tests
16. Fix error collection to pass `validate-invalid` tests
17. Add `$MAP`, `$LIST`, `$INTEGER`, `$DECIMAL`, `$NULL`, `$NIL`, `$INSTANCE` validators
18. Unskip all validate tests and ensure they pass

### Phase 3: Missing Core Functions
19. Implement `select(children, query)` with all operators ($AND, $OR, $NOT, $GT, $LT, $GTE, $LTE, $LIKE)
20. Implement `setpath(store, path, val, injdef)`
21. Implement `delprop(parent, key)`
22. Implement `getelem(val, key, alt)` with negative index support

### Phase 4: Type System
23. Convert `typify` to return bitfield integers
24. Add all type constants (`T_any`, `T_noval`, `T_boolean`, etc.)
25. Add `typename(t)` function
26. Export `SKIP` and `DELETE` sentinels (if not already)

### Phase 5: Missing Minor Functions
27. Add `getdef(val, alt)` helper
28. Add `size(val)` function
29. Add `slice(val, start, end, mutate)` function
30. Add `flatten(list, depth)` function
31. Add `filter(val, check)` function
32. Add `pad(str, padding, padchar)` function
33. Add `replace(s, from, to)` function
34. Add `join(arr, sep, url)` function
35. Add `jsonify(val, flags)` function
36. Add `jm`/`jt` JSON builder functions

### Phase 6: API Signature Alignment
37. Refactor `walk` to support `before`/`after` callbacks and `maxdepth`
38. Refactor `inject` to use `injdef` object parameter
39. Refactor `transform` to use `injdef` object parameter
40. Refactor `validate` to use `injdef` object parameter
41. Align `getpath` parameter order to `(store, path, injdef)`
42. Normalize `haskey` to always take `(val, key)` parameters

### Phase 7: Injection System
43. Create `Injection` class with `descend()`, `child()`, `setval()` methods
44. Add `checkPlacement`, `injectorArgs`, `injectChild` functions

### Phase 8: Test Completion
45. Add select tests
46. Add tests for all new functions
47. Run full test suite against shared `test.json`
48. Remove all test skips
