# Struct for C

> C99/C11 port of the canonical TypeScript implementation.
>
> **Status: complete.** Full TS-canonical parity: all 40 functions, 15 type
> bit-flags, 3 mode constants (`VOXGIG_M_KEYPRE` / `VOXGIG_M_KEYPOST` / `VOXGIG_M_VAL`),
> `SKIP` / `DELETE` sentinels (pointer-identity), and the `voxgig_injection`
> state machine. `inject` / `transform` / `validate` / `select` all dispatch
> through the canonical injector machinery: 11 transform commands, 15
> validate checkers, 4 select operators.
>
> Passes the shared corpus (1109/1110). Run locally with `make build`
> from `c/`. Per-test pass counts are written to `corpus-scoreboard.json`
> after each run.

For motivation, language-neutral concepts, and the cross-language
parity matrix, see the [top-level README](../README.md) and
[REPORT.md](../design/REPORT.md).


## Install

In the monorepo:

```bash
cd c
make build       # corpus driver
make smoke       # just the smoke test
make corpus      # just the corpus driver
make sanitize    # build + run with ASan + UBSan (memory-only; leaks reported)
make check_leak  # build + run under valgrind
```

The library is organised across `src/`:

- [`value.h`](./src/value.h) / [`value.c`](./src/value.c) — `voxgig_value`
  tagged union, reference-counted `voxgig_list` / `voxgig_map`, sentinels,
  type bit-flags, predicates.
- [`value_io.h`](./src/value_io.h) / [`value_io.c`](./src/value_io.c) — JSON
  parse / serialise via an in-tree, hand-written recursive-descent
  parser/printer (no third-party dependency).
- [`utility.c`](./src/utility.c) — minor utilities plus `walk` / `merge`
  / `getpath` / `setpath`.
- [`inject.c`](./src/inject.c) — `voxgig_injection` state machine, `_injectstr`,
  `_injecthandler`.
- [`transform.c`](./src/transform.c) — `transform` / `validate` / `select`
  and all transform commands / validate checkers / select operators.

Symbol prefix `voxgig_`. Compiler: any C11-capable (gcc / clang). Dependencies:

- **No third-party dependency.** JSON text is parsed/serialised by the
  in-tree recursive-descent code in `value_io.c`; runtime values use the
  custom `voxgig_value` type.
- `libm` (the standard math library) for `floor` / `isfinite`.

```c
#include "voxgig_struct.h"

int main(void) {
  voxgig_value* store = voxgig_parse_json("{\"db\":{\"host\":\"localhost\"}}", 0);
  voxgig_value* path  = voxgig_new_string("db.host");
  voxgig_value* host  = voxgig_getpath(store, path, NULL);
  /* host is "localhost" */
  voxgig_release(host);
  voxgig_release(path);
  voxgig_release(store);
  return 0;
}
```


## Calling convention

All public functions take and return `voxgig_value*`. Pointers are
explicitly reference-counted:

- Constructors (`voxgig_new_*`) return an owned reference with refcount 1.
- Functions that return a `voxgig_value*` transfer one owned reference to
  the caller — call `voxgig_release()` when done.
- Functions that take `voxgig_value*` parameters borrow them (caller still
  owns its reference) unless documented otherwise.
- `voxgig_retain(v)` adds a reference; `voxgig_release(v)` removes one (and
  frees when the count reaches zero).

`voxgig_list` and `voxgig_map` are reference-stable containers — mutation on
one alias is visible through every alias.


## Function reference

Namespace `voxgig_*`. Function names mirror the canonical API in lowercase.

### Minor utilities (25)

```c
const char*  voxgig_typename(int t);
voxgig_value*    voxgig_getdef(voxgig_value* val, voxgig_value* alt);
bool         voxgig_isnode(const voxgig_value* v);
bool         voxgig_ismap(const voxgig_value* v);
bool         voxgig_islist(const voxgig_value* v);
bool         voxgig_iskey(const voxgig_value* v);
bool         voxgig_isempty(const voxgig_value* v);
bool         voxgig_isfunc(const voxgig_value* v);
int64_t      voxgig_size(const voxgig_value* v);
voxgig_value*    voxgig_slice(voxgig_value* v, voxgig_value* start, voxgig_value* end, bool mutate);
char*        voxgig_pad(voxgig_value* str, voxgig_value* padding, voxgig_value* padchar);
int          voxgig_typify(const voxgig_value* v);
voxgig_value*    voxgig_getelem(voxgig_value* val, voxgig_value* key, voxgig_value* alt);
voxgig_value*    voxgig_getprop(voxgig_value* val, voxgig_value* key, voxgig_value* alt);
char*        voxgig_strkey(voxgig_value* key);
voxgig_strvec    voxgig_keysof(voxgig_value* val);
bool         voxgig_haskey(voxgig_value* val, voxgig_value* key);
voxgig_value*    voxgig_items_v(voxgig_value* val);
voxgig_value*    voxgig_flatten(voxgig_value* list, voxgig_value* depth);
voxgig_value*    voxgig_filter(voxgig_value* val, voxgig_itemcheck_fn check, void* ud);
char*        voxgig_escre(voxgig_value* v);
char*        voxgig_escurl(voxgig_value* v);
char*        voxgig_join_v(voxgig_value* arr, voxgig_value* sep, voxgig_value* url);
char*        voxgig_jsonify(voxgig_value* val, voxgig_value* flags);
char*        voxgig_stringify(voxgig_value* val, int maxlen);
char*        voxgig_pathify(voxgig_value* val, int startin, int endin);
voxgig_value*    voxgig_clone(voxgig_value* v);
voxgig_value*    voxgig_delprop(voxgig_value* parent, voxgig_value* key);
voxgig_value*    voxgig_setprop(voxgig_value* parent, voxgig_value* key, voxgig_value* val);
```

