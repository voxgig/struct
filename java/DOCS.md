# Struct for Java

> Java port of the canonical TypeScript implementation.
> **Status: partial.**  Basic utilities are present; major
> subsystems (`inject`, `transform`, `validate`, `select`) are not
> yet implemented.  Use the canonical TS or one of the complete ports
> for production work.

For the language-neutral overview, motivation, and concepts, see the
[top-level README](../README.md).  For the parity matrix see
[`../REPORT.md`](../REPORT.md).

These docs follow the [Diataxis](https://diataxis.fr/) framework.


## Tutorial: your first lookup

### Install

Inside the monorepo:

```bash
cd java
mvn package        # or `make build`
```

Group / artifact: `voxgig:struct`.  Single class:
`voxgig.struct.Struct`.

### A first lookup

```java
import voxgig.struct.Struct;
import java.util.Map;

Map<String, Object> store = Map.of(
    "db", Map.of("host", "localhost", "port", 5432)
);

Object host = Struct.getProp(
    Struct.getProp(store, "db"),
    "host"
);
// host == "localhost"
```

`Struct.getPath` and `Struct.setPath` are not yet implemented; once
they land, the canonical pattern will be:

```java
Object host = Struct.getPath("db.host", store);
```


## How-to recipes (current scope)

The currently-implemented functions are:

```
typify, typename, isFunc, isNode, isMap, isList, isEmpty, isKey,
getProp, setProp, hasKey, keysof, items, pathify, stringify,
escapeRegex, escapeUrl, joinUrl,
clone, walk
```

### Test value shapes

```java
Struct.isNode(value);
Struct.isMap(value);
Struct.isList(value);
```

### Read / write a single property

```java
Object v = Struct.getProp(node, "key");
Struct.setProp(node, "key", value);
```

### Walk a tree (post-order only, currently)

```java
Struct.walk(tree, (key, val, parent, path) ->
    val == null ? "DEFAULT" : val);
```

The canonical `walk` supports `before` and `after` callbacks and a
`maxdepth`; the Java port currently does post-order only.

### Clone

```java
Object copy = Struct.clone(value);
```


## Reference

Source: [`src/Struct.java`](./src/Struct.java).  Package
`voxgig.struct`.

### Constants

All 15 type bit-flags are present:

```java
Struct.T_any, Struct.T_noval, Struct.T_boolean, Struct.T_decimal,
Struct.T_integer, Struct.T_number, Struct.T_string,
Struct.T_function, Struct.T_symbol, Struct.T_null,
Struct.T_list, Struct.T_map, Struct.T_instance,
Struct.T_scalar, Struct.T_node
```

Sentinels (`SKIP`, `DELETE`) and mode constants
(`M_KEYPRE`/`M_KEYPOST`/`M_VAL`) are not yet defined.

### Naming convention

Java uses camelCase for methods:

| Canonical    | Java          |
|--------------|---------------|
| `getprop`    | `getProp`     |
| `setprop`    | `setProp`     |
| `isnode`     | `isNode`      |
| `keysof`     | `keysof`      |
| `escre`      | `escapeRegex` |
| `escurl`     | `escapeUrl`   |

### Tests

```bash
cd java
make test
```

The test runner is minimal -- there is no standard JUnit
configuration in the build environment yet.  See
[`../REPORT.md`](../REPORT.md) for full status.


## Explanation

### Why partial?

The Java port currently covers the minor utilities and the basic
`walk`.  The major subsystems (`inject`, `transform`, `validate`,
`select`) need:

1. `getpath` / `setpath` as the foundation;
2. an `Injection` class to carry walk state;
3. the `SKIP` / `DELETE` sentinels;
4. transform-command and validate-checker dispatch tables.

These are listed as P0/P1 items in [`../REPORT.md`](../REPORT.md).

### Known issues

- `keysof()` returns a list of zeros for `List` inputs instead of
  string indices.
- `walk()` is post-order only.
- `escapeRegex()` uses `Pattern.quote()` wrapping rather than
  per-character escaping; output differs from the canonical.
- `stringify()` format diverges from canonical.

These are tracked in [`../REPORT.md`](../REPORT.md).

### `null` conventions

Java has only `null`.  As in Go, `null` covers both JSON null and
"absent".  Once the validate and transform subsystems land, they will
use the same `__NULL__` test sentinel as other ports.

### Object model

The port uses `LinkedHashMap<String,Object>` for maps and
`ArrayList<Object>` for lists by default.  Both are
reference-stable, so the canonical "lists are mutable in place"
property holds without a wrapper.


## Build and test

```bash
cd java
mvn package
make test
```

Tests live in [`src/test/`](./src/test/).
