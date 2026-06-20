# @voxgig/struct — Scala

A Scala port of [`voxgig/struct`](../README.md): one small, fixed API for
manipulating JSON-shaped data — lookups, deep merge, by-example transform,
by-example validate, tree walk, path get/set, selection — that returns the
**same answer** as the canonical TypeScript implementation and every other
port. The behavioural contract is the shared JSON corpus in
[`build/test/`](../build/test); this port passes it in full.

## Status

Complete. Every canonical public function is implemented and the entire
shared corpus passes (`make test`). **Zero third-party dependencies** — only
the Scala 3 toolchain and a JDK are required.

## Requirements

- A JDK (Java 11+).
- The Scala 3 compiler (`scalac` / `scala`).

## Use

The library lives in the `voxgig.struct` object:

```scala
import voxgig.struct.*

val store = mkMap(Seq("a" -> mkMap(Seq("b" -> VNum(2.0)))))

println(stringify(getpath(store, VStr("a.b"))))            // 2
println(stringify(transform(
  mkMap(Seq("a" -> VNum(1.0))),
  mkMap(Seq("x" -> VStr("`a`"))))))                        // {x:1}
```

`jm` / `jt` are convenient JSON-object / JSON-array builders:

```scala
jsonify(jm(VStr("a"), VNum(1.0), VStr("b"), jt(VNum(2.0), VNum(3.0))))
```

### Data model

A single `Value` ADT represents JSON-shaped data:

```
Noval | VNull | VBool(Boolean) | VNum(Double) | VStr(String)
      | VList(ArrayBuffer[Value]) | VMap(LinkedHashMap[String, Value])
      | VFunc(Injector) | VSentinel(String)
```

`Noval` is the canonical `undefined` (absent); `VNull` is JSON null — distinct,
exactly as in the canonical TypeScript. Nodes (`VList` / `VMap`) are mutable and
reference-stable, so the library's in-place algorithms behave identically to
the reference implementation. See [`DOCS.md`](./DOCS.md) and
[the language-neutral docs](../DOCS.md).

## API

The public surface matches the canonical export list (lower-smushed /
camelCased): `clone delprop escre escurl filter flatten getdef getelem getpath
getprop haskey inject isempty isfunc iskey islist ismap isnode items join
jsonify keysof merge pad pathify select setpath setprop size slice strkey
stringify transform typify typename validate walk re_compile re_find
re_find_all re_replace re_test re_escape jm jt checkPlacement injectorArgs
injectChild`.

## Develop

```
make test     # run the shared corpus
make lint     # type-check the library
make inspect  # toolchain version
```

## License

MIT. See [`../LICENSE`](../LICENSE).
