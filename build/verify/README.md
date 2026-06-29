# Published-artifact verification harness

This harness proves that the **published** artifact for each port actually
installs/builds and works. It is deliberately separate from the in-repo
corpus tests: those test the source tree, this tests what a real user
downloads.

## What it does

There are two kinds of port:

- **Registry ports** (`go`, `typescript`, `javascript`, `python`, `ruby`,
  `rust`) — the published artifact is a package in a public registry (npm,
  Go modules, RubyGems, PyPI, crates.io). The target installs the latest
  published package from that registry.
- **Tag-only ports** (`php`, `zig`, `c`, `cpp`, `swift`) — there is **no
  package registry**: the published artifact *is* the git tag
  `<lang>/v<ver>`. The target reads the port's version from the repo,
  downloads the GitHub **source tarball at that tag**
  (`.../archive/refs/tags/<lang>/v<ver>.tar.gz`) into a fresh, gitignored
  `<lang>/.build/` temp dir, and builds the smoke client **against that
  downloaded (vendored) source — never the working tree**. This verifies
  that the source a user gets by checking out the published tag actually
  builds and works.

For every port it then:

1. Obtains the **published** artifact (registry install, or tagged-source
   download + build per the two kinds above).
2. Runs a tiny smoke client that performs one universal check:

   ```
   store = { db: { host: "localhost" } }
   getpath(store, "db.host") == "localhost"
   ```

   On success it prints `OK <port>: getpath(db.host) = localhost` and exits
   0; otherwise it prints `FAIL ...` and exits non-zero.

## Usage

```bash
make -C build/verify verify          # run all ports, print a summary
make -C build/verify verify-go       # one port at a time
make -C build/verify verify-typescript
make -C build/verify verify-ruby
make -C build/verify verify-python
make -C build/verify verify-php      # tag-only: download+build the tagged source
make -C build/verify verify-c
make -C build/verify verify-cpp
make -C build/verify verify-swift
make -C build/verify verify-zig
make -C build/verify clean           # remove installed artifacts + .build/ temp dirs
```

`make verify` runs every port, **continues past failures**, and prints a
`PASSED:` / `FAILED:` summary, exiting non-zero if any port failed.

### Ruby on older systems

The published `voxgig_struct` gem requires Ruby >= 2.7. If your default
`/usr/bin/ruby` is older (e.g. macOS system Ruby 2.6), point the harness at
a newer interpreter:

```bash
make -C build/verify verify-ruby \
  RUBY=/opt/homebrew/opt/ruby/bin/ruby \
  GEM=/opt/homebrew/opt/ruby/bin/gem
```

## Per-port layout

| Folder        | Registry package                        | Public API used                              |
|---------------|-----------------------------------------|----------------------------------------------|
| `go/`         | `github.com/voxgig/struct/go`           | `voxgigstruct.GetPath(store, "db.host")`     |
| `typescript/` | `@voxgig/struct` (npm, CommonJS)        | `require('@voxgig/struct').getpath(...)`     |
| `javascript/` | `@voxgig/structjs` (npm)                | `require('@voxgig/structjs').getpath(...)`   |
| `ruby/`       | `voxgig_struct` (RubyGems)              | `VoxgigStruct.getpath(store, "db.host")`     |
| `python/`     | `voxgig-struct` (PyPI)                  | `from voxgig_struct import getpath`          |
| `rust/`       | `voxgig-struct` (crates.io)             | `voxgig_struct::get_path(&store, ...)`       |
| `php/`        | git tag `php/v<ver>` (vendored source)  | `Voxgig\Struct\Struct::getpath($store, ...)` |
| `c/`          | git tag `c/v<ver>` (vendored source)    | `voxgig_getpath(store, path, NULL)`          |
| `cpp/`        | git tag `cpp/v<ver>` (vendored source)  | `voxgig::structlib::getpath_v(store, ...)`   |
| `swift/`      | git tag `swift/v<ver>` (vendored source)| `getpath(store, .string("db.host"))`         |
| `zig/`        | git tag `zig/v<ver>` (vendored source)  | `getpath(allocator, path, store)`            |

The tag-only ports read their version from `php/VERSION`, `c/VERSION`,
`cpp/VERSION`, `swift/VERSION`, and `zig/build.zig.zon` respectively.

## Publication status

`@voxgig/structjs` (JavaScript) and `voxgig-struct` (Rust / crates.io) are
**not published yet**, so `verify-javascript` and `verify-rust` are expected
to fail at the install step until they are. The scaffolding is in place so
they work the moment those packages ship.

## Toolchains required

`go`, `node`/`npm`, `ruby`/`gem`, `uv` (Python), `cargo` for the registry
ports; `php`, `cc`, `g++`, `swiftc`, and `zig` for the tag-only ports.
Override any of them on the command line, e.g.
`make verify-zig ZIG=$HOME/.local/zig/0.13.0/zig` or
`make verify-php PHP=/opt/homebrew/bin/php`. A missing toolchain makes the
target fail loudly rather than silently passing.

> **macOS note:** `verify-zig` requires a Zig toolchain that can link
> against the host's macOS SDK. Zig 0.13.0 (the version the port pins)
> cannot link `libSystem` on recent macOS SDKs — the same limitation breaks
> the zig port's own `zig build test` there — so `verify-zig` will fail at
> the final link step on those systems. The download + compile-from-tag
> steps still run; only the host link is affected.
