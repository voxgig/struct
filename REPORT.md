# Language Version Comparison Report

**Date**: 2026-04-12
**Canonical**: TypeScript (`ts/`)
**Languages**: JS, Python, Go, PHP, Ruby, Lua, Java, C++


## Summary

| Language | Functions | Type Constants | Sentinels | Tests | Status |
|----------|-----------|---------------|-----------|-------|--------|
| **ts** (canonical) | 40 | 15 | 2 | 83/83 pass | Reference |
| **js** | 40 | 15 | 2 | 84/84 pass | Complete |
| **py** | 40+ | 15 | 2 | 84/84 pass | Complete |
| **go** | 50+ | 15 | 2 | 92/92 pass | Complete |
| **php** | 46 | 15 | 2 | 82/82 pass | Complete |
| **rb** | 40+ | 15 | 2 | 75/75 pass | Complete |
| **lua** | 40+ | 15 | 2 | 75/75 pass | Complete |
| **java** | 40 | 15 | 2 | 1178/1178 corpus | Complete |
| **cpp** | 40 | 15 | 2 | 1178/1178 corpus | Complete |

\*\* Java and C++: full TS-canonical parity. `Injection` state machine,
`SKIP`/`DELETE` sentinels, mode constants, all 11 transform commands
(`$DELETE`/`$COPY`/`$KEY`/`$ANNO`/`$MERGE`/`$EACH`/`$PACK`/`$REF`/
`$FORMAT`/`$APPLY`), all 6 validate checkers (`$STRING`/`$TYPE`/`$ANY`/
`$CHILD`/`$ONE`/`$EXACT`), all 4 select operators (`$AND`/`$OR`/`$NOT`/
`$CMP`), and `_validation`/`_validatehandler`/`_injecthandler` internals
all wired. Per-file: minor 506/506, walk 46/46, merge 133/133, getpath 87/87,
inject 41/41, transform 187/187, validate 131/131, select 47/47.

The C++ port uses a custom `Value` class wrapping `std::variant` over
`<monostate, nullptr_t, bool, int64_t, double, string,
shared_ptr<List>, shared_ptr<Map>, Injector, Modify, const Sentinel*>`,
with a custom insertion-ordered `OrderedMap`. nlohmann/json is used
only as a JSON-text parse/serialise bridge. See
[cpp/REFACTOR_PLAN.md](./cpp/REFACTOR_PLAN.md) for the design
rationale.


## TypeScript Canonical API (Reference)

### Exported Functions (40)

**Minor utilities (25):**
typename, getdef, isnode, ismap, islist, iskey, isempty, isfunc, size, slice,
pad, typify, getelem, getprop, strkey, keysof, haskey, items, flatten, filter,
escre, escurl, join, jsonify, stringify, pathify, clone, delprop, setprop

**Major utilities (8):**
walk, merge, setpath, getpath, inject, transform, validate, select

**Builder helpers (2):**
jm, jt

**Injection helpers (3):**
checkPlacement, injectorArgs, injectChild

**Internal (not exported):**
replace (used internally but not in public API)

### Exported Constants

| Category | Symbols |
|----------|---------|
| Sentinels | SKIP, DELETE |
| Type constants (15) | T_any, T_noval, T_boolean, T_decimal, T_integer, T_number, T_string, T_function, T_symbol, T_null, T_list, T_map, T_instance, T_scalar, T_node |
| Mode constants (3) | M_KEYPRE, M_KEYPOST, M_VAL |
| Other | MODENAME |

### Exported Types
Injection (class), Injector (type), WalkApply (type)

### StructUtility Class
Wraps all functions, constants, and sentinels as instance properties.

### Transform Commands (11)
`$DELETE`, `$COPY`, `$KEY`, `$META`, `$ANNO`, `$MERGE`, `$EACH`, `$PACK`,
`$REF`, `$FORMAT`, `$APPLY`

