# Python (py) - Review vs TypeScript Canonical

## Overview

The Python version is one of the most complete implementations, with **39 exported functions** closely matching the TypeScript canonical. It uses the unified `injdef` parameter pattern and has a full `InjectState` class. The main gaps are minor naming differences and a few missing utilities.

---

## Missing Functions

| Function | Category | Impact |
|----------|----------|--------|
| `replace` | String | No unified string replace wrapper |
| `getdef` | Property access | Not exported (may exist internally) |

---

## Naming Differences

| TS Name | Python Name | Notes |
|---------|-------------|-------|
| `jm` | `jo` | JSON map/object builder |
| `jt` | `ja` | JSON tuple/array builder |
| `joinurl` | `joinurl` | Also exists as standalone (TS uses `join` with `url` flag) |

---

## API Signature Differences

### 1. `walk` signature differs slightly

- **TS**: `walk(val, before?, after?, maxdepth?, key?, parent?, path?)`
- **Python**: `walk(val, apply=None, key=UNDEF, parent=UNDEF, path=UNDEF, *, before=None, after=None, maxdepth=None)`
- **Notes**: Python uses keyword-only arguments for `before`/`after`/`maxdepth` and also supports a positional `apply` for backward compatibility. This is actually a reasonable Pythonic adaptation.

### 2. Default parameter handling uses `UNDEF` sentinel

- **TS**: Uses `undefined` (language native).
- **Python**: Uses `UNDEF = None` as sentinel, since Python's `None` maps to JSON `null`.
- **Impact**: This is a necessary language adaptation. However, `UNDEF = None` conflates Python's `None` with "no value". The TS version distinguishes between `undefined` and `null`.

### 3. `validate` return type

- **TS**: Returns validated data; errors collected in `injdef.errs` array or thrown.
- **Python**: Same pattern via `injdef` with `errs` list.
- **Notes**: Aligned correctly.

---

## Structural Differences

### InjectState vs Injection Class

- **TS**: Class named `Injection` with methods `descend()`, `child()`, `setval()`, `toString()`.
- **Python**: Class named `InjectState` with same methods.
- **Impact**: Minor naming difference. The class is functionally equivalent.

### Type Constants

- **TS** and **Python** both use bitfield type constants (`T_any`, `T_noval`, etc.).
- **Python**: All constants present and matching.
- **Notes**: Fully aligned.

### SKIP/DELETE Sentinels

- Both versions export `SKIP` and `DELETE` with matching structure.

---

## Significant Language Difference Issues

### 1. `None` vs `undefined`/`null` Distinction

- **Issue**: Python has only `None`, while JavaScript/TypeScript distinguishes `undefined` from `null`. The library uses `UNDEF = None`, which means Python cannot natively distinguish "absent value" from "JSON null".
- **Workaround**: The test runner uses `NULLMARK = '__NULL__'` and `UNDEFMARK = '__UNDEF__'` string markers, and a `nullModifier` to convert between them.
- **Impact**: This is an inherent language limitation. The workaround is adequate but care must be taken in edge cases where the distinction matters.

### 2. Dictionary Ordering

- Python 3.7+ guarantees insertion-order dict preservation, but `keysof` returns sorted keys to match TS behavior. This is correct.

### 3. No Symbol Type

- Python has no equivalent of JavaScript `Symbol`. The `T_symbol` type constant exists but `typify` will never return it.
- **Impact**: Minimal; symbols are rarely used in the data structures this library processes.

### 4. Integer vs Float Distinction

- Python natively distinguishes `int` from `float`, which maps well to TS's `T_integer` vs `T_decimal`.
- **Impact**: Good alignment; Python may actually be more precise here.

### 5. Function Identity in Clone

- Both versions copy function references rather than cloning them. Python's `callable` check via `isfunc` works correctly for this.

---

## Validation Differences

- **TS**: Uses `$MAP`, `$LIST`, `$STRING`, `$NUMBER`, `$INTEGER`, `$DECIMAL`, `$BOOLEAN`, `$NULL`, `$NIL`, `$FUNCTION`, `$INSTANCE`, `$ANY`, `$CHILD`, `$ONE`, `$EXACT`.
- **Python**: Same validators present.
- **Notes**: Fully aligned.

---

## Transform Differences

- **TS**: Supports `$DELETE`, `$COPY`, `$KEY`, `$ANNO`, `$MERGE`, `$EACH`, `$PACK`, `$REF`, `$FORMAT`, `$APPLY`, `$BT`, `$DS`, `$WHEN`.
- **Python**: Same transform commands present.
- **Notes**: Fully aligned.

---

## Test Coverage

Python tests cover all major categories matching TS:
- Minor functions, walk, merge, getpath, inject, transform, validate, select, JSON builders.
- Test categories are comprehensive and use the shared `test.json` spec.

### Minor Gaps
- Edge case tests may differ slightly in coverage.

---

## Alignment Plan

### Phase 1: Minor Fixes (Low Effort)
1. Add `replace(s, from_str, to)` function if missing
2. Verify `getdef(val, alt)` is exported (add if missing)
3. Consider renaming `jo`/`ja` to `jm`/`jt` to match TS (or add aliases)

### Phase 2: Naming Alignment
4. Consider renaming `InjectState` to `Injection` to match TS class name
5. Ensure all type constant names exactly match TS

### Phase 3: Edge Case Alignment
6. Review `None`/`UNDEF` handling for edge cases where TS distinguishes `undefined` from `null`
7. Verify `clone` behavior matches TS for all edge cases (functions, instances)
8. Run full test suite comparison against TS test.json to identify any failing cases

### Phase 4: Documentation
9. Document the `None` vs `undefined`/`null` language difference and its implications
10. Document any Python-specific idioms used (keyword-only args in `walk`, etc.)
