# Changelog

## 0.2.0

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
- `$CHILD` in list mode now validates every element, including the first.
- `StructError` collects no backtrace on GHC 9.10 and later.
- The corpus runner moves to voxgig/omni.

## 0.1.0

- Initial Hackage release of the Haskell port of voxgig/struct.
- Full parity with the shared `build/test` corpus (getpath, merge, inject,
  transform, validate, walk, and the minor utilities).
