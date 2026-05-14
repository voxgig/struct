// inject — recursive descent that resolves backtick references and
// command-table injectors. The three-phase key processing
// (M_KEYPRE → M_VAL → M_KEYPOST) is canonical: command handlers can
// rewrite the parent map mid-iteration via `setval`, and `keyI = -1`
// causes the outer loop to re-process the same slot with the new value.

import Foundation

// MARK: - Default handler

public func _injecthandler(_ inj: Injection, _ val: Value, _ ref: String, _ store: Value) -> Value {
    let isCmd: Bool = {
        guard case .function = val else { return false }
        return ref.isEmpty || ref.hasPrefix(S_DS)
    }()
    if isCmd {
        guard case .function(let fn) = val else { return val }
        return fn(inj, val, ref, store)
    }
    if inj.mode == M_VAL && inj.full {
        inj.setval(val)
    }
    return val
}

// MARK: - _injectstr — full or partial backtick injection

public func _injectstr(_ raw: String, _ store: Value, _ inj: Injection?) -> Value {
    if raw.isEmpty { return .string("") }
    let nsRaw = raw as NSString
    // Full pattern: ^`($NAME|[^`]*)[0-9]*`$
    let r = NSRange(location: 0, length: nsRaw.length)
    if let m = R_INJECTION_FULL.firstMatch(in: raw, range: r), m.range == r {
        var pathref = nsRaw.substring(with: m.range(at: 1))
        if pathref.count > 3 {
            pathref = pathref
                .replacingOccurrences(of: "$BT", with: "`")
                .replacingOccurrences(of: "$DS", with: "$")
        }
        inj?.full = true
        return getpath(store, .string(pathref), inj)
    }
    if !raw.contains("`") { return .string(raw) }
    inj?.full = false
    // Partial: replace each `...` segment.
    var out = ""
    var idx = raw.startIndex
    while idx < raw.endIndex {
        if raw[idx] == "`" {
            if let close = raw.range(of: "`", range: raw.index(after: idx)..<raw.endIndex) {
                var ref = String(raw[raw.index(after: idx)..<close.lowerBound])
                if ref.count > 3 {
                    ref = ref
                        .replacingOccurrences(of: "$BT", with: "`")
                        .replacingOccurrences(of: "$DS", with: "$")
                }
                inj?.full = false
                let found = getpath(store, .string(ref), inj)
                switch found {
                case .noval: break
                case .null:  out += "null"
                case .string(let s): out += s
                case .bool(let b):   out += b ? "true" : "false"
                case .int(let n):    out += String(n)
                case .double(let d): out += JSON.formatDouble(d)
                case .list, .map:    out += jsonify(found)
                case .function:      out += "<function>"
                case .sentinel(let s): out += s.marker
                }
                idx = raw.index(after: close.lowerBound)
                continue
            }
        }
        out.append(raw[idx])
        idx = raw.index(after: idx)
    }
    // Run a final handler pass over the partial result.
    if let inj = inj {
        inj.full = true
        let res = inj.handler(inj, .string(out), raw, store)
        return res
    }
    return .string(out)
}

// MARK: - Top-level inject

