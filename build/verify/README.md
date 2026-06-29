# Published-artifact verification harness

This harness proves that the **published** packages for each port actually
install from their registries and work. It is deliberately separate from
the in-repo corpus tests: those test the source tree, this tests what a
real user downloads.

## What it does

For every port it:

1. Installs the **latest published** package from its public registry
   (npm, Go modules, RubyGems, PyPI, crates.io).
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
make -C build/verify clean           # remove installed artifacts
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

## Publication status

`@voxgig/structjs` (JavaScript) and `voxgig-struct` (Rust / crates.io) are
**not published yet**, so `verify-javascript` and `verify-rust` are expected
to fail at the install step until they are. The scaffolding is in place so
they work the moment those packages ship.

## Toolchains required

`go`, `node`/`npm`, `ruby`/`gem`, `uv` (Python), `cargo`.
