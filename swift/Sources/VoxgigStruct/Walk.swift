// walk — depth-first recursive descent with optional before / after
// callbacks. Each callback receives (key, val, parent, path) and may
// return a replacement value. Mirrors the canonical TS walk.

import Foundation

public typealias WalkApply = (Value, Value, Value, [String]) -> Value

public func walk(
  _ val: Value,
  _ before: WalkApply? = nil,
  _ after: WalkApply? = nil,
  _ maxdepth: Int = MAXDEPTH
) -> Value {
  return walkInner(val, .noval, .noval, [], before, after, maxdepth, 0)
}

private func walkInner(
  _ val: Value, _ key: Value, _ parent: Value, _ path: [String],
  _ before: WalkApply?, _ after: WalkApply?,
  _ maxdepth: Int, _ depth: Int
) -> Value {
  var v = val
  if let bf = before { v = bf(key, v, parent, path) }
  if depth >= maxdepth { return v }
  switch v {
  case .list(let l):
    for i in 0..<l.items.count {
      let kk = String(i)
      l.items[i] = walkInner(
        l.items[i], .string(kk), v,
        path + [kk], before, after, maxdepth, depth + 1)
    }
  case .map(let m):
    for (k, item) in m.entries {
      m.entries[k] = walkInner(
        item, .string(k), v,
        path + [k], before, after, maxdepth, depth + 1)
    }
  default: break
  }
  if let af = after { v = af(key, v, parent, path) }
  return v
}
