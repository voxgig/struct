# Absent vs Null — Per-Language Native Semantics

> **Question.** Setting aside how the voxgig-struct ports model things,
> what does each host language *natively* provide for distinguishing
> "no value here" from "the value `null`"? This report probes the host
> language directly, in five different positions where the distinction
> can matter: variable, function parameter, map/dict key, list/array
> element, and struct/object field. (Plus a sixth: function return.)
>
> Every result below is from running the probes in `/tmp/undef/probe.*`
> against the locally-installed compilers / runtimes. Versions:
> Node 22.22 · Python 3.11 · Go 1.24 · Ruby 3.3 · PHP 8.4 · Lua 5.4 ·
> Rust 1.94 · Java 21 · C# / .NET 8 · g++ 13 · Kotlin 1.3 · Zig 0.13 ·
> gcc 13 · Perl 5.38 · Swift 5.10.

## How to read the table

Cell legend:

- ✅ **distinct** — the language has a first-class way to tell the two apart at this position.
- 🟡 **API-only** — the value type itself doesn't distinguish, but the API for *this position* has a separate "present?" / "exists?" check that lets you tell them apart.
- ❌ **indistinguishable** — at this position, the language cannot tell "absent" from "null/nil".
- ⊘ **no such concept** — the position doesn't exist as a separate idea in the language.

## Master table