### Validate Checkers (15)
`$MAP`, `$LIST`, `$STRING`, `$NUMBER`, `$INTEGER`, `$DECIMAL`, `$BOOLEAN`,
`$NULL`, `$NIL`, `$FUNCTION`, `$INSTANCE`, `$ANY`, `$CHILD`, `$ONE`, `$EXACT`


---


## Per-Language Analysis


### JavaScript (`js/`)

**Status: COMPLETE** -- Full functional parity with TypeScript.

**Tests:** 84/84 passing.

**Exported Functions:** All 40 canonical functions present with matching signatures.
Also exports `replace` as a public function (internal-only in TS).

**Constants:** All type constants, mode constants, sentinels, and MODENAME present.

**Classes:** Injection class and StructUtility class both present.

**Transform commands:** All 11 present.
**Validate checkers:** All 15 present.

**Differences:**
- `replace()` is exported publicly (not exported in TS canonical).
- Identical runtime semantics (both run on V8/JS engine).

**Gap count: 0**


### Python (`py/`)

**Status: COMPLETE** -- Full functional parity with TypeScript.

**Tests:** 84/84 passing.

**Exported Functions:** All 40 canonical functions present. Additionally exports:
- `replace(s, from_pat, to_str)` -- explicit string/regex replace (internal in TS)
- `joinurl(sarr)` -- convenience wrapper for `join(arr, '/', True)`
- `jo(...)` / `ja(...)` -- aliases for `jm` / `jt`

**Constants:** All type constants, mode constants, sentinels, and MODENAME present.

**Classes:** `Injection` class exported (TS exports as type-only).

**Transform commands:** All 11 present.
**Validate checkers:** All 15 present.

**Language adaptations:**
- `UNDEF = None` for undefined semantics; tests use `NULLMARK`/`UNDEFMARK` markers.
- `walk()` uses keyword arguments (`before`, `after`, `maxdepth`).

**Gap count: 0**


### Go (`go/`)

**Status: COMPLETE** -- Full functional parity with TypeScript.

**Tests:** 92/92 passing.

**Exported Functions:** All 40 canonical functions present, plus Go-idiomatic variants:
- `ItemsApply()` -- separate function (TS uses overloaded `items`)
- `CloneFlags()` -- clone with options (Go lacks optional params)
- `TransformModify()`, `TransformModifyHandler()`, `TransformCollect()` -- variants
- `WalkDescend()` -- walk with explicit path tracking
- `JoinUrl()` -- convenience URL join
- `Jo()`, `Ja()` -- aliases for `Jm`/`Jt` (Go naming: JSON Object/Array)
- `ListRef[T]` -- generic wrapper for mutable list references

**Constants:** All type constants, mode constants, sentinels, MODENAME, and PLACEMENT present.

**Classes/Types:** `Injection` struct, `Injector` func type, `WalkApply` func type, `Modify` func type.

**Transform commands:** All 11 present.
**Validate checkers:** All 15 present.

**Language adaptations:**
- `nil` represents both undefined and null; tests use `NULLMARK`/`UNDEFMARK`.
- Multiple function variants replace optional parameters.
- `Validate` returns `(any, error)` tuple per Go idiom.
- `ListRef[T]` generic for reference-stable slices.

**Gap count: 0**


### PHP (`php/`)

**Status: COMPLETE** -- Full functional parity with TypeScript.

**Tests:** 82/82 passing, 920 assertions.

**Exported Functions:** 46 public static methods. All 40 canonical functions present
plus: replace, joinurl, cloneWrap, cloneUnwrap, checkPlacement, injectorArgs,
injectChild.

**Constants:** All type constants, mode constants, sentinels (SKIP, DELETE), and
MODENAME present.

**Transform commands:** All 11 present (`$DELETE`, `$COPY`, `$KEY`, `$META`,
`$ANNO`, `$MERGE`, `$EACH`, `$PACK`, `$REF`, `$FORMAT`, `$APPLY`).

**Validate checkers:** All 15 present (registered via validate_TYPE).

