// getpath / setpath — descend / set along a dotted path. getpath
// supports the canonical injection extensions: `$KEY` substitution,
// `$REF:` / `$GET:` / `$META:` meta-path syntax, consecutive-dot
// ancestor traversal, and a custom handler callback.

import Foundation

// MARK: - setpath

@discardableResult
public func setpath(_ store: Value, _ pathIn: Value, _ val: Value) -> Value {
  // Keep each segment's original Value so the int-vs-string distinction
  // (which decides list-vs-map for an intermediate node) is preserved.
  var parts: [Value] = []
  if case .list(let l) = pathIn {
    parts = l.items
  } else if let s = pathIn.asString {
    parts = s.split(separator: ".", omittingEmptySubsequences: false).map {
      Value.string(String($0))
    }
  } else {
    return .noval
  }
  if parts.isEmpty { return .noval }
  var node = store
  for i in 0..<(parts.count - 1) {
    let k = parts[i]
    let nxt = parts[i + 1]
    // An intermediate node is a list only when the NEXT segment is an integer
    // value; a string-digit segment (e.g. "0") makes a map.
    let nxtIsInt = (T_integer & typify(nxt)) != 0
    var child = lookup(node, k)
    if !isnode(child) {
      child = nxtIsInt ? .list(VList()) : .map(VMap())
      setprop(node, k, child)
    }
    node = child
  }
  // Canonical setpath returns the leaf key's PARENT node, not the whole store.
  setprop(node, parts.last!, val)
  return node
}

// MARK: - getpath

public func getpath(_ store: Value, _ pathIn: Value, _ inj: Injection? = nil) -> Value {
  var parts: [String] = []
  switch pathIn {
  case .list(let l): parts = l.items.map { strkey($0) }
  case .string(let s):
    if s.isEmpty {
      parts = [""]
    } else {
      parts = s.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
    }
  case .int(let n): parts = [String(n)]
  case .double(let d): parts = [JSON.formatDouble(d)]
  default:
    return .noval
  }

  let base = inj?.base
  var src: Value = .noval
  if let b = base { src = getprop(store, .string(b), store) } else { src = store }
  let numparts = parts.count
  let dparent = inj?.dparent ?? .noval
  let dpath = inj?.dpath ?? []

  var val: Value = store

  if pathIn.isNoval || store.isNoval || (numparts == 1 && parts[0] == S_MT) {
    val = src
  } else if numparts > 0 {
    if numparts == 1 {
      val = getprop(store, .string(parts[0]))
    }
    if !isfunc(val) {
      val = src
      // Meta-path syntax on first part.
      if let inj = inj {
        let firstNS = parts[0] as NSString
        let metaMatch = R_META_PATH.firstMatch(
          in: parts[0], range: NSRange(location: 0, length: firstNS.length))
        if let m = metaMatch {
          let name = firstNS.substring(with: m.range(at: 1))
          let rest = firstNS.substring(with: m.range(at: 3))
          val = getprop(.map(inj.meta), .string(name))
          parts[0] = rest
        }
      }
      var pI = 0
      while !val.isNoval && pI < numparts {
        var part = parts[pI]
        // Special prefixes resolved via sub-getpath.
        if let inj = inj {
          if part == S_DKEY {
            part = inj.key
          } else if part.hasPrefix("$GET:") && part.hasSuffix("$") {
            let sub = String(part.dropFirst(5).dropLast())
            part = stringify(getpath(src, .string(sub), inj))
          } else if part.hasPrefix("$REF:") && part.hasSuffix("$") {
            let sub = String(part.dropFirst(5).dropLast())
            let spec = getprop(store, .string(S_DSPEC))
            part = stringify(getpath(spec, .string(sub), inj))
          } else if part.hasPrefix("$META:") && part.hasSuffix("$") {
            let sub = String(part.dropFirst(6).dropLast())
            part = stringify(getpath(.map(inj.meta), .string(sub), inj))
          }
        }
        // $$ → $ escape.
        part = part.replacingOccurrences(of: "$$", with: "$")
        if part == S_MT {
          var ascends = 0
          while pI + 1 < numparts && parts[pI + 1] == S_MT {
            ascends += 1
            pI += 1
          }
          if inj != nil, ascends > 0 {
            var actualAsc = ascends
            if pI == parts.count - 1 { actualAsc -= 1 }
            if actualAsc == 0 {
              val = dparent
            } else {
              var cut = dpath.count - actualAsc
              if cut < 0 { cut = 0 }
              var full = Array(dpath[0..<cut])
              if pI + 1 < parts.count {
                full.append(contentsOf: parts[(pI + 1)...])
              }
              if actualAsc <= dpath.count {
                val = getpath(store, .list(full.map { Value.string($0) }))
              } else {
                val = .noval
              }
              break
            }
          } else {
            val = dparent
          }
        } else {
          val = getprop(val, .string(part))
        }
        pI += 1
      }
    }
  }

  if let inj = inj, isfunc(inj.handler as Injector) {
    let ref = pathify(pathIn)
    val = inj.handler(inj, val, ref, store)
  }
  return val
}

// `isfunc` helper that works on an already-typed Injector — Swift's
// typealias is a function type, so just used to silence unused-warning.
private func isfunc(_: Injector) -> Bool { true }