@discardableResult
public func inject(_ val: Value, _ store: Value, _ injdef: Injection? = nil) -> Value {
    let inj: Injection
    let rootInit = injdef == nil || injdef!.mode == 0
    if rootInit {
        // Virtual parent holder.
        let vp = VMap()
        vp.entries[S_DTOP] = val
        let root = Injection(val: val, parent: .map(vp))
        root.mode = M_VAL
        root.dparent = store
        // Wire $ERRS from store if present.
        if case .map(let sm) = store, let errs = sm.entries[S_DERRS], case .list(let el) = errs {
            root.errs = el
        }
        root.meta.entries["__d"] = .int(0)
        // Carry over caller-supplied options from injdef.
        if let idef = injdef {
            if let m = idef.modify { root.modify = m }
            if !idef.extra.isNoval { root.extra = idef.extra }
            if !idef.meta.entries.isEmpty { root.meta = idef.meta }
            if !idef.errs.items.isEmpty { root.errs = idef.errs }
            // Caller-provided meta/errs override above.
        }
        inj = root
    } else {
        inj = injdef!
    }
    _ = inj.descend()
    var out = val
    if isnode(val) {
        var nodekeys: [String] = []
        if case .map(let m) = val {
            // Plain keys first, then $-prefixed in alphabetical order.
            let allSorted = m.entries.keys.sorted()
            let plain = allSorted.filter { !$0.contains(S_DS) }
            let cmd   = allSorted.filter { $0.contains(S_DS) }
            nodekeys = plain + cmd
        } else if case .list(let l) = val {
            nodekeys = (0..<l.items.count).map { String($0) }
        }
        var nkI = 0
        while nkI < nodekeys.count {
            let childinj = inj.child(nkI, nodekeys)
            let nodekey = childinj.key
            childinj.mode = M_KEYPRE
            let prekey = _injectstr(nodekey, store, childinj)
            nkI = childinj.keyI
            nodekeys = childinj.keys
            if !prekey.isNoval {
                childinj.val = getprop(val, prekey)
                childinj.mode = M_VAL
                inject(childinj.val, store, childinj)
                nkI = childinj.keyI
                nodekeys = childinj.keys
                childinj.mode = M_KEYPOST
                _ = _injectstr(nodekey, store, childinj)
                nkI = childinj.keyI
                nodekeys = childinj.keys
            }
            nkI += 1
        }
    } else if case .string(let s) = val {
        inj.mode = M_VAL
        out = _injectstr(s, store, inj)
        let isSkip: Bool = {
            if case .sentinel(let sn) = out { return sn === SKIP }
            return false
        }()
        if !isSkip {
            inj.setval(out)
        }
    }
    // Modify hook (runs after injection).
    if let mod = inj.modify {
        let isSkip: Bool = {
            if case .sentinel(let sn) = out { return sn === SKIP }
            return false
        }()
        if !isSkip {
            let mkey = inj.key
            let mparent = inj.parent
            let mval = getprop(mparent, .string(mkey))
            mod(mval, .string(mkey), mparent, inj, store)
        }
    }
    inj.val = out
    return lookup(inj.parent, .string(S_DTOP))
}

// MARK: - Helpers for transform / validate / select commands

public func checkPlacement(_ modes: Int, _ name: String, _ parentTypes: Int, _ inj: Injection) -> Bool {
    if (modes & inj.mode) == 0 {
        let allowed = [M_KEYPRE, M_VAL, M_KEYPOST]
            .filter { (modes & $0) != 0 }
            .compactMap { MODENAME[$0] }
            .joined(separator: ",")
        inj.errs.items.append(.string("$\(name): invalid placement as " +
            (MODENAME[inj.mode] ?? "?") + ", expected: " + allowed))
        return false
    }
    if parentTypes != 0 {
        let ptype = typify(inj.parent)
        if (parentTypes & ptype) == 0 {
            inj.errs.items.append(.string("$\(name): invalid placement in parent " +
                typename(ptype) + "."))
            return false
        }
    }
    return true
}

public func injectorArgs(_ types: [Int], _ args: Value) -> (Value, [Value]) {
    guard case .list(let l) = args else { return (.noval, []) }
    var out: [Value] = []
    for i in 0..<types.count {
        let expected = types[i]
        let arg = i < l.items.count ? l.items[i] : Value.noval
        let atype = typify(arg)
        if expected != T_any && (expected & atype) == 0 {
            return (.string("argument \(i) not of type: " + typename(expected)), l.items)
        }
        out.append(arg)
    }
    return (.noval, out)
}

public func injectChild(_ child: Value, _ store: Value, _ inj: Injection) -> Injection {
    var cinj = inj
    if let prior = inj.prior {
        if let prior2 = prior.prior {
            cinj = prior2.child(prior.keyI, prior.keys)
            cinj.val = child
            setprop(cinj.parent, .string(prior.key), child)
        } else {
            cinj = prior.child(inj.keyI, inj.keys)
            cinj.val = child
            setprop(cinj.parent, .string(inj.key), child)
        }
    }
    inject(child, store, cinj)
    return cinj
}

// MARK: - Builder helpers (jm / jt)
//
// `jm` takes alternating key/value args (Swift variadics can't carry a
// tuple type without ambiguity at the call site). It accepts a key, a
// value, then any number of additional (key, value) tuples for further
// pairs. Use `jmd` to pass a Dictionary or OrderedDictionary literal.

public func jm(_ k1: String, _ v1: Value, _ pairs: (String, Value)...) -> Value {
    let m = VMap()
    m.entries[k1] = v1
    for (k, v) in pairs { m.entries[k] = v }
    return .map(m)
}

public func jmd(_ entries: OrderedDictionary<String, Value>) -> Value {
    return .map(VMap(entries))
}

public func jt(_ items: Value...) -> Value {
    return .list(VList(items))
}
