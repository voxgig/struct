// Test Provider (prototype) — CANONICAL implementation.
//
// Reads the shared corpus (build/test/test.json) and hands test code clean,
// normalized cases. It is NOT a test runner: it never calls the subject and
// never asserts. See ../PROVIDER.md for the model and ../AGENTS.md for usage.
//
// Zero runtime dependencies (Node built-ins only), matching repo policy.

import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const NULLMARK = '__NULL__'
const UNDEFMARK = '__UNDEF__'
const EXISTSMARK = '__EXISTS__'

export type InputKind = 'in' | 'args' | 'ctx'
export type ExpectKind = 'value' | 'error' | 'match' | 'absent'

export interface Input {
  kind: InputKind
  in?: any
  args?: any[]
  ctx?: Record<string, any>
}

export interface ErrorCheck {
  any: boolean
  text: string | null
  regex: boolean
}

export interface Expect {
  kind: ExpectKind
  value?: any
  error?: ErrorCheck
  match?: any
}

export interface Entry {
  function: string
  group: string
  index: number
  id: string | null
  doc: boolean
  client: string | null
  input: Input
  expect: Expect
  raw: Record<string, any>
}

export interface MatchResult {
  ok: boolean
  path?: string[]
  expected?: any
  actual?: any
}

// Default corpus path: build/test/test.json relative to the repo root.
function defaultTestFile(): string {
  const here = dirname(fileURLToPath(import.meta.url)) // test/proto/ts
  return join(here, '..', '..', '..', 'build', 'test', 'test.json')
}

export class TestProvider {
  readonly spec: any

  constructor(spec: any) {
    this.spec = spec
  }

  static load(testfile?: string): TestProvider {
    const file = testfile ?? defaultTestFile()
    return new TestProvider(JSON.parse(readFileSync(file, 'utf8')))
  }

  raw(): any {
    return this.spec
  }

  private fnNode(fn: string): Record<string, any> {
    const node = this.spec?.struct?.[fn] ?? this.spec?.[fn]
    if (null == node) {
      throw new Error(`Unknown function: ${fn}`)
    }
    return node
  }

  functions(): string[] {
    const root = this.spec?.struct ?? this.spec
    return Object.keys(root).filter((k) => isGroupBag(root[k]) || hasGroups(root[k]))
  }

  groups(fn: string): string[] {
    const node = this.fnNode(fn)
    return Object.keys(node).filter((k) => k !== 'name' && isGroupBag(node[k]))
  }

  entries(fn: string, group?: string): Entry[] {
    const node = this.fnNode(fn)
    const groups = group != null ? [group] : this.groups(fn)
    const out: Entry[] = []
    for (const g of groups) {
      const bag = node[g]
      if (!isGroupBag(bag)) {
        continue
      }
      const set: any[] = bag.set
      for (let i = 0; i < set.length; i++) {
        out.push(normalize(fn, g, i, set[i]))
      }
    }
    return out
  }
}

// A group bag is a map with a `set` array.
function isGroupBag(v: any): boolean {
  return null != v && 'object' === typeof v && !Array.isArray(v) && Array.isArray(v.set)
}

// A function node has at least one child group bag.
function hasGroups(v: any): boolean {
  return (
    null != v &&
    'object' === typeof v &&
    !Array.isArray(v) &&
    Object.keys(v).some((k) => k !== 'name' && isGroupBag(v[k]))
  )
}

function normalize(fn: string, group: string, index: number, raw: Record<string, any>): Entry {
  return {
    function: fn,
    group,
    index,
    id: null != raw.id ? String(raw.id) : null,
    doc: true === raw.doc,
    client: null != raw.client ? String(raw.client) : null,
    input: resolveInput(raw),
    expect: resolveExpect(raw),
    raw,
  }
}

function has(raw: Record<string, any>, key: string): boolean {
  return Object.prototype.hasOwnProperty.call(raw, key)
}

function resolveInput(raw: Record<string, any>): Input {
  if (has(raw, 'ctx')) {
    return { kind: 'ctx', ctx: raw.ctx }
  }
  if (has(raw, 'args')) {
    return { kind: 'args', args: raw.args }
  }
  return { kind: 'in', in: has(raw, 'in') ? raw.in : null }
}

function parseErr(err: any): ErrorCheck {
  if (true === err) {
    return { any: true, text: null, regex: false }
  }
  if ('string' === typeof err) {
    const m = err.match(/^\/(.+)\/$/)
    if (m) {
      return { any: false, text: m[1], regex: true }
    }
    return { any: false, text: err, regex: false }
  }
  // Non-true, non-string err spec: treat as "any error".
  return { any: true, text: null, regex: false }
}

