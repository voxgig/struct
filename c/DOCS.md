# Struct for C — Comprehensive Guide

> A C11 port of the canonical TypeScript implementation. Behaviour is
> defined by TypeScript and pinned by the shared corpus; this port follows
> it in idiomatic C. This guide is the in-depth companion to
> [`README.md`](./README.md) (quick-start + signature reference) and the
> language-neutral [`../DOCS.md`](../DOCS.md).

Four parts, each with a different job:

- **[Tutorial](#1-tutorial)** — build it, write a first program, build up
  the API.
- **[How-to guides](#2-how-to-guides)** — recipes for specific tasks.
- **[Reference](#3-reference)** — signatures live in
  [`README.md`](./README.md#function-reference); this section adds the
  C-specific semantics (memory, casing, types).
- **[Explanation](#4-explanation--port-specifics)** — the model, memory
  ownership, and C-specific behaviour.

Then: [Build, test, extend](#build-test-and-extend).

---

## 1. Tutorial

### Build

There is nothing to install. The library is pure C11 (gcc or clang) with
**zero third-party runtime dependencies** — JSON text I/O is a vendored
recursive-descent parser in [`src/value_io.c`](./src/value_io.c), the
insertion-ordered `Map` lives in [`src/value.h`](./src/value.h), and the
regex engine is an in-tree RE2-subset Thompson NFA in
[`src/regex.c`](./src/regex.c). Only `libm` is linked (for `floor` /
`isfinite`).

```bash
cd c
make test        # compiles the corpus driver + runs it (no deps)
make smoke       # the 13-check API smoke test
```

To use it from your own code, compile `src/*.c` alongside your program and
include the umbrella header:

```c
#include "voxgig_struct.h"
```

### Your first program

Every value is a `voxgig_value*` — a reference-counted tagged union. You build
values with `voxgig_new_*` / `voxgig_parse_json`, pass them to the `voxgig_`-prefixed
API, and release what you own with `voxgig_release`:

```c
#include "voxgig_struct.h"
#include <stdlib.h>

int main(void) {
  voxgig_value* store = voxgig_parse_json("{\"db\":{\"host\":\"localhost\",\"port\":5432}}", 0);
  voxgig_value* path  = voxgig_new_string("db.host");
  voxgig_value* host  = voxgig_getpath(store, path, NULL);   /* owned: "localhost" */

  /* ... use host ... */

  voxgig_release(host);    /* free what voxgig_getpath returned */
  voxgig_release(path);
  voxgig_release(store);
  return 0;
}
```

The third `voxgig_getpath` argument is an optional `voxgig_injection*` (relative-path
state used inside transforms) — pass `NULL` for a plain lookup. The C API
follows one rule throughout: **optional TS arguments are passed as `NULL`**.

### Build up the rest of the API

Each call below has the same meaning in every port; only the spelling
changes. Read [`../DOCS.md`](../DOCS.md#1-tutorial-a-guided-tour) for the
full language-neutral walkthrough. Because specs are themselves
JSON-shaped data, the most convenient way to write them in C is to parse a
literal:

```c
/* Reshape by example — the spec mirrors the output you want. */
voxgig_value* data = voxgig_parse_json("{\"user\":{\"first\":\"Ada\",\"last\":\"Lovelace\"},\"age\":36}", 0);
voxgig_value* spec = voxgig_parse_json("{\"name\":\"`user.first`\",\"surname\":\"`user.last`\",\"years\":\"`age`\"}", 0);
voxgig_value* out  = voxgig_transform(data, spec, NULL);
char* js = voxgig_jsonify(out, NULL);    /* {"name": "Ada","surname": "Lovelace","years": 36} */
free(js);                            /* jsonify returns a malloc'd char* */
voxgig_release(out); voxgig_release(spec); voxgig_release(data);

/* Validate by example — leaves are type checkers. */
voxgig_value* vspec = voxgig_parse_json("{\"name\":\"`$STRING`\",\"age\":\"`$INTEGER`\"}", 0);
voxgig_value* ok = voxgig_validate(data2, vspec, NULL);  /* returns data on success */

/* Select children by query — each match tagged with its $KEY. */
voxgig_value* q  = voxgig_parse_json("{\"age\":30}", 0);
voxgig_value* hits = voxgig_select(children, q);          /* a new list */
```

`voxgig_walk` and `voxgig_filter` take C **function pointers** rather than spec
data — see the how-to guides below.

---

## 2. How-to guides

### Read a deep value, with a fallback
```c
voxgig_value* v = voxgig_getprop(node, key, alt);  /* returns a retained copy of alt if key absent */
voxgig_value* d = voxgig_getdef(maybe, alt);       /* alt only when maybe is undefined */
```
`voxgig_getprop`/`voxgig_getdef` return an **owned** reference (when they fall back
to `alt`, they retain it for you) — `voxgig_release` the result.

### Walk the tree, replacing values on ascent
`voxgig_walk` takes `before` / `after` C callbacks of type `voxgig_walkapply_fn`;
pass `NULL` for either phase. Each callback returns the (possibly new) value
for that slot:
```c
static voxgig_value* deflt_null(voxgig_value* key, voxgig_value* val,
                            voxgig_value* parent, voxgig_value* path, void* ud) {
  return voxgig_is_null(val) ? voxgig_new_string("DEFAULT") : voxgig_retain(val);
}
voxgig_value* result = voxgig_walk(tree, NULL, deflt_null, VOXGIG_MAXDEPTH, ud);
```
The `path` argument is a `voxgig_value` string-list; `ud` is your opaque
closure pointer (C has no captures).

### Filter entries with a predicate
```c
static bool keep_nonempty(voxgig_value* pair, void* ud) {
  voxgig_value* one = voxgig_new_int(1);                 /* element 1 of the [key, val] pair */
  voxgig_value* val = voxgig_getprop(pair, one, NULL);   /* owned */
  bool keep = !voxgig_isempty(val);
  voxgig_release(val); voxgig_release(one);
  return keep;
}
voxgig_value* kept = voxgig_filter(node, keep_nonempty, NULL);
```
`voxgig_filter` calls `voxgig_itemcheck_fn` on each `[key, val]` pair value; `ud` is
your opaque closure pointer.

### Run your own function during a transform (`$APPLY`)
Register a callable `voxgig_value` (built with `voxgig_new_injector`) in the
transform's `extra`, and reference it by name in the spec. A custom
function may return the `SKIP` / `DELETE` sentinels (see below) to
omit/remove the current key. The callback signature
(`voxgig_injector_fn` / `voxgig_modify_fn`) is C-specific and covered by the
port's unit tests, not the JSON corpus — see [`../NOTES.md`](../design/NOTES.md).

### Collect all validation errors instead of aborting
`voxgig_validate` returns the data on success. To gather errors rather than
fail, supply an `errs` collector via the `voxgig_injection*` argument (the
`errs` field on the injection state) — the canonical "collect errs"
behaviour from [`../DOCS.md`](../DOCS.md#2-how-to-guides).

### Serialise
```c
char* j  = voxgig_jsonify(value, NULL);              /* compact, insertion-ordered keys */
char* jp = voxgig_jsonify(value, voxgig_new_int(2));     /* pretty, 2-space indent */
char* s  = voxgig_stringify(value, 40);              /* truncated human form, for logs */
free(j); free(jp); free(s);                      /* all three are malloc'd */
```

For more task recipes (merge configs, `$EACH`, `$MERGE`, `$FORMAT`, `$ONE`,
`$EXACT`, …) see the language-neutral
[How-to guides](../DOCS.md#2-how-to-guides) — the spec syntax is identical;
only the host literals differ.

---

## 3. Reference

The full C signatures, grouped and with the constant lists, are in
[`README.md` → Function reference](./README.md#function-reference). The
canonical public surface is the `export { … }` block in
[`../typescript/src/StructUtility.ts`](../typescript/src/StructUtility.ts) —
that block *is* what [`../tools/check_parity.py`](../tools/check_parity.py)
checks this port against.

C-specific points the signatures don't show:

- **Two return disciplines.** Functions returning `voxgig_value*` give you an
  **owned** reference — release with `voxgig_release`. Functions returning
  `char*` (`voxgig_jsonify`, `voxgig_stringify`, `voxgig_pathify`, `voxgig_strkey`,
  `voxgig_pad`, `voxgig_escre`, `voxgig_escurl`, `voxgig_join_v`) give you a **malloc'd**
  string — release with `free`. `voxgig_keysof` returns a `voxgig_strvec` you free
  with `voxgig_strvec_free`.
- **`getprop` vs `getelem`.** Both are Group A (a stored `null` reads as
  absent). `voxgig_getelem` is list-specific, supports `-1`-from-the-end
  indexing, and *invokes* a callable `alt`; `voxgig_getprop`/`voxgig_getdef` do not.
- **`items` is `voxgig_items_v`** — it returns a `voxgig_value` list of `[key, val]`
  pair lists (owned). The C name carries a `_v` suffix because the value is
  boxed.
- **`voxgig_lookup` is the Group B raw read.** It is the internal literal
  lookup that preserves a stored `null`; the public readers
  (`voxgig_getprop`/`voxgig_getelem`/`voxgig_haskey`) are Group A. Its result is
  **borrowed** from the container (not retained) — `voxgig_retain` it if it must
  outlive the parent.
- **Type flags** combine bitwise: `voxgig_typify` of a string is
  `VOXGIG_T_SCALAR | VOXGIG_T_STRING`; test with `0 < (VOXGIG_T_STRING & t)`.
  `voxgig_typify(undefined)` is `VOXGIG_T_NOVAL` (not a scalar);
  `voxgig_typify(null)` is `VOXGIG_T_SCALAR | VOXGIG_T_NULL`. Mode constants are
  `VOXGIG_M_KEYPRE` / `VOXGIG_M_KEYPOST` / `VOXGIG_M_VAL`.

---

## 4. Explanation & port specifics

### Memory ownership — the thing to get right in C

Every `voxgig_value` carries an integer `refcount`. The model is documented at
the top of [`voxgig_struct.h`](./src/voxgig_struct.h) and holds uniformly:

- **Constructors** (`voxgig_new_*`) and **`voxgig_parse_json`** return a fresh value
  with refcount 1 — you own it.
- A function that **returns** a `voxgig_value*` transfers one owned reference to
  you. Always `voxgig_release` it when done (even on the `alt`/fallback path —
  the API retains `alt` before returning it).
- A function that **takes** `voxgig_value*` parameters **borrows** them: it does
  not consume your reference, and you still release it yourself.
- `voxgig_retain(v)` adds a reference; `voxgig_release(v)` removes one and frees the
  value (and its container) when the count hits zero.
- **Containers add a reference.** `voxgig_map_set` / `voxgig_list_push` (and the
  ordered-`Map` setters in [`value.h`](./src/value.h)) **take ownership** of
  the one reference you pass in — do not release it afterwards. Reads like
  `voxgig_map_get` / `voxgig_list_get` return a **borrowed** reference.

The header annotates each function (`/* borrowed */`, `/* takes
ownership */`, `/* owned by caller */`); when in doubt, read the annotation.
`make sanitize` (ASan/UBSan) and `make check_leak` (valgrind) exist
precisely to catch ownership mistakes.

### `null` versus absent ("Group A/B")

C distinguishes the two kinds in the value tag itself: `VOXGIG_VAL_UNDEF`
(absent) is a separate kind from `VOXGIG_VAL_NULL` (the JSON null scalar). This
mirrors TS `undefined` vs `null` and is the language-neutral
[Group A/B rule](../DOCS.md#null-versus-absent-group-ab):

- **Group A — readers** (`voxgig_getprop`, `voxgig_getelem`, `voxgig_haskey`,
  `voxgig_isempty`, `voxgig_isnode`): a stored `null` reads as *no value*.
- **Group B — value processors** (`voxgig_setprop`, `voxgig_clone`, `voxgig_walk`,
  `voxgig_merge`, `voxgig_inject`, `voxgig_transform`, `voxgig_validate`, `voxgig_select`, …):
  `null` is preserved literally.

Full text in [`../UNDEF_SPEC.md`](../design/UNDEF_SPEC.md). This is the single most
common source of port bugs.

### Reference-stable containers

`voxgig_list` and `voxgig_map` are reference-counted *containers*: aliasing one
`voxgig_value*` that wraps a list and mutating through it is visible through
every alias, exactly as JavaScript arrays/objects are shared by reference.
`walk`, `merge`, `inject`, and `setpath` rely on this. The `Map` is
insertion-ordered (keys held in a vector plus an open-addressing hash
index) because the inject machinery partitions keys by their `$`-suffix and
needs stable order — never swap in an unordered map.

### Regex

The canonical regex layer is the uniform six-function API. In C the
shared `re_*` names are exposed as `voxgig_re_compile` / `voxgig_re_test` /
`voxgig_re_find` / `voxgig_re_find_all` / `voxgig_re_replace` / `voxgig_re_escape` (with
`_re` variants taking an already-compiled `voxgig_regex*`); the lower-level
engine is `voxgig_regex_*` in [`regex.h`](./src/regex.h). It is an **in-tree
Thompson NFA** implementing the RE2 subset (literals, classes, anchors,
greedy/lazy quantifiers, groups, alternation; **no** backreferences or
lookaround). Two consequences:

- **Linear time, no catastrophic backtracking** — pathological inputs
  finish in microseconds. See
  [`../REGEX_PATHOLOGICAL.md`](../design/REGEX_PATHOLOGICAL.md).
- **Zero-width `re_replace` is ECMA-style**: `voxgig_re_replace("a*", "abc",
  "X")` returns `"XXbXcX"` (the convention shared with the other in-tree
  Thompson ports). Captures cap at `VOXGIG_REGEX_MAX_GROUPS` (16). Compiled
  regexes and the returned `char*`/`voxgig_strvec` are caller-owned — free them
  with `voxgig_regex_free` / `voxgig_strvec_free` / `free`.

---

## Build, test, and extend

```bash
cd c
make test        # compile + run the corpus driver (alias of make corpus)
make smoke       # 13-check API smoke test
make sanitize    # corpus driver under ASan + UBSan
make check_leak  # corpus driver under valgrind
make lint        # clang-format --dry-run + clang-tidy
make format      # apply clang-format in place
make clean       # remove built binaries / scoreboard
```

The corpus runner ([`tests/struct_corpus_test.c`](./tests/struct_corpus_test.c))
loads the shared corpus from [`../build/test/`](../build/test/) — the same
contract every port runs. This port passes the corpus (1177/1177 per
[`../REPORT.md`](../design/REPORT.md)); per-test counts are written to
`corpus-scoreboard.json` after each run.

**To change behaviour:** this is a port, so behaviour changes start in the
canonical TypeScript, flow to the corpus, then to every port. To fix a C
bug, reproduce against the failing corpus case, compare `src/*.c` to the
canonical TS for that function, fix the **port** (never the corpus), then
`make test` green and `make lint`. The full cross-port checklist is in
[`../AGENTS.md`](../AGENTS.md); see also [`./AGENTS.md`](./AGENTS.md) for
port-specific agent notes.
