// This test utility runs the JSON-specified tests in build/test/test.json.

import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import { deepEqual, fail, AssertionError } from 'node:assert'

import { StructUtility } from '../dist/struct'

const NULLMARK = '__NULL__' // Value is JSON null
const UNDEFMARK = '__UNDEF__' // Value is not present (thus, undefined).
const EXISTSMARK = '__EXISTS__' // Value exists (not undefined).


type Subject = (...args: any[]) => any
type RunSet = (testspec: any, testsubject: Function) => Promise<any>
type RunSetFlags = (testspec: any, flags: Record<string, boolean>, testsubject: Function)
  => Promise<any>

type RunPack = {
  spec: Record<string, any>
  runset: RunSet
  runsetflags: RunSetFlags
  subject: Subject
  client: any
}

type TestPack = {
  name?: string
  client: any
  subject: Subject
  utility: any
}

type Flags = Record<string, boolean>


type Utility = {
  struct: StructUtility
  contextify: (ctxmap: Record<string, any>) => any
}

type Client = {
  utility: () => Utility
}


async function makeRunner(testfile: string, client: Client) {

  return async function runner(
    name: string,
    store?: any,
  ): Promise<RunPack> {
    store = store || {}

    const utility = client.utility()
    const structUtils = utility.struct

    let spec = resolveSpec(name, testfile)
    let clients = await resolveClients(client, spec, store, structUtils)
    let subject = resolveSubject(name, utility)

    let runsetflags: RunSetFlags = async (
      testspec: any,
      flags: Flags,
      testsubject: Function
    ) => {
      subject = testsubject || subject
      flags = resolveFlags(flags)
      const testspecmap = fixJSON(testspec, flags)

      const testset: any[] = testspecmap.set
      for (let entry of testset) {
        try {
          entry = resolveEntry(entry, flags)

          let testpack = resolveTestPack(name, entry, subject, client, clients)
          let args = resolveArgs(entry, testpack, utility, structUtils)

          let res = await testpack.subject(...args)
          res = fixJSON(res, flags)
          entry.res = res

          checkResult(entry, res, structUtils)
        }
        catch (err: any) {
          handleError(entry, err, structUtils)
        }
      }
    }

    let runset: RunSet = async (
      testspec: any,
      testsubject: Function
    ) => runsetflags(testspec, {}, testsubject)

    const runpack: RunPack = {
      spec,
      runset,
      runsetflags,
      subject,
      client,
    }

    return runpack
  }
}

function resolveSpec(name: string, testfile: string): Record<string, any> {
  const alltests =
    JSON.parse(readFileSync(join(
      __dirname, testfile), 'utf8'))

  let spec = alltests.primary?.[name] || alltests[name] || alltests
  return spec
}


async function resolveClients(
  client: any,
  spec: Record<string, any>,
  store: any,
  structUtils: Record<string, any>
):
  Promise<Record<string, any>> {

  const clients: Record<string, any> = {}
  if (spec.DEF && spec.DEF.client) {
    for (let cn in spec.DEF.client) {
      const cdef = spec.DEF.client[cn]
      const copts = cdef.test.options || {}
      if ('object' === typeof store && structUtils?.inject) {
        structUtils.inject(copts, store)
      }

      clients[cn] = await client.tester(copts)
    }
  }
  return clients
}


function resolveSubject(name: string, container: any) {
  const subject = container[name] || container.struct[name]
  return subject
}


function resolveFlags(flags?: Flags): Flags {
  if (null == flags) {
    flags = {}
  }
  flags.null = null == flags.null ? true : !!flags.null
  return flags
}


function resolveEntry(entry: any, flags: Flags): any {
  entry.out = null == entry.out && flags.null ? NULLMARK : entry.out
  return entry
}


function checkResult(entry: any, res: any, structUtils: Record<string, any>) {
  let matched = false

  if (entry.match) {
    const result = { in: entry.in, out: entry.res, ctx: entry.ctx }
    match(
      entry.match,
      result,
      structUtils
    )

    matched = true
  }

  const out = entry.out

  if (out === res) {
    return
  }

  // NOTE: allow match with no out.
  if (matched && (NULLMARK === out || null == out)) {
    return
  }

  deepEqual(null != res ? JSON.parse(JSON.stringify(res)) : res, entry.out)
}