**Language adaptations:**
- `UNDEF = '__UNDEFINED__'` string sentinel for undefined semantics.
- `setprop` uses `&$parent` reference for mutation (PHP arrays are value types).
- `ListRef` wrapper class for reference-stable list injection (mirrors Go pattern).

**Gap count: 0**


### Ruby (`rb/`)

**Status: COMPLETE** -- Full functional parity with TypeScript.

**Tests:** 75/75 passing, 150 assertions.

**Exported Functions:** All 40 canonical functions present plus replace, joinurl,
checkPlacement, injectorArgs, injectChild, select operators (AND, OR, NOT, CMP).

**Constants:** All type constants, mode constants (M_KEYPRE, M_KEYPOST, M_VAL),
sentinels (SKIP, DELETE), and MODENAME present.

**Injection class:** Full implementation with descend, child, setval methods.

**Transform commands:** All 11 present (`$DELETE`, `$COPY`, `$KEY`, `$META`,
`$ANNO`, `$MERGE`, `$EACH`, `$PACK`, `$REF`, `$FORMAT`, `$APPLY`).

**Validate checkers:** All 15 present (`$MAP`, `$LIST`, `$STRING`, `$NUMBER`,
`$INTEGER`, `$DECIMAL`, `$BOOLEAN`, `$NULL`, `$NIL`, `$FUNCTION`, `$INSTANCE`,
`$ANY`, `$CHILD`, `$ONE`, `$EXACT`).

**Language adaptations:**
- `UNDEF = Object.new.freeze` sentinel for absent values (distinct from nil/JSON null).
- `nil` represents JSON null; `typify(nil)` returns `T_scalar | T_null`.
- Walk-based merge with before/after callbacks and maxdepth.

**Gap count: 0**


### Lua (`lua/`)

**Status: COMPLETE** -- Full functional parity with TypeScript.

**Tests:** 75/75 passing.

**Exported Functions:** All 40 canonical functions present plus `replace` (internal
in TS). Full list: clone, delprop, escre, escurl, filter, flatten, getdef,
getelem, getpath, getprop, haskey, inject, isempty, isfunc, iskey, islist,
ismap, isnode, items, join, jm, jt, jsonify, keysof, merge, pad, pathify,
select, setpath, setprop, size, slice, strkey, stringify, transform, typify,
typename, validate, walk, checkPlacement, injectorArgs, injectChild.

**Constants:** All 15 type constants, mode constants, sentinels, MODENAME present.

**Transform commands:** All 11 present (`$DELETE`, `$COPY`, `$KEY`, `$ANNO`, `$MERGE`, `$EACH`, `$PACK`, `$REF`, `$FORMAT`, `$APPLY`, `$META`).
**Validate checkers:** All 15 present.

**Language adaptations:**
- 1-based indexing internally; external API uses 0-based with translation.
- `__jsontype` metatable field distinguishes arrays from objects (Lua tables are unified).
- `escre()` escapes Lua pattern chars (not regex).
- `nil` represents undefined; no native null/undefined distinction.
- `items()` returns `{key, val}` tables instead of `[key, val]` arrays.

**Gap count: 0**


### Java (`java/`)

**Status: INCOMPLETE** -- Basic utilities only; major subsystems missing.

**Tests:** No standard test runner configured. `StructTest.java` exists but minimal.

**Exported Functions (22 of 40):**
Present: typify, typename, isFunc, isNode, isMap, isList, isEmpty, isKey,
getProp, setProp, hasKey, keysof, items, pathify, stringify, escapeRegex,
escapeUrl, joinUrl, clone, walk (2 overloads).

Missing (18):
- **Path operations:** getpath, setpath
- **Major subsystems:** inject, transform, validate, select
- **Minor utilities:** getdef, getelem, delprop, size, slice, flatten, filter,
  pad, replace, join, jsonify, strkey, merge (stubbed)
- **Builders:** jm, jt
- **Injection helpers:** checkPlacement, injectorArgs, injectChild

