# JavaScript Implementation Notes

## undefined vs null

JavaScript natively distinguishes `undefined` from `null`. In this library:
- `undefined` means **property absence** (the key does not exist, or no value was provided).
- `null` represents **JSON null** (an explicit null value in the data).

TypeScript tests relating to `undefined` test property absence behavior. Since JavaScript
shares this semantics, no special handling is needed — the language natively supports this distinction.

## Type System

This implementation uses bitfield integers for the type system, matching the TypeScript canonical.
Type constants (`T_any`, `T_noval`, `T_boolean`, etc.) are exported and `typify()` returns
integer bitfields. Use `typename()` to get the human-readable name for error messages.
Bitwise operations allow composite type checks (e.g., `T_scalar | T_string`).
