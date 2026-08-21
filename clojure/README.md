# @voxgig/struct — Clojure

A Clojure port of [`voxgig/struct`](../README.md): one small, fixed API for
manipulating JSON-shaped data — lookups, deep merge, by-example transform,
by-example validate, tree walk, path get/set, selection — that returns the
**same answer** as the canonical TypeScript implementation and every other
port. The behavioural contract is the shared JSON corpus in
[`build/test/`](../build/test); this port passes it in full.

## Status

Complete. Every canonical public function is implemented and the shared corpus
passes in full (`make test`) on [voxgig/omni](https://github.com/voxgig/omni),
the shared test runner — 1358 entries in 72 groups, plus the two `check`
entries and three single entries that are not part of any set. Zero
third-party runtime dependencies, and omni is a test-time classpath entry the
published jar never names.

## Requirements

- A JDK (Java 11+).
- The [Clojure CLI](https://clojure.org/guides/install_clojure)
  (`clojure` / `clj`).
- For the tests only: a [voxgig/omni](https://github.com/voxgig/omni)
  checkout, found via `$OMNI_HOME` or beside this repository.

## Use

The library lives in the `voxgig.struct` namespace:

```clojure
(require '[voxgig.struct :as s])

;; Build nodes with the mutable Java collections the library operates on.
(def store
  (doto (java.util.LinkedHashMap.)
    (.put "a" (doto (java.util.LinkedHashMap.) (.put "b" 2)))))

(s/getpath store "a.b")                 ;=> 2
(s/stringify (s/transform
               (doto (java.util.LinkedHashMap.) (.put "a" 1))
               (doto (java.util.LinkedHashMap.) (.put "x" "`a`"))))  ;=> "{x:1}"
```

`jm` / `jt` are convenient JSON-object / JSON-array builders:

```clojure
(s/jsonify (s/jm "a" 1 "b" (s/jt 2 3)))
```

### Data model

Nodes are mutable Java collections so the library's in-place, reference-stable
algorithms work exactly as in the canonical TypeScript:

- maps → `java.util.LinkedHashMap` (insertion-ordered),
- lists → `java.util.ArrayList`,
- `nil` plays the role of both `undefined` and JSON `null` (the Group A/B
  rules recover the distinction — see
  [`design/UNDEF_SPEC.md`](../design/UNDEF_SPEC.md)).

## API

The public surface matches the canonical export list, in lower-smushed names:

`clone delprop escre escurl filter flatten getdef getelem getpath getprop
haskey inject isempty isfunc iskey islist ismap isnode items join jsonify
keysof merge pad pathify select setpath setprop size slice strkey stringify
transform typify typename validate walk re_compile re_find re_find_all
re_replace re_test re_escape jm jt checkPlacement injectorArgs injectChild`

See [`DOCS.md`](./DOCS.md) for the full guide and
[the language-neutral docs](../DOCS.md) for concepts and examples.

## Develop

```
make test     # run the shared corpus on voxgig/omni (needs $OMNI_HOME)
make lint     # compile the namespaces
make inspect  # toolchain versions
```

## License

MIT. See [`../LICENSE`](../LICENSE).