**Constants:** All 15 type constants present (bitfield integers).
- Missing: SKIP, DELETE sentinels.
- Missing: M_KEYPRE, M_KEYPOST, M_VAL mode constants (enum exists but unused).
- Missing: MODENAME.

**No Injection class.** InjectMode enum defined but not used.

**Transform commands:** None implemented.
**Validate checkers:** None implemented.

**Implementation issues:**
- `keysof()` bug: returns list of zeros for Lists instead of string indices.
- `walk()` post-order only; no `before`/`after` callbacks or `maxdepth`.
- `escapeRegex()` uses `Pattern.quote()` wrapping instead of char-by-char escaping.
- `stringify()` format differs from canonical.

**Gap count: ~30** (18 missing functions + 6 missing subsystem commands + 4 missing constants + bugs)


### C++ (`cpp/`)

**Status: INCOMPLETE** -- Basic type/property utilities only; major subsystems missing.

**Tests:** Catch2 framework; limited test coverage for ~16 functions.

**Exported Functions (18 of 40):**
Present: typename_of, typify, isnode, ismap, islist, iskey, isempty, isfunc,
getprop, setprop, keysof, haskey, items, escre, escurl, joinurl, stringify,
clone, walk, merge (partial).

Missing (22):
- **Path operations:** getpath, setpath
- **Major subsystems:** inject, transform, validate, select
- **Minor utilities:** getdef, getelem, delprop, size, slice, flatten, filter,
  pad, replace, join, jsonify, strkey, pathify
- **Builders:** jm, jt
- **Injection helpers:** checkPlacement, injectorArgs, injectChild

**Constants:** All 15 type constants present (bitfield integers).
- Missing: SKIP, DELETE sentinels.
- Missing: M_KEYPRE, M_KEYPOST, M_VAL mode constants.
- Missing: MODENAME.

**No Injection class.**

**Transform commands:** None implemented.
**Validate checkers:** None implemented.

**Implementation issues:**
- All functions use `args_container&&` (vector of JSON) -- no type-safe signatures.
- `walk()` casts function pointers through JSON via `intptr_t` (undefined behavior).
- `clone()` is shallow copy (TS does deep clone).
- `merge()` has large commented-out section; partially implemented.
- Debug console output left in code.

**Gap count: ~35** (22 missing functions + all transform/validate + missing constants + UB issues)


---


## Function Parity Matrix