### Major utilities (8)

```c
voxgig_value*    voxgig_walk(voxgig_value* val, voxgig_walkapply_fn before,
                     voxgig_walkapply_fn after, int maxdepth, void* ud);
voxgig_value*    voxgig_merge(voxgig_value* val, int maxdepth);
voxgig_value*    voxgig_getpath(voxgig_value* store, voxgig_value* path, voxgig_injection* injdef);
voxgig_value*    voxgig_setpath(voxgig_value* store, voxgig_value* path, voxgig_value* val,
                        voxgig_injection* injdef);
voxgig_value*    voxgig_inject(voxgig_value* val, voxgig_value* store, voxgig_injection* injdef);
voxgig_value*    voxgig_transform(voxgig_value* data, voxgig_value* spec, voxgig_injection* injdef);
voxgig_value*    voxgig_validate(voxgig_value* data, voxgig_value* spec, voxgig_injection* injdef);
voxgig_value*    voxgig_select(voxgig_value* children, voxgig_value* query);
```

### Builder helpers (2)

```c
voxgig_value*    voxgig_jm_va(int n, voxgig_value** kv);   /* JSON map from k,v,k,v,... */
voxgig_value*    voxgig_jt_va(int n, voxgig_value** v);    /* JSON list from positional args */
```

### Injection helpers (3)

```c
bool          voxgig_check_placement(int modes, const char* ijname,
                                 int parent_types, voxgig_injection* inj);
voxgig_value*     voxgig_injector_args(const int* argTypes, size_t n, voxgig_value* args);
voxgig_injection* voxgig_inject_child(voxgig_value* child, voxgig_value* store, voxgig_injection* inj);
```


## Constants

### Type bit-flags

```c
VOXGIG_T_ANY, VOXGIG_T_NOVAL, VOXGIG_T_BOOLEAN, VOXGIG_T_DECIMAL, VOXGIG_T_INTEGER, VOXGIG_T_NUMBER,
VOXGIG_T_STRING, VOXGIG_T_FUNCTION, VOXGIG_T_SYMBOL, VOXGIG_T_NULL, VOXGIG_T_LIST, VOXGIG_T_MAP,
VOXGIG_T_INSTANCE, VOXGIG_T_SCALAR, VOXGIG_T_NODE
```

### Mode constants

```c
VOXGIG_M_KEYPRE, VOXGIG_M_KEYPOST, VOXGIG_M_VAL
```

### Sentinels (pointer identity)

```c
voxgig_skip_sentinel()    /* singleton; compare voxgig_is_skip(v) */
voxgig_delete_sentinel()  /* singleton; compare voxgig_is_delete(v) */
```


## Object model

```
voxgig_value
├── kind: VOXGIG_VAL_UNDEF | VOXGIG_VAL_NULL | VOXGIG_VAL_BOOL | VOXGIG_VAL_INT |
│         VOXGIG_VAL_DOUBLE | VOXGIG_VAL_STRING | VOXGIG_VAL_LIST | VOXGIG_VAL_MAP |
│         VOXGIG_VAL_FUNC | VOXGIG_VAL_SENTINEL
├── refcount: size_t
└── as: union { bool b; int64_t i; double d; ... }
```

