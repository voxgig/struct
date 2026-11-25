# Changelog

## 0.3.0

- `$ONE` is gone. `$NOF` sets how many of its specs a value must match, and
  `$ALL` requires every one. A spec that names an unknown checker fails before
  any data is read.
- New checkers: `$LEN` bounds the length of a string, list or map, `$RANGE`
  bounds a number, `$LIKE` matches a string against a pattern, and `$REST`
  types the keys a map spec does not name and the items after a list spec's
  named ones.
- `$REF` checks as the spec it names, and a relative path counts from the
  node that holds it.
- A list spec is closed, and so is a map spec that names keys, even when the
  data gives none of them. `[]` and `{}` stay open.
- A failed type check keeps its value, so the items after it are still
  checked, and a list item that resolves to nothing no longer hides the next.
- The condense functions are ported, and list keys are read only as
  canonical integers.

## 0.2.2

- `$CHILD` in list mode now validates every element, including the first.
- The corpus runner moves to voxgig/omni, taken from its release tags.

## 0.2.1

- Initial public release of the Dart port of voxgig/struct.
- Full parity with the shared `build/test` corpus (getpath, merge, inject,
  transform, validate, walk, and the minor utilities).