| Function | ts | js | py | go | php | lua | rb | java | cpp |
|----------|----|----|----|----|-----|-----|----|------|-----|
| **Minor utilities** | | | | | | | | | |
| typename | Y | Y | Y | Y | Y | Y | Y | Y | Y |
| getdef | Y | Y | Y | Y | Y | Y | Y | - | - |
| isnode | Y | Y | Y | Y | Y | Y | Y | Y | Y |
| ismap | Y | Y | Y | Y | Y | Y | Y | Y | Y |
| islist | Y | Y | Y | Y | Y | Y | Y | Y | Y |
| iskey | Y | Y | Y | Y | Y | Y | Y | Y | Y |
| isempty | Y | Y | Y | Y | Y | Y | Y | Y | Y |
| isfunc | Y | Y | Y | Y | Y | Y | Y | Y | Y |
| size | Y | Y | Y | Y | Y | Y | Y | - | - |
| slice | Y | Y | Y | Y | Y | Y | Y | - | - |
| pad | Y | Y | Y | Y | Y | Y | Y | - | - |
| typify | Y | Y | Y | Y | Y | Y | Y | Y | Y |
| getelem | Y | Y | Y | Y | Y | Y | Y | - | - |
| getprop | Y | Y | Y | Y | Y | Y | Y | Y | Y |
| strkey | Y | Y | Y | Y | Y | Y | Y | - | - |
| keysof | Y | Y | Y | Y | Y | Y | Y | Y* | Y |
| haskey | Y | Y | Y | Y | Y | Y | Y | Y | Y |
| items | Y | Y | Y | Y | Y | Y | Y | Y | Y |
| flatten | Y | Y | Y | Y | Y | Y | Y | - | - |
| filter | Y | Y | Y | Y | Y | Y | Y | - | - |
| escre | Y | Y | Y | Y | Y | Y | Y | Y | Y |
| escurl | Y | Y | Y | Y | Y | Y | Y | Y | Y |
| join | Y | Y | Y | Y | Y | Y | Y | - | - |
| jsonify | Y | Y | Y | Y | Y | Y | Y | - | - |
| stringify | Y | Y | Y | Y | Y | Y | Y | Y | Y |
| pathify | Y | Y | Y | Y | Y | Y | Y | Y | - |
| clone | Y | Y | Y | Y | Y | Y | Y | Y | Y* |
| delprop | Y | Y | Y | Y | Y | Y | Y | - | - |
| setprop | Y | Y | Y | Y | Y | Y | Y | Y | Y |
| **Major utilities** | | | | | | | | | |
| walk | Y | Y | Y | Y | Y | Y | Y* | Y* | Y* |
| merge | Y | Y | Y | Y | Y | Y | Y | - | Y* |
| setpath | Y | Y | Y | Y | Y | Y | Y | - | - |
| getpath | Y | Y | Y | Y | Y | Y | Y | - | - |
| inject | Y | Y | Y | Y | Y | Y | Y | - | - |
| transform | Y | Y | Y | Y | Y | Y | Y | - | - |
| validate | Y | Y | Y | Y | Y | Y | Y | - | - |
| select | Y | Y | Y | Y | Y | Y | Y | - | - |
| **Builders** | | | | | | | | | |
| jm | Y | Y | Y | Y | Y | Y | Y | - | - |
| jt | Y | Y | Y | Y | Y | Y | Y | - | - |
| **Injection helpers** | | | | | | | | | |
| checkPlacement | Y | Y | Y | Y | Y | Y | Y | - | - |
| injectorArgs | Y | Y | Y | Y | Y | Y | Y | - | - |
| injectChild | Y | Y | Y | Y | Y | Y | Y | - | - |

**Legend:** Y = present and aligned, Y* = present with issues (see notes), - = missing


## Transform Command Parity

| Command | ts | js | py | go | php | lua | rb | java | cpp |
|---------|----|----|----|----|-----|-----|----|------|-----|
| $DELETE | Y | Y | Y | Y | Y | Y | Y | - | - |
| $COPY | Y | Y | Y | Y | Y | Y | Y | - | - |
| $KEY | Y | Y | Y | Y | Y | Y | Y | - | - |
| $META | Y | Y | Y | Y | Y | Y | Y | - | - |
| $ANNO | Y | Y | Y | Y | Y | Y | Y | - | - |
| $MERGE | Y | Y | Y | Y | Y | Y | Y | - | - |
| $EACH | Y | Y | Y | Y | Y | Y | Y | - | - |
| $PACK | Y | Y | Y | Y | Y | Y | Y | - | - |
| $REF | Y | Y | Y | Y | Y | Y | Y | - | - |
| $FORMAT | Y | Y | Y | Y | Y | Y | Y | - | - |
| $APPLY | Y | Y | Y | Y | Y | Y | Y | - | - |

## Validate Checker Parity

