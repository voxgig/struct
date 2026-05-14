// Injection state — passed through every recursive `inject` call as a
// reference type so command handlers (`transform_*`, `validate_*`,
// `select_*`) can mutate `keyI`, `keys`, `path`, `dparent`, `dpath`,
// and the shared `errs` collector. Mirrors the canonical TS `Injection`
// class — see typescript/src/StructUtility.ts.

import Foundation

public final class Injection: @unchecked Sendable {
  // `mode == 0` is the "uninitialized" / "options-only" state — `inject`
  // bootstraps a root Injection when it sees this. Once descent begins,
  // the inject loop sets mode to one of M_KEYPRE / M_VAL / M_KEYPOST.
  public var mode: Int = 0
  public var full: Bool = false
  public var keyI: Int = 0
  public var keys: [String] = [S_DTOP]
  public var key: String = S_DTOP
  public var val: Value = .noval
  public var parent: Value = .noval
  public var path: [String] = [S_DTOP]
  public var nodes: [Value] = []
  public var handler: Injector = _injecthandler
  public var errs: VList = VList()
  public var meta: VMap = VMap()
  public var dparent: Value = .noval
  public var dpath: [String] = [S_DTOP]
  public var base: String = S_DTOP
  public var modify: Modify? = nil
  public var prior: Injection? = nil
  public var extra: Value = .noval

  public init(val: Value, parent: Value) {
    self.val = val
    self.parent = parent
    self.nodes = [parent]
    self.dparent = .noval
  }

  // child(keyI, keys): build a child injection for the next descent step.
  public func child(_ keyI: Int, _ keys: [String]) -> Injection {
    let key = keys[keyI]
    let cv = getprop(val, .string(key))
    let cinj = Injection(val: cv, parent: val)
    cinj.keyI = keyI
    cinj.keys = keys
    cinj.key = key
    cinj.path = path + [key]
    cinj.nodes = nodes + [val]
    cinj.mode = mode
    cinj.handler = handler
    cinj.modify = modify
    cinj.base = base
    cinj.meta = meta
    cinj.errs = errs
    cinj.prior = self
    cinj.dpath = dpath
    cinj.dparent = dparent
    return cinj
  }

  // descend(): step into the current node. dparent walks down by
  // parentkey; dpath grows or contracts past synthetic $:KEY markers
  // (canonical behaviour).
  public func descend() -> Value {
    if let d = meta.entries["__d"], case .int(let n) = d {
      meta.entries["__d"] = .int(n + 1)
    } else {
      meta.entries["__d"] = .int(1)
    }
    let parentkey: String? = path.count >= 2 ? path[path.count - 2] : nil
    if dparent.isNoval {
      // No data: still grow dpath so relative paths line up with path.
      if dpath.count > 1, let pk = parentkey {
        dpath.append(pk)
      }
    } else if let pk = parentkey {
      dparent = getprop(dparent, .string(pk))
      let last = dpath.last ?? ""
      if last == "$:" + pk {
        dpath.removeLast()
      } else {
        dpath.append(pk)
      }
    }
    return dparent
  }

  // setval(val, ancestor?): write a value into the parent (or a
  // higher ancestor when |ancestor| >= 2). NONE deletes the slot.
  @discardableResult
  public func setval(_ v: Value, ancestor: Int = 0) -> Value {
    let absAnc = abs(ancestor)
    if absAnc < 2 {
      if v.isNoval {
        parent = delprop(parent, .string(key))
      } else {
        parent = setprop(parent, .string(key), v)
      }
      return parent
    }
    let nlen = nodes.count
    let plen = path.count
    guard absAnc <= nlen, absAnc <= plen else { return parent }
    let target = nodes[nlen - absAnc]
    let tkey = path[plen - absAnc]
    if v.isNoval {
      return delprop(target, .string(tkey))
    }
    return setprop(target, .string(tkey), v)
  }
}