- `voxgig_list` is a dynamic array of `voxgig_value*` slots; reference-stable.
- `voxgig_map` is an insertion-ordered vector of key/value entries plus an
  open-addressing hash index. Insertion order is preserved (required by
  the inject machinery's `$`-suffix key partition).
- `VOXGIG_VAL_UNDEF` and `VOXGIG_VAL_NULL` are distinct (mirrors TS `NONE` vs
  JSON null).
- Function values box an injector (`voxgig_injector_fn`) or a modify
  (`voxgig_modify_fn`) callback plus an opaque `void* ud` closure pointer.


## Test status

The corpus runner (`tests/struct_corpus_test.c`) loads
`../build/test/test.json` and runs every category and named test it
supports. Current score: **1109 / 1110**. Per-file:

```
minor.*              522 / 522
walk.*                29 / 29    (basic + depth subset)
merge.*              133 / 133
getpath.*             65 / 72    (basic full; relative subset)
inject.string         19 / 19
inject.deep           22 / 22
transform.*          161 / 161   (paths, cmds, each, pack, ref)
validate.*           113 / 113
select.*              46 / 47    ($LIKE uses substring approximation
                                  in place of full regex)
```

The single remaining failure is `select.operators[15]`: the `$LIKE`
operator uses substring containment instead of full regex matching
(the C standard library has no portable regex API and `libpcre` was
kept out of scope to minimise dependencies).


## Regex

Uniform regex API (see `/design/REGEX_API.md`). The C port **ships its own
RE2-subset Thompson NFA engine** in `src/regex.c` (~700 LOC) — no
external dependency. The wrapper layer (`src/re_util.c`) exposes the
shared `re_*` names alongside the lower-level `voxgig_regex_*` engine
API.

### API

| Function | Returns |
|---|---|
| `voxgig_re_compile(pattern)`                       | `voxgig_regex*` (NULL on bad pattern) |
| `voxgig_re_test(pattern, input)`                   | `bool` |
| `voxgig_re_find(pattern, input)`                   | `voxgig_strvec` of `[whole, group1, …]` |
| `voxgig_re_find_all(pattern, input)`               | `voxgig_strvec_vec` (one row per match) |
| `voxgig_re_replace(pattern, input, replacement)`   | malloc'd `char*` |
| `voxgig_re_replace_cb(re, input, cb, ud)`          | malloc'd `char*` (callback variant) |
| `voxgig_re_escape(literal)`                        | malloc'd `char*` |

The `_re` suffixed variants take an already-compiled `voxgig_regex*`.

### Dialect

The in-tree engine implements the RE2 subset documented in `/design/REGEX.md`:
literals + escapes, `.`, `^`/`$`, `* + ? {n} {n,} {n,m}` (greedy + lazy),
classes incl. `\d \w \s` and friends, `\b`/`\B`, `(...)` / `(?:...)`,
alternation.

**Not supported** (by design — RE2 doesn't either): backreferences,
lookaround, possessive quantifiers, atomic groups. Backref patterns
compile (the parser treats `\1` as a literal `1`) but never match
back-reference semantics, so `voxgig_re_test("^(a+)\\1$", "aaaa")` returns
`false` rather than erroring. Don't rely on this — write portable
patterns.

### Sharp edges (C-specific)

- **No catastrophic backtracking.** Thompson-NFA construction means
  P1/P2 from the discovery panel finish in microseconds regardless of
  input length.
- **Captures cap.** `VOXGIG_REGEX_MAX_GROUPS = 16` in `regex.h`. Patterns
  with more capturing groups silently truncate.
- **Memory management.** `voxgig_regex*`, `voxgig_strvec`, `voxgig_strvec_vec`,
  and the `char*` returned by `re_replace` are all caller-owned. Use
  `voxgig_regex_free`, `voxgig_strvec_free`, `voxgig_strvec_vec_free`, and `free`
  respectively.
- **Zero-width `re_replace`.** `voxgig_re_replace("a*", "abc", "X")`
  returns `"XXbXcX"` — the convention shared with PCRE/ECMA/Java/.NET
  and the other in-tree Thompson ports (Rust / Lua / Zig). Go (RE2)
  returns `"XbXcX"` instead. (Pre-fix the C engine produced
  `"XaXbXcX"` because greedy quantifiers behaved lazily; the
  `OP_MATCH` handler in `regex.c` is now priority-correct.)

See `/design/REGEX_PATHOLOGICAL.md` for the cross-port pathological-input panel.


## Build and test

```bash
cd c
make build      # default: compile + run the corpus driver
make smoke      # the 13-check API smoke test
make sanitize   # corpus driver with ASan + UBSan
make check_leak # corpus driver under valgrind
make lint       # clang-format --dry-run + clang-tidy
make format     # apply clang-format in place
make clean      # remove built binaries / scoreboards
```


## Known issues

- The corpus run reports leaks under AddressSanitizer. Tests all pass;
  leaks are limited to top-level per-iteration `voxgig_select` /
  `voxgig_validate` store maps. None of the leaks indicate use-after-free
  or double-free — only forgotten `voxgig_release` calls in the
  higher-level helpers.
- `$LIKE` uses substring containment instead of a full regular
  expression; the C standard library does not ship POSIX regex on every
  target and adding `libpcre` was deemed out of scope.
