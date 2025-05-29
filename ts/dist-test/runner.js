"use strict";
// This test utility runs the JSON-specified tests in build/test/test.json.
Object.defineProperty(exports, "__esModule", { value: true });
exports.EXISTSMARK = exports.NULLMARK = void 0;
exports.nullModifier = nullModifier;
exports.makeRunner = makeRunner;
const node_fs_1 = require("node:fs");
const node_path_1 = require("node:path");
const node_assert_1 = require("node:assert");
const NULLMARK = '__NULL__'; // Value is JSON null
exports.NULLMARK = NULLMARK;
const UNDEFMARK = '__UNDEF__'; // Value is not present (thus, undefined).
const EXISTSMARK = '__EXISTS__'; // Value exists (not undefined).
exports.EXISTSMARK = EXISTSMARK;
async function makeRunner(testfile, client) {
    return async function runner(name, store) {
        store = store || {};
        const utility = client.utility();
        const structUtils = utility.struct;
        let spec = resolveSpec(name, testfile);
        let clients = await resolveClients(client, spec, store, structUtils);
        let subject = resolveSubject(name, utility);
        let runsetflags = async (testspec, flags, testsubject) => {
            subject = testsubject || subject;
            flags = resolveFlags(flags);
            const testspecmap = fixJSON(testspec, flags);
            const testset = testspecmap.set;
            for (let entry of testset) {
                try {
                    entry = resolveEntry(entry, flags);
                    let testpack = resolveTestPack(name, entry, subject, client, clients);
                    let args = resolveArgs(entry, testpack, utility, structUtils);
                    let res = await testpack.subject(...args);
                    res = fixJSON(res, flags);
                    entry.res = res;
                    checkResult(entry, res, structUtils);
                }
                catch (err) {
                    handleError(entry, err, structUtils);
                }
            }
        };
        let runset = async (testspec, testsubject) => runsetflags(testspec, {}, testsubject);
        const runpack = {
            spec,
            runset,
            runsetflags,
            subject,
            client,
        };
        return runpack;
    };
}
function resolveSpec(name, testfile) {
    const alltests = JSON.parse((0, node_fs_1.readFileSync)((0, node_path_1.join)(__dirname, testfile), 'utf8'));
    let spec = alltests.primary?.[name] || alltests[name] || alltests;
    return spec;
}
async function resolveClients(client, spec, store, structUtils) {
    const clients = {};
    if (spec.DEF && spec.DEF.client) {
        for (let cn in spec.DEF.client) {
            const cdef = spec.DEF.client[cn];
            const copts = cdef.test.options || {};
            if ('object' === typeof store && structUtils?.inject) {
                structUtils.inject(copts, store);
            }
            clients[cn] = await client.tester(copts);
        }
    }
    return clients;
}
function resolveSubject(name, container) {
    const subject = container[name] || container.struct[name];
    return subject;
}
function resolveFlags(flags) {
    if (null == flags) {
        flags = {};
    }
    flags.null = null == flags.null ? true : !!flags.null;
    return flags;
}
function resolveEntry(entry, flags) {
    entry.out = null == entry.out && flags.null ? NULLMARK : entry.out;
    return entry;
}
function checkResult(entry, res, structUtils) {
    let matched = false;
    if (entry.match) {
        const result = { in: entry.in, out: entry.res, ctx: entry.ctx };
        match(entry.match, result, structUtils);
        matched = true;
    }
    const out = entry.out;
    if (out === res) {
        return;
    }
    // NOTE: allow match with no out.
    if (matched && (NULLMARK === out || null == out)) {
        return;
    }
    (0, node_assert_1.deepEqual)(null != res ? JSON.parse(JSON.stringify(res)) : res, entry.out);
}
// Handle errors from test execution
function handleError(entry, err, structUtils) {
    entry.thrown = err;
    const entry_err = entry.err;
    if (null != entry_err) {
        if (true === entry_err || matchval(entry_err, err.message, structUtils)) {
            if (entry.match) {
                match(entry.match, { in: entry.in, out: entry.res, ctx: entry.ctx, err: fixJSON(err, { null: true }) }, structUtils);
            }
            return;
        }
        (0, node_assert_1.fail)('ERROR MATCH: [' + structUtils.stringify(entry_err) +
            '] <=> [' + err.message + ']');
    }
    // Unexpected error (test didn't specify an error expectation)
    else if (err instanceof node_assert_1.AssertionError) {
        (0, node_assert_1.fail)(err.message + '\n\nENTRY: ' + JSON.stringify(entry, null, 2));
    }
    else {
        (0, node_assert_1.fail)(err.stack + '\\nnENTRY: ' + JSON.stringify(entry, null, 2));
    }
}
function resolveArgs(entry, testpack, utility, structUtils) {
    let args = [];
    if (entry.ctx) {
        args = [entry.ctx];
    }
    else if (entry.args) {
        args = entry.args;
    }
    else {
        args = [structUtils.clone(entry.in)];
    }
    if (entry.ctx || entry.args) {
        let first = args[0];
        if (structUtils.ismap(first)) {
            first = structUtils.clone(first);
            first = utility.contextify(first);
            args[0] = first;
            entry.ctx = first;
            first.client = testpack.client;
            first.utility = testpack.utility;
        }
    }
    return args;
}
function resolveTestPack(name, entry, subject, client, clients) {
    const testpack = {
        name,
        client,
        subject,
        utility: client.utility(),
    };
    if (entry.client) {
        testpack.client = clients[entry.client];
        testpack.utility = testpack.client.utility();
        testpack.subject = resolveSubject(name, testpack.utility);
    }
    return testpack;
}
function match(check, basex, structUtils) {
    const cbase = structUtils.clone(basex);
    structUtils.walk(check, (_key, val, _parent, path) => {
        if (!structUtils.isnode(val)) {
            let baseval = structUtils.getpath(cbase, path);
            if (baseval === val) {
                return val;
            }
            // Explicit undefined expected
            if (UNDEFMARK === val && undefined === baseval) {
                return val;
            }
            // Explicit defined expected
            if (EXISTSMARK === val && null != baseval) {
                return val;
            }
            if (!matchval(val, baseval, structUtils)) {
                (0, node_assert_1.fail)('MATCH: ' + path.join('.') +
                    ': [' + structUtils.stringify(val) +
                    '] <=> [' + structUtils.stringify(baseval) + ']');
            }
        }
        return val;
    });
}
function matchval(check, base, structUtils) {
    let pass = check === base;
    if (!pass) {
        if ('string' === typeof check) {
            let basestr = structUtils.stringify(base);
            let rem = check.match(/^\/(.+)\/$/);
            if (rem) {
                pass = new RegExp(rem[1]).test(basestr);
            }
            else {
                pass = basestr.toLowerCase().includes(structUtils.stringify(check).toLowerCase());
            }
        }
        else if ('function' === typeof check) {
            pass = true;
        }
    }
    return pass;
}
function fixJSON(val, flags) {
    if (null == val) {
        return flags?.null ? NULLMARK : val;
    }
    const replacer = (_k, v) => {
        if (null == v && flags?.null) {
            return NULLMARK;
        }
        if (v instanceof Error) {
            return {
                ...v,
                name: v.name,
                message: v.message,
            };
        }
        return v;
    };
    return JSON.parse(JSON.stringify(val, replacer));
}
function nullModifier(val, key, parent) {
    if ("__NULL__" === val) {
        parent[key] = null;
    }
    else if ('string' === typeof val) {
        parent[key] = val.replaceAll('__NULL__', 'null');
    }
}
//# sourceMappingURL=runner.js.map