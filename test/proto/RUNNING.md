# Running the prototype smokes

Every port ships a `smoke` that prints the canonical summary and must show:

```
functions: minor, getpath, inject, merge, transform, walk, validate, select, sentinels
total entries: 1325
expect kinds: value=1181, absent=84, match=1, error=59   (some ports print sorted: absent,error,match,value)
input kinds: in=1325
getpath/basic[0]: id=getpath/basic#deep, doc=true, input.kind=in, expect.kind=value, expect.value=42
```

All 22 were verified with the commands below (run from the repo root unless noted).
This is a **prototype** — these are run by hand, not in CI.

## Corpus-path convention

Each provider defaults to `build/test/test.json`. Two resolution styles are in use:

* **source-relative** (resolves from the provider file, run from anywhere):
  ts, javascript, python, php, ruby, perl, go, rust, dart, elixir, lua, swift.
* **cwd-relative** (run the binary from the repo root): c, cpp, java, kotlin,
  scala, csharp, zig, ocaml, clojure.

## Per-language commands

| Port | Command |
|------|---------|
| typescript | `node --experimental-strip-types test/proto/ts/smoke.ts` |
| javascript | `node test/proto/javascript/smoke.js` |
| python | `python3 test/proto/python/smoke.py` |
| ruby | `ruby test/proto/ruby/smoke.rb` |
| php | `php test/proto/php/smoke.php` |
| perl | `perl -I test/proto/perl test/proto/perl/smoke.pl` |
| lua | `lua5.4 test/proto/lua/smoke.lua` |
| elixir | `elixir test/proto/elixir/smoke.exs` |
| go | `cd test/proto/go && go run ./cmd/smoke` |
| rust | `cd test/proto/rust && cargo run --example smoke` |
| c | `gcc -std=c11 -O2 test/proto/c/smoke.c -o /tmp/c_smoke -lm && /tmp/c_smoke` |
| cpp | `g++ -std=c++17 -O2 test/proto/cpp/smoke.cpp -o /tmp/cpp_smoke && /tmp/cpp_smoke` |
| java | `cd test/proto/java && javac *.java && cd - && java -cp test/proto/java Smoke` |
| csharp | `cd test/proto/csharp && dotnet run` |
| zig | `cd test/proto/zig && zig run smoke.zig` |
| dart | `dart run test/proto/dart/smoke.dart` |
| haskell | `cd test/proto/haskell && runghc Smoke.hs` |
| ocaml | `cd test/proto/ocaml && ocamlc -o /tmp/ocaml_smoke provider.ml smoke.ml && cd - && /tmp/ocaml_smoke` |
| kotlin | `cd test/proto/kotlin && kotlinc Provider.kt Smoke.kt -include-runtime -d /tmp/kt.jar && cd - && java -jar /tmp/kt.jar` |
| scala | `cd test/proto/scala && scalac -d /tmp/scala_out Provider.scala Smoke.scala && cd - && java -cp "/tmp/scala_out:$SCALA3_LIB/*" Smoke` |
| swift | `cd test/proto/swift && swiftc Provider.swift main.swift -o /tmp/swift_smoke && /tmp/swift_smoke` |
| clojure | see note below |

### Toolchain versions used to verify

node 22 · python 3.11 · go 1.24 · rustc 1.94 · php 8.3 · ruby 3 · perl 5 ·
gcc/g++ 13 · openjdk 21 · dotnet 8 · zig 0.13.0 · dart 3.12 · kotlin 2.1 ·
scala 3.5.2 · lua 5.4 · ocaml 4.14 · ghc 9.4 · elixir 1.14 · clojure 1.12 ·
swift 6.0.3. (`$SCALA3_LIB` = the Scala 3 dist `lib/` dir.)

### Known prototype packaging nits (do not affect the 1325 result)

* **swift** — top-level smoke code must live in `main.swift` (Swift compiles
  top-level statements only there), hence the filename. Compile from the
  `swift/` dir so `#filePath` resolves the corpus.
* **clojure** — `provider.clj` declares ns `voxgig.proto.provider` (two path
  segments) but `default-test-file` walks three dirs up (it assumes the file is
  at `test/proto/clojure/`). Loading it by namespace from a staged classpath
  where the file sits at `voxgig/proto/` therefore mis-resolves the corpus path.
  Verified run (from a staged layout, with `/tmp/build -> <repo>/build`):

  ```
  mkdir -p /tmp/cljroot/voxgig/proto
  cp test/proto/clojure/{provider,smoke}.clj /tmp/cljroot/voxgig/proto/
  ln -sfn "$PWD/build" /tmp/build
  cd /tmp/cljroot && clojure -Sdeps '{:paths ["."]}' -M -m voxgig.proto.smoke
  ```

  A cleaner fix (left for later): make `default-test-file` search upward for a
  `build/test/test.json` rather than assuming a fixed depth.