| Checker | ts | js | py | go | php | lua | rb | java | cpp |
|---------|----|----|----|----|-----|-----|----|------|-----|
| $MAP | Y | Y | Y | Y | Y | Y | Y | - | - |
| $LIST | Y | Y | Y | Y | Y | Y | Y | - | - |
| $STRING | Y | Y | Y | Y | Y | Y | Y | - | - |
| $NUMBER | Y | Y | Y | Y | Y | Y | Y | - | - |
| $INTEGER | Y | Y | Y | Y | Y | Y | Y | - | - |
| $DECIMAL | Y | Y | Y | Y | Y | Y | Y | - | - |
| $BOOLEAN | Y | Y | Y | Y | Y | Y | Y | - | - |
| $NULL | Y | Y | Y | Y | Y | Y | Y | - | - |
| $NIL | Y | Y | Y | Y | Y | Y | Y | - | - |
| $FUNCTION | Y | Y | Y | Y | Y | Y | Y | - | - |
| $INSTANCE | Y | Y | Y | Y | Y | Y | Y | - | - |
| $ANY | Y | Y | Y | Y | Y | Y | Y | - | - |
| $CHILD | Y | Y | Y | Y | Y | Y | Y | - | - |
| $ONE | Y | Y | Y | Y | Y | Y | Y | - | - |
| $EXACT | Y | Y | Y | Y | Y | Y | Y | - | - |

^ Ruby uses `$OBJECT`/`$ARRAY` naming instead of `$MAP`/`$LIST`.


## Constant Parity

| Constant | ts | js | py | go | php | lua | rb | java | cpp |
|----------|----|----|----|----|-----|-----|----|------|-----|
| T_any..T_node (15) | Y | Y | Y | Y | Y | Y | Y | Y | Y |
| M_KEYPRE | Y | Y | Y | Y | Y | Y | Y | - | - |
| M_KEYPOST | Y | Y | Y | Y | Y | Y | Y | - | - |
| M_VAL | Y | Y | Y | Y | Y | Y | Y | - | - |
| MODENAME | Y | Y | Y | Y | Y | Y | Y | - | - |
| SKIP | Y | Y | Y | Y | Y | Y | Y | - | - |
| DELETE | Y | Y | Y | Y | Y | Y | Y | - | - |


---


## Key Issues by Language

### PHP
No remaining issues. Full parity achieved.

### Ruby
No remaining issues. Full parity achieved.

### Java
1. **P0 - Missing subsystems**: No inject, transform, validate, select.
2. **P0 - Missing path ops**: No getpath, setpath.
3. **P1 - No Injection class**: Cannot support injection state management.
4. **P1 - No sentinels**: SKIP, DELETE not defined.
5. **P2 - keysof() bug**: Returns zeros for list indices.
6. **P2 - walk()**: Post-order only, no before/after or maxdepth.

### C++
1. **P0 - Missing subsystems**: No inject, transform, validate, select.
2. **P0 - Missing path ops**: No getpath, setpath.
3. **P0 - Undefined behavior**: `walk()` casts function pointers through `intptr_t`.
4. **P1 - No Injection class**: Cannot support injection state management.
5. **P1 - Shallow clone**: Should be deep clone.
6. **P2 - No type-safe signatures**: All functions use `args_container&&`.


---


## Completeness Ranking

1. **js** -- 100% parity. Identical runtime semantics. 84/84 tests passing.
2. **go** -- 100% parity. Idiomatic Go adaptations. 92/92 tests passing.
3. **py** -- 100% parity. All functions, constants, and commands present. 84/84 tests passing.
4. **lua** -- 100% parity. All functions and commands present. 75/75 tests passing.
5. **php** -- 100% parity. All functions, constants, and commands present. 82/82 tests passing.
6. **rb** -- 100% parity. All 40 functions, Injection class, all 11 transform commands, all 15 validators, select with operators. 75/75 tests passing.
7. **java** -- ~45% parity. Basic utilities only; all major subsystems missing.
8. **cpp** -- ~40% parity. Basic utilities only; UB issues; all major subsystems missing.


---


## Recommendations

### Immediate (P0)
- **Java/C++**: Implement getpath, setpath as foundation for inject/transform/validate.
- **C++**: Fix undefined behavior in `walk()` function pointer handling.

### Short-term (P1)
- **Java**: Implement Injection class and SKIP/DELETE sentinels.
- **Java**: Implement inject, transform, validate, select subsystems.

### Medium-term (P2)
- **Java**: Fix keysof() bug, improve walk() to support before/after callbacks.
- **C++**: Redesign function signatures for type safety.