| Position | typescript/javascript | python | go | ruby | php | lua | rust | java | csharp | cpp | kotlin | zig | c | perl | swift |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| **Variable (local)** — uninitialised vs `null`-assigned | ✅ `typeof === 'undefined'` vs `=== null` | 🟡 unbound name → `NameError`; assigned `None` → exists. No "uninitialised but defined". | 🟡 `var v T` gets zero value; for ref types that's `nil` — indistinguishable from explicit `nil`. | 🟡 `defined?(v)` returns `nil` for unbound, `"local-variable"` for assigned-`nil`. | 🟡 `isset($v)` = false for unset AND null; `array_key_exists('v', get_defined_vars())` distinguishes. | ❌ a Lua local is `nil` until assigned and `nil` after `= nil`; identical. | ✅ compile-time: must definitely-assign before use. `Option<T>` models absent. | ✅ compile-time: must definitely-assign locals. Fields default to `null` (ref) / 0 (val). | ✅ compile-time definite-assignment; nullable refs `T?` distinguishable via flow analysis. | ✅ types like `std::optional<T>` model absent distinctly; reading uninit primitive is UB. | ✅ `lateinit`/`by lazy` exist precisely for "declared but not yet set" distinct from null. | ✅ `?T` optionals: `null` is the empty case. | ⊘ uninitialised auto storage = UB; static = zero-init. No managed concept. | ❌ `my $v;` is `undef`, identical to `my $v = undef;`. `undef` is the only null-like value. | ✅ compile-time: a non-optional `let`/`var` must be assigned before use; `T?` (`Optional`) makes `nil` the explicit empty case, distinct from "not yet set". |
| **Function parameter** — omitted vs `null` passed | ✅ `arguments.length` / default `undefined` vs explicit `null` | ✅ default-sentinel idiom: `def f(x=SENT): if x is SENT` | ✅ variadic `...args` + `len(args)`. Non-variadic: arity is fixed. | ✅ default-sentinel idiom: `def p(x = SENT)` + `equal?(SENT)` | ✅ default param + `func_num_args()`; or `null` default + `array_key_exists` on `func_get_args()` | ✅ `select('#', ...)` returns true arg count in varargs | ✅ params are fixed-arity; `Option<Option<T>>` encodes "omitted" vs "stored null" | 🟡 only via overloads (different arities) — single signature can't tell omitted from null | ✅ optional params + `default`; or `[CallerArgumentExpression]`; sentinel works too | ✅ default args + `std::optional<T>` parameter | 🟡 default value + sentinel-object idiom; no built-in "was this defaulted?" check | ✅ params are fixed-arity; `??T` encodes "omitted" vs "stored null" | ⊘ no defaults, no varargs introspection beyond `va_list` count | ✅ all args land in `@_`; `scalar(@_)` is the true arg count, so omitted vs explicit `undef` is distinguishable | ✅ default-valued params (`x: T? = nil`) + `Optional<Optional<T>>` to encode "omitted" vs "passed nil"; arity is otherwise fixed |
| **Map / dict key** — absent vs `null`-valued | ✅ `'k' in m` vs `m[k] === undefined` vs `m[k] === null` | ✅ `'k' in m` vs `m.get(k, SENT) is SENT` | ✅ `v, ok := m[k]` (the comma-ok pattern) | ✅ `h.key?(k)` / `h.fetch(k, SENT)` | ✅ `array_key_exists($k, $a)` (NOT `isset`, which returns false for both) | ❌ **Lua tables cannot store `nil`** — assignment removes the key. "Absent" and "stored nil" are literally identical. | ✅ `m.contains_key(k)` / `.get(k)` returns `Option<&V>`; `Some(&None)` ≠ `None` | ✅ `m.containsKey(k)` (because `m.get(k)` returns `null` for both) | ✅ `m.ContainsKey(k)` / `TryGetValue` | ✅ `m.count(k)` / `m.find(k) != m.end()` | ✅ `m.containsKey(k)` (because `m[k]` returns `null` for both) | ✅ `m.get(k)` returns `?V`; `null` outer = absent, `null` inner = present-and-null | ⊘ no native map; libs use the comma-ok / found-flag idiom | ✅ `exists $h{$k}` (key present?) vs `defined $h{$k}` (value not `undef`?) — the two checks are orthogonal | ✅ `d[k]` returns `V?`; with a non-optional value type `nil` = absent, with `V?` values `Optional<Optional<V>>` distinguishes absent from stored-nil. `d.index(forKey:)` also tests presence |
| **List / array element** — out-of-bounds vs in-bounds `null` | 🟡 `arr[99] === undefined`, but explicit `arr[1] = undefined` is also `undefined`. `1 in arr` distinguishes holes. | ✅ out-of-bounds raises `IndexError`; explicit `None` is just `None`. | 🟡 out-of-bounds panics; nil element returns nil. `i < len(arr)` is the gate. | ❌ `arr[99]` returns `nil`; explicit `nil` is also `nil`. `arr.length` is the only check. | ✅ `array_key_exists($i, $arr)` works on indexed arrays too (PHP unifies them). | ❌ no holes (sort of) — `ipairs` stops at first nil. Mixed-presence arrays have undefined `#arr`. | ✅ `arr.get(i)` returns `Option<&T>`; out-of-bounds = `None`, present-null = `Some(&None)` | ✅ `list.get(99)` throws `IndexOutOfBoundsException`; null element returns null | ✅ `arr[99]` throws `ArgumentOutOfRangeException`; null element returns null | ✅ `vec.at(99)` throws `std::out_of_range`; `operator[]` is UB out-of-bounds | 🟡 `getOrNull(99)` returns null and explicit `null` also null — ambiguous. `arr[99]` throws. | ✅ out-of-bounds is a compile-time error (if static) or runtime panic in safe builds | ⊘ out-of-bounds is UB; no runtime check | 🟡 `$arr[99]` is `undef` and an in-bounds `undef` is also `undef`; `$#arr`/`exists $arr[$i]` is the gate (autovivification muddies sparse arrays). | ✅ out-of-bounds index traps (runtime); for `[T?]` an in-bounds `nil` element is `.some(nil)` after `indices.contains(i)`, distinct from out-of-bounds |
| **Object / struct field** — declared but unset vs `null` | 🟡 reading an undeclared field gives `undefined`; reading a declared `null` field gives `null`. `'x' in obj` distinguishes. | ✅ `hasattr(obj, 'x')` / `'x' in obj.__dict__` is true only when set | 🟡 Go struct fields always exist with zero value; no concept of "field not set". | ✅ `c.instance_variable_defined?(:@x)` | ✅ `property_exists($c, 'x')` distinguishes from `isset` | ⊘ Lua has no native objects — tables only, same constraints as map | ✅ struct fields are mandatory at construction; `Option<T>` for "absent" | 🟡 a declared field always exists with default `null`; no "field not declared yet" | 🟡 properties always exist after construction; `Nullable<T>` distinguishes at the type level | ✅ `std::optional<T>` member; otherwise fields are always present | 🟡 `lateinit` distinguishes "not yet set" from null (throws on access). Otherwise null. | ✅ struct fields require initialisers or defaults; `?T` for absent | ⊘ every declared field exists; "absent" must be modelled with an extra flag | 🟡 a blessed hash is just a hash: `exists $self->{x}` (field set?) vs `defined $self->{x}` (not `undef`?) distinguishes the two | ✅ stored properties require initialisers; a `var x: T?` defaults to `nil` only if declared optional — `T` vs `T?` makes "absent" a compile-time-distinct type |
| **Function return** — no value vs returned `null` | ✅ `void`/no-`return` yields `undefined`; explicit `return null` yields `null` | ❌ all four of `pass` / no `return` / `return` / `return None` yield the same `None` | ✅ `void`-like functions have no return slot; `T` returns must produce a value | ✅ implicit-last-expr; `r1; end` yields `nil`. No `void` distinction. | ❌ both `function f(){}` and `function f(){ return null; }` yield `NULL` | ✅ `select('#', f())` reports 0 for `r1`/`r3`, 1 for `r2 → nil` | ✅ `()` (unit) vs `Option<T>` — type-distinct | ✅ `void` vs `T`. `void` cannot return value. | ✅ `void` vs `T?`. `void` cannot return value. | ✅ `void` vs `std::optional<T>` / etc. | ✅ `Unit` vs `T?`. `Unit` returns the `Unit` instance, distinguishable from `null`. | ✅ `void` vs `?T` | ✅ `void` vs `T`. `T` always returns. | ✅ in list context `wantarray`/`return;` yields the empty list (0 returns) vs `return undef;` (1 return = `undef`); `scalar` collapses them, but the bare-`return` distinction is real | ✅ `Void`/no-`return` returns `()`, distinct from a `-> T?` returning `nil` |

