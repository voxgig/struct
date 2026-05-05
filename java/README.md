# Struct for Java

> Java port of the canonical TypeScript implementation.
>
> **Status: complete.**  Full TS-canonical parity: all 40 functions,
> 15 type bit-flags, 3 mode constants (`M_KEYPRE`/`M_KEYPOST`/`M_VAL`),
> `SKIP`/`DELETE` sentinel marker maps, and the `Injection` state
> machine. `inject()`/`transform()`/`validate()`/`select()` all dispatch
> through the canonical injector machinery: 11 transform commands
> (`$DELETE`/`$COPY`/`$KEY`/`$ANNO`/`$MERGE`/`$EACH`/`$PACK`/`$REF`/
> `$FORMAT`/`$APPLY`), 6 validate checkers (`$STRING`/`$TYPE`/`$ANY`/
> `$CHILD`/`$ONE`/`$EXACT`), and 4 select operators (`$AND`/`$OR`/
> `$NOT`/`$CMP`).
>
> Passes the full shared corpus (1178/1178). Run locally with
> `mvn test` from `java/`. Per-file pass counts are written to
> `target/corpus-scoreboard.json`; the committed baseline lives at
> `test-baseline.json`.

For motivation, language-neutral concepts, and the cross-language
parity matrix, see the [top-level README](../README.md) and
[REPORT.md](../REPORT.md).


## Install

In the monorepo:

```bash
cd java
mvn package        # or `make build`
```

Group / artifact: `voxgig:struct`.  Single class:
`voxgig.struct.Struct`.

```java
import voxgig.struct.Struct;
```


## Quick start

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

Once `getPath` is implemented, the canonical pattern will be:

```java
Object host = Struct.getPath(store, "db.host");
```


## Naming convention

Java uses camelCase for methods:

| Canonical    | Java          |
|--------------|---------------|
| `getprop`    | `getProp`     |
| `setprop`    | `setProp`     |
| `isnode`     | `isNode`      |
| `keysof`     | `keysof`      |
| `escre`      | `escapeRegex` |
| `escurl`     | `escapeUrl`   |


## Function reference (currently implemented)

Source: [`src/Struct.java`](./src/Struct.java).  Package
`voxgig.struct`.

22 of the 40 canonical functions are present:

### Predicates

```java
public static boolean isNode(Object val)
public static boolean isMap(Object val)
public static boolean isList(Object val)
public static boolean isKey(Object val)
public static boolean isEmpty(Object val)
public static boolean isFunc(Object val)
```

### Type inspection

```java
public static int    typify(Object val)
public static String typename(int t)
```

### Property access

```java
public static Object       getProp(Object val, Object key)
public static Object       setProp(Object parent, Object key, Object val)
public static boolean      hasKey(Object val, Object key)
public static List<String> keysof(Object val)         // BUG: see notes
public static List<Object[]> items(Object val)
```

### Tree operations

```java
public static Object clone(Object val)

public static Object walk(Object val, WalkApply apply)
public static Object walk(Object val, WalkApply apply, int maxdepth)

public interface WalkApply {
    Object apply(Object key, Object val, Object parent,
                 List<String> path);
}
```

### Strings / URL

```java
public static String stringify(Object val)
public static String escapeRegex(String s)
public static String escapeUrl(String s)
public static String joinUrl(List<Object> parts)
public static String pathify(Object val)
```


## Function reference (not yet implemented)

The following canonical functions are missing from the Java port.
Items marked **P0** must be implemented before the major subsystems
can land:

### Path operations (P0)

```java
public static Object getPath(Object store, Object path);
public static Object setPath(Object store, Object path, Object val);
```

### Major subsystems (P0)

```java
public static Object       inject(Object val, Object store);
public static Object       transform(Object data, Object spec);
public static Object       validate(Object data, Object spec);
public static List<Object> select(Object children, Object query);
```

### Minor utilities

```java
getDef, getElem, delProp, size, slice, flatten, filter,
pad, replace, join, jsonify, strKey, merge   // currently stubbed
```

### Builders

```java
jm, jt
```

### Injection helpers

```java
checkPlacement, injectorArgs, injectChild
```

### Sentinels and mode constants

```java
SKIP, DELETE
M_KEYPRE, M_KEYPOST, M_VAL, MODENAME
```

(Type bit-flags `T_any`..`T_node` are present.)


## Constants

### Type bit-flags

All 15 are present as `int` constants on `Struct`:

```java
Struct.T_any        Struct.T_noval     Struct.T_boolean
Struct.T_decimal    Struct.T_integer   Struct.T_number
Struct.T_string     Struct.T_function  Struct.T_symbol
Struct.T_null       Struct.T_list      Struct.T_map
Struct.T_instance   Struct.T_scalar    Struct.T_node
```


## Notes

### Why partial?

The Java port currently covers the predicates, type inspection, and
basic `walk`.  The major subsystems (`inject`, `transform`,
`validate`, `select`) need:

1. `getPath` / `setPath` as the foundation.
2. An `Injection` class to carry walk state.
3. `SKIP` / `DELETE` sentinels.
4. Transform-command and validate-checker dispatch tables.

These are listed as P0/P1 items in [`../REPORT.md`](../REPORT.md).

### Known issues

- **`keysof()` returns zeros for `List` inputs** instead of string
  indices.
- **`walk()` is post-order only**; no `before`/`after` callbacks or
  `maxdepth` control.
- **`escapeRegex()`** uses `Pattern.quote()` wrapping rather than
  per-character escaping; output diverges from canonical.
- **`stringify()`** format diverges from canonical.

### `null` conventions

Java has only `null`.  As in Go, `null` covers both JSON null and
"absent".  Once the validate/transform subsystems land they will
use the same `__NULL__` test sentinel as other ports.

### Object model

The port uses `LinkedHashMap<String,Object>` for maps and
`ArrayList<Object>` for lists by default.  Both are
reference-stable; the canonical "lists are mutable in place"
property holds without a wrapper.

### Test status

No standard test runner configured yet.  `StructTest.java` exists
but is minimal.


## Build and test

```bash
cd java
mvn package
make test
```

Tests live in [`src/test/`](./src/test/).
