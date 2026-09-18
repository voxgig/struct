# Implementation rationale

Null and absence semantics are classified by operation. Readers that collapse them and processors that preserve them must follow their respective contracts across languages.

Go uses a pointer-stable ListRef wrapper so aliases observe list growth and mutation. Rust uses ordered containers so traversal and transformation preserve observable key order. Replacing either representation with a convenient host container can break parity.

Sources: [Go guide](go/AGENTS.md), [Rust guide](rust/AGENTS.md), [agent guide](AGENTS.md).

The Aontu file under `design/` is a reference proposal, not a build input. Its schema-mark emission and optional-default behavior need verification before adoption. The executable shared corpus remains under `build/test/`.