## Per-language summary

### TypeScript / JavaScript
Two first-class values: `undefined` and `null`. They have distinct `typeof` (`'undefined'` vs `'object'`), distinct `===` identity, and the `in` operator gives you direct key-existence checks. The only minor wrinkle is array holes (`[, , 'x']`) which read as `undefined` like an out-of-bounds index — only `i in arr` tells them apart. **Best-in-class for this distinction.**

### Python
There is no "undefined" — a name is either bound or unbound (`NameError` on access). Once bound, the only "absent" value the language ships is `None`. Distinguishing absent from null *at the value level* requires a user-defined sentinel object (`SENT = object()`). At the map/list/attribute level, Python provides positional APIs (`'k' in m`, `hasattr`, `IndexError`) that work without a sentinel. Functions cannot tell "I didn't return" from "I returned `None`" — they're identical.

### Go
`nil` is a single value and `var v T` produces it for any ref-typed `T`. No way to tell "uninitialised" from "explicitly `nil`" at the variable level. The compensation is the comma-ok pattern at map/channel/type-assertion sites: `v, ok := m[k]`. For function args, variadic `...any` + `len(args)` distinguishes omitted from explicit nil. Struct fields always exist with zero values — to model "absent" you carry a flag or use a pointer (`*T`).

### Ruby
Only `nil` natively. But Ruby is unusually rich in introspection: `defined?` for variables, `key?`/`fetch` for hashes, `instance_variable_defined?` for ivars. Arrays are the weak spot — `arr[99]` silently returns `nil`, and sparse arrays auto-fill the gaps with `nil`. Functions always return the value of their last expression (`nil` if empty), no distinction.

### PHP
Has `null` plus a notion of "unset" — but `isset()` returns false for *both*. The correct check is `array_key_exists()` (for arrays) or `property_exists()` (for objects). PHP arrays unify maps and lists, so the same check works on numeric indices. `function_num_args()` reports the actual arg count for omitted-vs-null at parameters. Functions can return `null` or fall off the end — both yield `NULL`, **indistinguishable**.

### Lua
`nil` is the only "null-like" value. Three places where this hurts:
1. **Variables**: a declared-but-unassigned local is `nil` and identical to one explicitly set to `nil`.
2. **Tables**: assigning `nil` to a table key *removes the key*. You literally cannot store `nil` as a table value. A round-tripped JSON `null` either disappears or has to be replaced with a sentinel value by the parser.
3. **Arrays**: there's no real distinction between "hole" and "stored nil" — `ipairs` stops at the first nil, and `#arr` is undefined for sparse arrays.

The one bright spot: `select('#', ...)` reports the actual number of args (or returns from a function), so omitted-vs-nil works for varargs and for "did the function return anything?".

### Rust
`Option<T>` is part of the prelude and is the language's standard answer. `None` = absent, `Some(value)` = present. To represent "stored null" distinct from "absent", nest: `Option<Option<T>>` with `Some(None)` meaning the inner is null. Maps' `.get()` returns `Option<&V>` which composes naturally; out-of-bounds vec access via `.get(i)` returns `Option<&T>`. The compiler also enforces definite-assignment for locals, so an "uninitialised but in scope" state simply doesn't exist. **Cleanest native distinction of any mainstream language.**

