# Ruby Implementation Notes

## undefined vs null

Ruby has only `nil` — there is no native distinction between "absent" and "null".
For this library:
- `UNDEF = Object.new.freeze` is used as a sentinel for **property absence**
  (the TypeScript `undefined` equivalent). This is a unique frozen object that cannot
  collide with any real data value.
- `nil` represents Ruby's native null, which maps to JSON null.
- TypeScript tests relating to `undefined` should be treated as **property absence**: the key
  does not exist in the Hash, or the function parameter was not provided.
- Where the distinction matters, the test runner uses marker strings:
  `NULLMARK = '__NULL__'` for JSON null and `UNDEFMARK = '__UNDEF__'` for absent values.
- In practice, most APIs do not use JSON null, so this ambiguity rarely causes issues.

## Type System

This implementation uses bitfield integers for the type system, matching the TypeScript canonical.
Type constants (`T_any`, `T_noval`, `T_boolean`, etc.) are defined as module constants and
`typify()` returns integer bitfields. Use `typename()` to get the human-readable name for
error messages. Bitwise operations allow composite type checks (e.g., `T_scalar | T_string`).
