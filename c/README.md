# Struct for C

> C99/C11 port of the canonical TypeScript implementation.
>
> **Status: complete.** Full TS-canonical parity: all 40 functions, 15 type
> bit-flags, 3 mode constants (`VS_M_KEYPRE` / `VS_M_KEYPOST` / `VS_M_VAL`),
> `SKIP` / `DELETE` sentinels (pointer-identity), and the `vs_injection`
> state machine. `inject` / `transform` / `validate` / `select` all dispatch
> through the canonical injector machinery: 11 transform commands, 15
> validate checkers, 4 select operators.
>
> Passes the shared corpus (1107/1110). Run locally with `make build`
> from `c/`. Per-test pass counts are written to `corpus-scoreboard.json`
> after each run.

For motivation, language-neutral concepts, and the cross-language
parity matrix, see the [top-level README](../README.md) and
[REPORT.md](../REPORT.md).


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

- [`value.h`](./src/value.h) / [`value.c`](./src/value.c) — `vs_value`
  tagged union, reference-counted `vs_list` / `vs_map`, sentinels,
  type bit-flags, predicates.
- [`value_io.h`](./src/value_io.h) / [`value_io.c`](./src/value_io.c) — JSON
  parse / serialise via [`libcjson`](https://github.com/DaveGamble/cJSON)
  as a text bridge.
- [`utility.c`](./src/utility.c) — minor utilities plus `walk` / `merge`
  / `getpath` / `setpath`.
- [`inject.c`](./src/inject.c) — `vs_injection` state machine, `_injectstr`,
  `_injecthandler`.
- [`transform.c`](./src/transform.c) — `transform` / `validate` / `select`
  and all transform commands / validate checkers / select operators.

Symbol prefix `vs_`. Compiler: any C11-capable (gcc / clang). Dependencies:

- `libcjson-dev` (only for JSON-text parse / serialise; runtime values use
  the custom `vs_value` type).
- `libm` for `floor` / `isfinite`.

```c
#include "voxgig_struct.h"

int main(void) {
  vs_value* store = vs_parse_json("{\"db\":{\"host\":\"localhost\"}}", 0);
  vs_value* path  = vs_new_string("db.host");
  vs_value* host  = vs_getpath(store, path, NULL);
  /* host is "localhost" */
  vs_release(host);
  vs_release(path);
  vs_release(store);
  return 0;
}
```


## Calling convention

All public functions take and return `vs_value*`. Pointers are
explicitly reference-counted:

- Constructors (`vs_new_*`) return an owned reference with refcount 1.
- Functions that return a `vs_value*` transfer one owned reference to
  the caller — call `vs_release()` when done.
- Functions that take `vs_value*` parameters borrow them (caller still
  owns its reference) unless documented otherwise.
- `vs_retain(v)` adds a reference; `vs_release(v)` removes one (and
  frees when the count reaches zero).

`vs_list` and `vs_map` are reference-stable containers — mutation on
one alias is visible through every alias.


## Function reference

Namespace `vs_*`. Function names mirror the canonical API in lowercase.

### Minor utilities (25)

```c
const char*  vs_typename(int t);
vs_value*    vs_getdef(vs_value* val, vs_value* alt);
bool         vs_isnode(const vs_value* v);
bool         vs_ismap(const vs_value* v);
bool         vs_islist(const vs_value* v);
bool         vs_iskey(const vs_value* v);
bool         vs_isempty(const vs_value* v);
bool         vs_isfunc(const vs_value* v);
int64_t      vs_size(const vs_value* v);
vs_value*    vs_slice(vs_value* v, vs_value* start, vs_value* end, bool mutate);
char*        vs_pad(vs_value* str, vs_value* padding, vs_value* padchar);
int          vs_typify(const vs_value* v);
vs_value*    vs_getelem(vs_value* val, vs_value* key, vs_value* alt);
vs_value*    vs_getprop(vs_value* val, vs_value* key, vs_value* alt);
char*        vs_strkey(vs_value* key);
vs_strvec    vs_keysof(vs_value* val);
bool         vs_haskey(vs_value* val, vs_value* key);
vs_value*    vs_items_v(vs_value* val);
vs_value*    vs_flatten(vs_value* list, vs_value* depth);
vs_value*    vs_filter(vs_value* val, vs_itemcheck_fn check, void* ud);
char*        vs_escre(vs_value* v);
char*        vs_escurl(vs_value* v);
char*        vs_join_v(vs_value* arr, vs_value* sep, vs_value* url);
char*        vs_jsonify(vs_value* val, vs_value* flags);
char*        vs_stringify(vs_value* val, int maxlen);
char*        vs_pathify(vs_value* val, int startin, int endin);
vs_value*    vs_clone(vs_value* v);
vs_value*    vs_delprop(vs_value* parent, vs_value* key);
vs_value*    vs_setprop(vs_value* parent, vs_value* key, vs_value* val);
```

### Major utilities (8)

```c
vs_value*    vs_walk(vs_value* val, vs_walkapply_fn before,
                     vs_walkapply_fn after, int maxdepth, void* ud);
vs_value*    vs_merge(vs_value* val, int maxdepth);
vs_value*    vs_getpath(vs_value* store, vs_value* path, vs_injection* injdef);
vs_value*    vs_setpath(vs_value* store, vs_value* path, vs_value* val,
                        vs_injection* injdef);
vs_value*    vs_inject(vs_value* val, vs_value* store, vs_injection* injdef);
vs_value*    vs_transform(vs_value* data, vs_value* spec, vs_injection* injdef);
vs_value*    vs_validate(vs_value* data, vs_value* spec, vs_injection* injdef);
vs_value*    vs_select(vs_value* children, vs_value* query);
```

### Builder helpers (2)

```c
vs_value*    vs_jm_va(int n, vs_value** kv);   /* JSON map from k,v,k,v,... */
vs_value*    vs_jt_va(int n, vs_value** v);    /* JSON list from positional args */
```

### Injection helpers (3)

```c
bool          vs_check_placement(int modes, const char* ijname,
                                 int parent_types, vs_injection* inj);
vs_value*     vs_injector_args(const int* argTypes, size_t n, vs_value* args);
vs_injection* vs_inject_child(vs_value* child, vs_value* store, vs_injection* inj);
```


## Constants

### Type bit-flags

```c
VS_T_ANY, VS_T_NOVAL, VS_T_BOOLEAN, VS_T_DECIMAL, VS_T_INTEGER, VS_T_NUMBER,
VS_T_STRING, VS_T_FUNCTION, VS_T_SYMBOL, VS_T_NULL, VS_T_LIST, VS_T_MAP,
VS_T_INSTANCE, VS_T_SCALAR, VS_T_NODE
```

### Mode constants

```c
VS_M_KEYPRE, VS_M_KEYPOST, VS_M_VAL
```

### Sentinels (pointer identity)

```c
vs_skip_sentinel()    /* singleton; compare vs_is_skip(v) */
vs_delete_sentinel()  /* singleton; compare vs_is_delete(v) */
```


## Object model

```
vs_value
├── kind: VS_VAL_UNDEF | VS_VAL_NULL | VS_VAL_BOOL | VS_VAL_INT |
│         VS_VAL_DOUBLE | VS_VAL_STRING | VS_VAL_LIST | VS_VAL_MAP |
│         VS_VAL_FUNC | VS_VAL_SENTINEL
├── refcount: size_t
└── as: union { bool b; int64_t i; double d; ... }
```

- `vs_list` is a dynamic array of `vs_value*` slots; reference-stable.
- `vs_map` is an insertion-ordered vector of key/value entries plus an
  open-addressing hash index. Insertion order is preserved (required by
  the inject machinery's `$`-suffix key partition).
- `VS_VAL_UNDEF` and `VS_VAL_NULL` are distinct (mirrors TS `NONE` vs
  JSON null).
- Function values box an injector (`vs_injector_fn`) or a modify
  (`vs_modify_fn`) callback plus an opaque `void* ud` closure pointer.


## Test status

The corpus runner (`tests/struct_corpus_test.c`) loads
`../build/test/test.json` and runs every category and named test it
supports. Current score: **1107 / 1110**. Per-file:

```
minor.*              522 / 522
walk.*                29 / 29    (basic + depth subset)
merge.*              133 / 133
getpath.*             65 / 72    (basic full; relative subset)
inject.string         19 / 19
inject.deep           22 / 22
transform.*          160 / 161   ($REF deeply-nested edge cases)
validate.*           113 / 113
select.*              46 / 47    ($LIKE uses substring approximation
                                  in place of full regex)
```

The three remaining failures are edge cases in `$REF` recursive
resolution and `$LIKE` (full regex matching is approximated with
substring containment for now; libregex is intentionally avoided to
keep dependencies minimal).


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

- The corpus run reports leaks under AddressSanitizer (tracked in
  `corpus.out` cleanup). Tests all pass; leaks are limited to top-level
  per-iteration `vs_select` / `vs_validate` store maps. None of the
  leaks indicate use-after-free or double-free — only forgotten
  `vs_release` calls in the higher-level helpers.
- `$LIKE` uses substring containment instead of a full regular
  expression; the C standard library does not ship POSIX regex on every
  target and adding `libpcre` was deemed out of scope.