### Java
`null` is the only "absent" for reference types. Locals must be definitely-assigned (compile-time enforced). Field-level "declared but never assigned" doesn't exist — declared fields default to `null`/`0`/`false`. Distinction happens via API: `Map.containsKey`, `Optional.isPresent`, `List.get(i)` throws on out-of-bounds. No way to express "function returned without producing a value" for non-void returns — `Optional<T>` is the workaround.

### C# / .NET
Like Java: definite-assignment for locals, ref types nullable. But .NET has `Nullable<T>` (for value types) and now non-nullable reference types via `<Nullable>enable</Nullable>` (since C# 8). `TryGetValue` is the standard map idiom. C# adds `[CallerArgumentExpression]` and optional parameters with defaults, so "was the arg passed?" is detectable for some patterns. Otherwise indistinguishable from Java.

### C++
`std::optional<T>` (since C++17) is the canonical "absent or T". `std::variant` with `std::monostate` lets you build a tagged "either-absent-or-one-of-these". `std::any` has `has_value()` for type-erased "absent". Maps use `.count` / `.find` for presence. Vectors throw on `.at(i)` out of bounds. Reading uninitialised primitives is UB, so the type system pushes you to `optional` for safety.

### Kotlin
`T?` for nullable types. `lateinit` is the interesting feature: a `lateinit var x: String` distinguishes "not yet set" (throws `UninitializedPropertyAccessException` on read) from `null`-assigned. For map keys it's the Java story (containsKey vs get). For lists, `getOrNull(i)` collapses out-of-bounds and stored-null to the same `null` — ambiguous. Functions return `Unit` (a singleton object) for void-like, distinct from `null`-returning `T?`.

### Zig
`?T` (optionals) are first-class — `null` is a value, `T` is a value, `?T` is either-or. Maps' `.get(k)` returns `?V`, so you can nest: `?V` outer null = absent, outer Some + inner null = "stored null". The probe shows nested `??i32` working correctly. Bounds-checked array access traps in safe builds. Struct fields require initialisers or default values, no "declared but unset" state.

### C
No managed types, no maps, no exceptions. The conventions are:
- For "absent at a pointer position": use `NULL` (the null pointer).
- For "absent at a map/list slot": library-dependent — typically a `bool found` out-param or a NULL-pointer return from `lookup()`.
- For "absent at a variable position": there is none — uninitialised auto storage is UB, static storage is zero-initialised.

The voxgig-struct C port shows the explicit approach: a tagged union with `VOXGIG_VAL_UNDEF` and `VOXGIG_VAL_NULL` as distinct enum cases. That's how you model the distinction *inside* C — the language gives you nothing for free.

### Perl
`undef` is the single null-like value — there is no separate "uninitialised" state, since `my $v;` and `my $v = undef;` are identical. The language's strength is its two orthogonal introspection operators at *positions*: `exists $h{$k}` asks "is the key present?" while `defined $h{$k}` asks "is the value not `undef`?". The two are independent, so a key can exist with an `undef` value and you can tell that apart from an absent key — the same `exists` vs `defined` pair works on hash entries, array elements, and blessed-hash object fields. For parameters, every argument flat-lands in `@_` and `scalar(@_)` is the true arg count, so "omitted" vs "explicit `undef`" is distinguishable. Arrays are the soft spot: autovivification and sparse `exists $arr[$i]` make hole-vs-`undef` muddy. Functions can `return;` (the empty list / zero values in list context) distinct from `return undef;` (one `undef` value) — though `scalar` context collapses them. The voxgig-struct Perl port models the JSON distinction explicitly: a blessed `$NONE` sentinel for TS-`undefined`/absent and a blessed JSON-`Null` sentinel for `null`, both kept apart from raw Perl `undef`.

### Swift
`Optional<T>` (spelled `T?`) is the native, type-system-enforced answer, in the same tier as Rust and Zig. `nil` is the empty case, `.some(value)` is present; a non-optional `let`/`var` *must* be assigned before use, so "uninitialised but in scope" doesn't exist. To distinguish "absent" from "stored nil" you nest — `Optional<Optional<T>>`, where `.some(nil)` is "present and nil". Dictionary subscript `d[k]` returns `V?` (so `nil` = absent for a non-optional value type), and `d.index(forKey:)` tests presence directly; array out-of-bounds traps, distinct from an in-bounds `nil` element of a `[T?]`. `??` (nil-coalescing) and `if let` / `guard let` are the ergonomic unwrap forms. Functions returning `Void` yield `()`, distinct from a `-> T?` returning `nil`. The voxgig-struct Swift port mirrors the canonical model with an `enum Value` carrying separate `.noval` (TS-`undefined`/absent) and `.null` (JSON null) cases, which `Equatable` keeps distinct.


## Cross-cutting observations

- **Compile-time languages** (rust, java, csharp, cpp, kotlin, zig, swift) all enforce definite-assignment for locals. That's enough to make "uninitialised variable" a compile-time error, sidestepping the problem. The remaining distinction at value/parameter/return level is handled by an explicit "Maybe" type (`Option`, `Optional`, `std::optional`, `?T`).

- **Dynamic languages** (javascript, python, ruby, php, lua, perl) can never enforce "declared but not assigned" — declaration and assignment are typically the same operation. Their answer is at the *position* level: `in`, `key?`, `array_key_exists`, `instance_variable_defined?`, `exists`/`defined`.

- **The position that's hardest across most languages** is the list/array element. JS, Go, Ruby and Kotlin all conflate "out-of-bounds" with "stored null" if you read by index without first checking the bounds. Only the strict-typed compile-time languages (Rust, C++, Zig) plus PHP (via `array_key_exists` on numeric indices) provide a clean answer.

- **The position that's easiest** is function return. Thirteen of fifteen languages have a `void`/`Unit`/no-return-value form distinct from `null`-returning (Perl's bare `return;` yields the empty list, distinct from `return undef;`; Swift's `Void` yields `()`). Python and PHP are the exceptions: both collapse all return paths to `None`/`NULL`.

- **Lua is the global outlier** at the map/table position: assigning `nil` deletes the key. No other language in this set has that property. Every Lua library that needs to round-trip JSON `null` invents a sentinel value.

## Function-return distinguishability — a tighter look

The probes captured this clearly:

| Language | `function r1() {}` | `function r2() { return null; }` | Distinguishable? |
|---|---|---|---|
| typescript / javascript | `undefined` | `null` | ✅ |
| python | `None` | `None` | ❌ |
| go (`func r() any { return nil }`) | n/a — must declare return type | `nil` | ✅ (different signatures) |
| ruby | `nil` | `nil` | ❌ (without `respond_to?`) |
| php | `NULL` | `NULL` | ❌ |
| lua | `select('#', f()) == 0` | `select('#', f()) == 1, first == nil` | ✅ |
| rust | `()` | `Option<T>::None` | ✅ (compile-time distinct types) |
| java | `void r1()` | `Object r2() { return null; }` | ✅ (compile-time distinct types) |
| csharp | `void` | `object?` | ✅ |
| cpp | `void` | `std::optional<T>::nullopt` | ✅ |
| kotlin | `Unit` | `T?: null` | ✅ |
| zig | `void` | `?T: null` | ✅ |
| c | `void` | `T (return val)` | ✅ |
| perl | `return;` → `()` (empty list) | `return undef;` → `undef` | ✅ (in list context; `scalar` collapses them) |
| swift | `Void` → `()` | `-> T?: nil` | ✅ (compile-time distinct types) |

## TL;DR

If you order the 15 languages by how cleanly they support "absent ≠ null" in the general case:

1. **rust, zig, swift** — `Option<T>` / `?T` is first-class. Cleanest.
2. **typescript / javascript** — `undefined` and `null` are distinct primitive values at every position except array holes.
3. **cpp** — needs `std::optional`/`std::variant`/`std::any`, but they're stdlib.
4. **ruby, php, perl** — only `nil`/`null`/`undef` natively, but rich introspection (`key?`, `array_key_exists`, `exists`/`defined`) makes positional distinction easy.
5. **java, csharp, kotlin** — definite-assignment plus `containsKey`/`Optional`/`Nullable<T>`/`lateinit`. Solid.
6. **go** — comma-ok at maps; pointer or extra flag elsewhere.
7. **python** — sentinel-object idiom is required at value level; positional introspection (`in`, `hasattr`, `IndexError`) is fine.
8. **c** — language gives nothing; you model it with a tagged union or NULL-pointer convention.
9. **lua** — at the table-value position, the distinction is **impossible**. Everywhere else it's emulated.