// Handle errors from test execution
function handleError(entry: any, err: any, structUtils: Record<string, any>) {
  entry.thrown = err

  const entry_err = entry.err

  if (null != entry_err) {
    if (true === entry_err || matchval(entry_err, err.message, structUtils)) {
      if (entry.match) {
        match(
          entry.match,
          { in: entry.in, out: entry.res, ctx: entry.ctx, err: fixJSON(err, { null: true }) },
          structUtils
        )
      }
      return
    }

    fail('ERROR MATCH: [' + structUtils.stringify(entry_err) +
      '] <=> [' + err.message + ']')
  }

  // Unexpected error (test didn't specify an error expectation)
  else if (err instanceof AssertionError) {
    fail(err.message + '\n\nENTRY: ' + JSON.stringify(entry, null, 2))
  }
  else {
    fail(err.stack + '\\nnENTRY: ' + JSON.stringify(entry, null, 2))
  }
}


function resolveArgs(
  entry: any,
  testpack: TestPack,
  utility: Utility,
  structUtils: Record<string, any>
): any[] {
  let args: any[] = []

  if (entry.ctx) {
    args = [entry.ctx]
  }
  else if (entry.args) {
    args = entry.args
  }
  else {
    args = [structUtils.clone(entry.in)]
  }

  if (entry.ctx || entry.args) {
    let first = args[0]
    if (structUtils.ismap(first)) {
      first = structUtils.clone(first)
      first = utility.contextify(first)
      args[0] = first
      entry.ctx = first

      first.client = testpack.client
      first.utility = testpack.utility
    }
  }

  return args
}


function resolveTestPack(
  name: string,
  entry: any,
  subject: Subject,
  client: any,
  clients: Record<string, any>
) {
  const testpack: TestPack = {
    name,
    client,
    subject,
    utility: client.utility(),
  }

  if (entry.client) {
    testpack.client = clients[entry.client]
    testpack.utility = testpack.client.utility()
    testpack.subject = resolveSubject(name, testpack.utility)
  }

  return testpack
}


function match(
  check: any,
  basex: any,
  structUtils: Record<string, any>
) {
  const cbase = structUtils.clone(basex)

  structUtils.walk(check, (_key: any, val: any, _parent: any, path: any) => {
    if (!structUtils.isnode(val)) {
      let baseval = structUtils.getpath(cbase, path)

      if (baseval === val) {
        return val
      }

      // Explicit undefined expected
      if (UNDEFMARK === val && undefined === baseval) {
        return val
      }

      // Explicit defined expected
      if (EXISTSMARK === val && null != baseval) {
        return val
      }

      if (!matchval(val, baseval, structUtils)) {
        fail('MATCH: ' + path.join('.') +
          ': [' + structUtils.stringify(val) +
          '] <=> [' + structUtils.stringify(baseval) + ']')
      }
    }

    return val
  })
}


function matchval(
  check: any,
  base: any,
  structUtils: Record<string, any>
) {
  let pass = check === base

  if (!pass) {

    if ('string' === typeof check) {
      let basestr = structUtils.stringify(base)

      let rem = check.match(/^\/(.+)\/$/)
      if (rem) {
        pass = new RegExp(rem[1]).test(basestr)
      }
      else {
        pass = basestr.toLowerCase().includes(structUtils.stringify(check).toLowerCase())
      }
    }
    else if ('function' === typeof check) {
      pass = true
    }
  }

  return pass
}


function fixJSON(val: any, flags?: Flags): any {
  if (null == val) {
    return flags?.null ? NULLMARK : val
  }

  const replacer = (_k: string, v: any) => {
    if (null == v && flags?.null) {
      return NULLMARK
    }

    if (v instanceof Error) {
      return {
        ...v,
        name: v.name,
        message: v.message,
      }
    }

    return v
  }

  return JSON.parse(JSON.stringify(val, replacer))
}


function nullModifier(
  val: any,
  key: any,
  parent: any
) {
  if ("__NULL__" === val) {
    parent[key] = null
  }
  else if ('string' === typeof val) {
    parent[key] = val.replaceAll('__NULL__', 'null')
  }
}


export {
  NULLMARK,
  EXISTSMARK,
  nullModifier,
  makeRunner,
}

