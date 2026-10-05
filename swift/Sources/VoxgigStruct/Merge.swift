// merge — deep-merge a list of values. Later values win; nodes deep-
// merge; scalars overwrite. The first element is modified in place
// (matches canonical).

import Foundation

public func merge(_ vals: Value, _ maxdepth: Int = MAXDEPTH) -> Value {
  guard case .list(let l) = vals else { return vals }
  if l.items.isEmpty { return .noval }
  if l.items.count == 1 { return l.items[0] }
  // Canonical clamps depth to ≥ 0 with slice's number-clamp branch.
  let md = max(0, maxdepth)
  var out = l.items[0]
  for i in 1..<l.items.count {
    out = mergePair(out, l.items[i], md, 0)
  }
  // depth == 0 short-circuit: replace with the last element, then
  // empty-ify nodes (matches canonical TS).
  if md == 0 {
    let last = l.items.last ?? .noval
    if last.isList { return .list([]) }
    if last.isMap { return .map(VMap()) }
    return last
  }
  return out
}

private func mergePair(_ a: Value, _ b: Value, _ maxdepth: Int, _ depth: Int) -> Value {
  guard isnode(b) else { return b }
  if depth >= maxdepth { return b }
  var a = a
  if !isnode(a) || islist(a) != islist(b) {
    // The override wins: it is copied, so no later merge writes into it.
    a = islist(b) ? .list([]) : .map(VMap())
  }
  if case .list(let la) = a, case .list(let lb) = b {
    for i in 0..<lb.items.count {
      if i < la.items.count {
        la.items[i] = mergePair(la.items[i], lb.items[i], maxdepth, depth + 1)
      } else {
        la.items.append(mergePair(.noval, lb.items[i], maxdepth, depth + 1))
      }
    }
    return a
  }
  if case .map(let ma) = a, case .map(let mb) = b {
    for (k, bv) in mb.entries {
      ma.entries[k] = mergePair(ma.entries[k] ?? .noval, bv, maxdepth, depth + 1)
    }
    return a
  }
  return b
}