function resolveExpect(raw: Record<string, any>): Expect {
  const matchPart = has(raw, 'match') ? raw.match : undefined
  if (has(raw, 'err')) {
    return { kind: 'error', error: parseErr(raw.err), match: matchPart }
  }
  if (has(raw, 'out')) {
    return { kind: 'value', value: raw.out, match: matchPart }
  }
  if (has(raw, 'match')) {
    return { kind: 'match', match: raw.match }
  }
  return { kind: 'absent' }
}

// ─── pure comparison helpers ───────────────────────────────────────────────

function stringify(x: any): string {
  return 'string' === typeof x ? x : JSON.stringify(x)
}

function normNull(x: any): any {
  if (NULLMARK === x || undefined === x) {
    return null
  }
  if (Array.isArray(x)) {
    return x.map(normNull)
  }
  if (null != x && 'object' === typeof x) {
    const o: Record<string, any> = {}
    for (const k of Object.keys(x)) {
      o[k] = normNull(x[k])
    }
    return o
  }
  return x
}

export function matchval(check: any, base: any): boolean {
  if (check === base) {
    return true
  }
  if ('string' === typeof check) {
    const basestr = stringify(base)
    const rem = check.match(/^\/(.+)\/$/)
    if (rem) {
      return new RegExp(rem[1]).test(basestr)
    }
    return basestr.toLowerCase().includes(check.toLowerCase())
  }
  if ('function' === typeof check) {
    return true
  }
  return false
}

export function equal(expected: any, actual: any): boolean {
  return deepEq(normNull(expected), normNull(actual))
}

// Strict variant for the runner's `{ null: false }` functions, where an absent
// value (undefined) is distinct from JSON null. Only __NULL__ is normalized.
export function equalStrict(expected: any, actual: any): boolean {
  return deepEq(normMark(expected), normMark(actual))
}

function normMark(x: any): any {
  if (NULLMARK === x) {
    return null
  }
  if (Array.isArray(x)) {
    return x.map(normMark)
  }
  if (null != x && 'object' === typeof x) {
    const o: Record<string, any> = {}
    for (const k of Object.keys(x)) {
      o[k] = normMark(x[k])
    }
    return o
  }
  return x
}

function deepEq(a: any, b: any): boolean {
  if (a === b) {
    return true
  }
  if (Array.isArray(a) && Array.isArray(b)) {
    return a.length === b.length && a.every((v, i) => deepEq(v, b[i]))
  }
  if (null != a && null != b && 'object' === typeof a && 'object' === typeof b) {
    const ak = Object.keys(a)
    const bk = Object.keys(b)
    return ak.length === bk.length && ak.every((k) => has(b, k) && deepEq(a[k], b[k]))
  }
  return false
}

export function errorMatches(check: ErrorCheck, message: string): boolean {
  if (check.any) {
    return true
  }
  if (null == check.text) {
    return false
  }
  if (check.regex) {
    return new RegExp(check.text).test(message)
  }
  return message.toLowerCase().includes(check.text.toLowerCase())
}

// Partial structural match: every leaf of `check` must match `base` at its path.
export function structMatch(check: any, base: any): MatchResult {
  let result: MatchResult = { ok: true }
  walkLeaves(check, [], (val, path) => {
    if (!result.ok) {
      return
    }
    const baseval = getpath(base, path)
    if (baseval === val) {
      return
    }
    if (UNDEFMARK === val && undefined === baseval) {
      return
    }
    if (EXISTSMARK === val && null != baseval) {
      return
    }
    if (!matchval(val, baseval)) {
      result = { ok: false, path, expected: val, actual: baseval }
    }
  })
  return result
}

function isNode(v: any): boolean {
  return null != v && 'object' === typeof v
}

function walkLeaves(node: any, path: string[], fn: (val: any, path: string[]) => void): void {
  if (Array.isArray(node)) {
    node.forEach((v, i) => walkLeaves(v, [...path, String(i)], fn))
  } else if (isNode(node)) {
    for (const k of Object.keys(node)) {
      walkLeaves(node[k], [...path, k], fn)
    }
  } else {
    fn(node, path)
  }
}

function getpath(store: any, path: string[]): any {
  let cur = store
  for (const key of path) {
    if (null == cur) {
      return undefined
    }
    cur = Array.isArray(cur) ? cur[Number(key)] : cur[key]
  }
  return cur
}
