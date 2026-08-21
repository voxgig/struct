"use strict";
// The shared test runner comes from voxgig/omni, consumed as a local
// checkout - omni is deliberately not published to a package registry (yet).
// The checkout is resolved the same way voxgig/sekreto's ports resolve it:
// $OMNI_HOME first, then sibling paths, taking the first directory that
// carries spec/fib.json. Set OMNI_HOME if yours lives elsewhere.
//
// Only the tests depend on omni. The library never does, and package.json
// gains no dependency - this is a runtime `require`, so `npm publish` and
// anything built from `src/` are untouched.
//
// TypeScript resolves imports at COMPILE time, and the checkout's location is
// only known at run time, so the shim is loaded with `require` rather than
// `import`. That is also why it loads omni's COMPILED output: a `.ts` import
// from outside this project's rootDir would have to be compiled by struct's
// own tsc, which would drag omni's whole source tree into struct's build.
//
// It follows that omni's typescript must be BUILT before these tests run -
// `dist/` is not committed there. CI does that explicitly; locally,
// `npm run build` in the omni checkout is enough.
//
// This is the TypeScript counterpart of javascript/test/omni.js,
// python/tests/omni.py, php/tests/omni.php, lua/test/omni.lua and
// csharp/tests/Omni.cs.
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.EXISTSMARK = exports.UNDEFMARK = exports.NULLMARK = exports.structprovider = exports.nullModifier = exports.makeRunner = void 0;
const node_fs_1 = require("node:fs");
const Path = __importStar(require("node:path"));
function omnihome() {
    const candidates = [];
    // Resolved against the process cwd: `existsSync` would do that anyway, but
    // `require` resolves a relative path against THIS file, so a relative
    // OMNI_HOME could pass the probe and then fail the require.
    if (process.env.OMNI_HOME) {
        candidates.push(Path.resolve(process.env.OMNI_HOME));
    }
    candidates.push(Path.resolve(__dirname, '..', '..', '..', 'omni'), Path.resolve(__dirname, '..', '..', '..', '..', 'omni'), '/workspace/omni', '/home/user/omni');
    for (const candidate of candidates) {
        if ((0, node_fs_1.existsSync)(Path.join(candidate, 'spec', 'fib.json'))) {
            return candidate;
        }
    }
    throw new Error('struct: voxgig/omni checkout not found - set OMNI_HOME');
}
const home = omnihome();
const shim = Path.join(home, 'typescript', 'dist', 'compat', 'struct.js');
if (!(0, node_fs_1.existsSync)(shim)) {
    throw new Error('struct: found an omni checkout at ' +
        home +
        " but its typescript is not built - run `npm install && npm run build` there. (omni's dist/ is not committed.)");
}
// eslint-disable-next-line @typescript-eslint/no-require-imports
const compat = require(shim);
// The corpus path, resolved the way this port's own runner resolved it:
//
//     JSON.parse(readFileSync(join(__dirname, testfile), 'utf8'))
//
// where `__dirname` was the RUNNER module's directory. This file compiles to
// that same directory, so joining here reproduces it exactly and the test
// files keep passing the relative path they always passed.
//
// It has to be done here rather than left to the shim. omni's shim resolves a
// relative path against the CALLER's directory, found by walking the stack -
// and this port's test files sit one level below the loader
// (`dist-test/utility/`), so the same string resolved one directory too deep
// and read `typescript/build/test/test.json`. Passing an absolute path is the
// route the shim documents, and it drops the stack walk entirely.
function corpuspath(testfile) {
    return Path.isAbsolute(testfile) ? testfile : Path.join(__dirname, testfile);
}
const makeRunner = (testfile, client) => compat.makeRunner(corpuspath(testfile), client);
exports.makeRunner = makeRunner;
const nullModifier = compat.nullModifier;
exports.nullModifier = nullModifier;
const structprovider = compat.structprovider;
exports.structprovider = structprovider;
// Literals rather than re-exports of the shim's constants: those would force
// omni to be loaded merely by importing this file. The values are part of the
// corpus format, not of omni's implementation, so they cannot drift silently -
// a change would fail every port at once.
const NULLMARK = '__NULL__';
exports.NULLMARK = NULLMARK;
const UNDEFMARK = '__UNDEF__';
exports.UNDEFMARK = UNDEFMARK;
const EXISTSMARK = '__EXISTS__';
exports.EXISTSMARK = EXISTSMARK;
//# sourceMappingURL=omni.js.map