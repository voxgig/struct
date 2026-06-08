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

Every value is a `vs_value*` — a reference-counted tagged union. You build
values with `vs_new_*` / `vs_parse_json`, pass them to the `vs_`-prefixed
API, and release what you own with `vs_release`:

```c
#include "voxgig_struct.h"
#include <stdlib.h>

int main(void) {
  vs_value* store = vs_parse_json("{\"db\":{\"host\":\"localhost\",\"port\":5432}}", 0);
  vs_value* path  = vs_new_string("db.host");
  vs_value* host  = vs_getpath(store, path, NULL);   /* owned: "localhost" */

  /* ... use host ... */

  vs_release(host);    /* free what vs_getpath returned */
  vs_release(path);
  vs_release(store);
  return 0;
}
```

The third `vs_getpath` argument is an optional `vs_injection*` (relative-path
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
vs_value* data = vs_parse_json("{\"user\":{\"first\":\"Ada\",\"last\":\"Lovelace\"},\"age\":36}", 0);
vs_value* spec = vs_parse_json("{\"name\":\"`user.first`\",\"surname\":\"`user.last`\",\"years\":\"`age`\"}", 0);
vs_value* out  = vs_transform(data, spec, NULL);
char* js = vs_jsonify(out, NULL);    /* {"name": "Ada","surname": "Lovelace","years": 36} */
free(js);                            /* jsonify returns a malloc'd char* */
vs_release(out); vs_release(spec); vs_release(data);

/* Validate by example — leaves are type checkers. */
vs_value* vspec = vs_parse_json("{\"name\":\"`$STRING`\",\"age\":\"`$INTEGER`\"}", 0);
vs_value* ok = vs_validate(data2, vspec, NULL);  /* returns data on success */

/* Select children by query — each match tagged with its $KEY. */
vs_value* q  = vs_parse_json("{\"age\":30}", 0);
vs_value* hits = vs_select(children, q);          /* a new list */
```

`vs_walk` and `vs_filter` take C **function pointers** rather than spec
data — see the how-to guides below.

---

## 2. How-to guides

### Read a deep value, with a fallback
```c
vs_value* v = vs_getprop(node, key, alt);  /* returns a retained copy of alt if key absent */
vs_value* d = vs_getdef(maybe, alt);       /* alt only when maybe is undefined */
```
`vs_getprop`/`vs_getdef` return an **owned** reference (when they fall back
to `alt`, they retain it for you) — `vs_release` the result.

### Walk the tree, replacing values on ascent
`vs_walk` takes `before` / `after` C callbacks of type `vs_walkapply_fn`;
pass `NULL` for either phase. Each callback returns the (possibly new) value
for that slot:
```c
static vs_value* deflt_null(vs_value* key, vs_value* val,
                            vs_value* parent, vs_value* path, void* ud) {
  return vs_is_null(val) ? vs_new_string("DEFAULT") : vs_retain(val);
}
vs_value* result = vs_walk(tree, NULL, deflt_null, VS_MAXDEPTH, ud);
```
The `path` argument is a `vs_value` string-list; `ud` is your opaque
closure pointer (C has no captures).

### Filter entries with a predicate
```c
static bool keep_nonempty(vs_value* pair, void* ud) {
  vs_value* one = vs_new_int(1);                 /* element 1 of the [key, val] pair */
  vs_value* val = vs_getprop(pair, one, NULL);   /* owned */
  bool keep = !vs_isempty(val);
  vs_release(val); vs_release(one);
  return keep;
}
vs_value* kept = vs_filter(node, keep_nonempty, NULL);
```
`vs_filter` calls `vs_itemcheck_fn` on each `[key, val]` pair value; `ud` is
your opaque closure pointer.

### Run your own function during a transform (`$APPLY`)
Register a callable `vs_value` (built with `vs_new_injector`) in the
transform's `extra`, and reference it by name in the spec. A custom
function may return the `SKIP` / `DELETE` sentinels (see below) to
omit/remove the current key. The callback signature
(`vs_injector_fn` / `vs_modify_fn`) is C-specific and covered by the
port's unit tests, not the JSON corpus — see [`../NOTES.md`](../NOTES.md).

### Collect all validation errors instead of aborting
`vs_validate` returns the data on success. To gather errors rather than
fail, supply an `errs` collector via the `vs_injection*` argument (the
`errs` field on the injection state) — the canonical "collect errs"
behaviour from [`../DOCS.md`](../DOCS.md#2-how-to-guides).

### Serialise
```c
char* j  = vs_jsonify(value, NULL);              /* compact, insertion-ordered keys */
char* jp = vs_jsonify(value, vs_new_int(2));     /* pretty, 2-space indent */
char* s  = vs_stringify(value, 40);              /* truncated human form, for logs */
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

- **Two return disciplines.** Functions returning `vs_value*` give you an
  **owned** reference — release with `vs_release`. Functions returning
  `char*` (`vs_jsonify`, `vs_stringify`, `vs_pathify`, `vs_strkey`,
  `vs_pad`, `vs_escre`, `vs_escurl`, `vs_join_v`) give you a **malloc'd**
  string — release with `free`. `vs_keysof` returns a `vs_strvec` you free
  with `vs_strvec_free`.
- **`getprop` vs `getelem`.** Both are Group A (a stored `null` reads as
  absent). `vs_getelem` is list-specific, supports `-1`-from-the-end
  indexing, and *invokes* a callable `alt`; `vs_getprop`/`vs_getdef` do not.
- **`items` is `vs_items_v`** — it returns a `vs_value` list of `[key, val]`
  pair lists (owned). The C name carries a `_v` suffix because the value is
  boxed.
- **`vs_lookup` is the Group B raw read.** It is the internal literal
  lookup that preserves a stored `null`; the public readers
  (`vs_getprop`/`vs_getelem`/`vs_haskey`) are Group A. Its result is
  **borrowed** from the container (not retained) — `vs_retain` it if it must
  outlive the parent.
- **Type flags** combine bitwise: `vs_typify` of a string is
  `VS_T_SCALAR | VS_T_STRING`; test with `0 < (VS_T_STRING & t)`.
  `vs_typify(undefined)` is `VS_T_NOVAL` (not a scalar);
  `vs_typify(null)` is `VS_T_SCALAR | VS_T_NULL`. Mode constants are
  `VS_M_KEYPRE` / `VS_M_KEYPOST` / `VS_M_VAL`.

---

## 4. Explanation & port specifics

### Memory ownership — the thing to get right in C

Every `vs_value` carries an integer `refcount`. The model is documented at
the top of [`voxgig_struct.h`](./src/voxgig_struct.h) and holds uniformly:

- **Constructors** (`vs_new_*`) and **`vs_parse_json`** return a fresh value
  with refcount 1 — you own it.
- A function that **returns** a `vs_value*` transfers one owned reference to
  you. Always `vs_release` it when done (even on the `alt`/fallback path —
  the API retains `alt` before returning it).
- A function that **takes** `vs_value*` parameters **borrows** them: it does
  not consume your reference, and you still release it yourself.
- `vs_retain(v)` adds a reference; `vs_release(v)` removes one and frees the
  value (and its container) when the count hits zero.
- **Containers add a reference.** `vs_map_set` / `vs_list_push` (and the
  ordered-`Map` setters in [`value.h`](./src/value.h)) **take ownership** of
  the one reference you pass in — do not release it afterwards. Reads like
  `vs_map_get` / `vs_list_get` return a **borrowed** reference.

The header annotates each function (`/* borrowed */`, `/* takes
ownership */`, `/* owned by caller */`); when in doubt, read the annotation.
`make sanitize` (ASan/UBSan) and `make check_leak` (valgrind) exist
precisely to catch ownership mistakes.

### `null` versus absent ("Group A/B")

C distinguishes the two kinds in the value tag itself: `VS_VAL_UNDEF`
(absent) is a separate kind from `VS_VAL_NULL` (the JSON null scalar). This
mirrors TS `undefined` vs `null` and is the language-neutral
[Group A/B rule](../DOCS.md#null-versus-absent-group-ab):

- **Group A — readers** (`vs_getprop`, `vs_getelem`, `vs_haskey`,
  `vs_isempty`, `vs_isnode`): a stored `null` reads as *no value*.
- **Group B — value processors** (`vs_setprop`, `vs_clone`, `vs_walk`,
  `vs_merge`, `vs_inject`, `vs_transform`, `vs_validate`, `vs_select`, …):
  `null` is preserved literally.

Full text in [`../UNDEF_SPEC.md`](../UNDEF_SPEC.md). This is the single most
common source of port bugs.

### Reference-stable containers

`vs_list` and `vs_map` are reference-counted *containers*: aliasing one
`vs_value*` that wraps a list and mutating through it is visible through
every alias, exactly as JavaScript arrays/objects are shared by reference.
`walk`, `merge`, `inject`, and `setpath` rely on this. The `Map` is
insertion-ordered (keys held in a vector plus an open-addressing hash
index) because the inject machinery partitions keys by their `$`-suffix and
needs stable order — never swap in an unordered map.

### Regex

The canonical regex layer is the uniform six-function API. In C the
shared `re_*` names are exposed as `vs_re_compile` / `vs_re_test` /
`vs_re_find` / `vs_re_find_all` / `vs_re_replace` / `vs_re_escape` (with
`_re` variants taking an already-compiled `vs_regex*`); the lower-level
engine is `vs_regex_*` in [`regex.h`](./src/regex.h). It is an **in-tree
Thompson NFA** implementing the RE2 subset (literals, classes, anchors,
greedy/lazy quantifiers, groups, alternation; **no** backreferences or
lookaround). Two consequences:

- **Linear time, no catastrophic backtracking** — pathological inputs
  finish in microseconds. See
  [`../REGEX_PATHOLOGICAL.md`](../REGEX_PATHOLOGICAL.md).
- **Zero-width `re_replace` is ECMA-style**: `vs_re_replace("a*", "abc",
  "X")` returns `"XXbXcX"` (the convention shared with the other in-tree
  Thompson ports). Captures cap at `VS_REGEX_MAX_GROUPS` (16). Compiled
  regexes and the returned `char*`/`vs_strvec` are caller-owned — free them
  with `vs_regex_free` / `vs_strvec_free` / `free`.

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
[`../REPORT.md`](../REPORT.md)); per-test counts are written to
`corpus-scoreboard.json` after each run.

**To change behaviour:** this is a port, so behaviour changes start in the
canonical TypeScript, flow to the corpus, then to every port. To fix a C
bug, reproduce against the failing corpus case, compare `src/*.c` to the
canonical TS for that function, fix the **port** (never the corpus), then
`make test` green and `make lint`. The full cross-port checklist is in
[`../AGENTS.md`](../AGENTS.md); see also [`./AGENTS.md`](./AGENTS.md) for
port-specific agent notes.
