// The corpus runner is voxgig/omni. This port's own copy of that algorithm -
// the 226-line test/runner.zig - is gone. What is left here is a bridge and
// a subject factory: which function answers a group, and how this port's
// values cross to omni's and back.
//
// omni is consumed as a local checkout, wired in by build.zig from the
// `-Domni=<path>` option the Makefile computes from $OMNI_HOME. Neither
// build.zig.zon nor the library names omni, so nothing that depends on this
// package depends on it (register 4.13).
//
// The bridge is cheap here in a way it is not for most ports: omni's value
// model IS std.json.Value, and this port already converts to and from
// std.json.Value at its own boundary (fromStdJson / toStdJson). So the
// conversion is the port's own pair, not a second one written for omni.
//
// Zig has no closures, so a subject is a function pointer plus data, and the
// allocator a subject needs cannot be captured. It is held here instead and
// set by makeRunner - the same shape omni's own test/run.zig uses.

const std = @import("std");
const omni = @import("omni");
const voxgig_struct = @import("voxgig-struct");

const Allocator = std.mem.Allocator;
const JsonValue = voxgig_struct.JsonValue;

pub const Json = omni.Json;
pub const Flags = omni.Flags;
pub const RunPack = omni.RunPack;

pub const NULLMARK = omni.NULLMARK;
pub const UNDEFMARK = omni.UNDEFMARK;
pub const EXISTSMARK = omni.EXISTSMARK;

pub const TEST_JSON_FILE = "../build/test/test.json";

/// The allocator subjects run against. Set by makeRunner; the Zig test runner
/// is single-threaded and runs one group at a time, so a module-level binding
/// is enough and is what omni's own consumer does.
var ALLOC: Allocator = undefined;

/// The corpus is run out of an arena, freed once per group, rather than out
/// of `std.testing.allocator`. Every value the runner builds - the parsed
/// spec, each cloned argument, every failure message - lives as long as the
/// group and is then dropped wholesale, which is what an arena is for. The
/// testing allocator would instead report each of those as a leak and fail
/// a group that passed. omni's own consumer makes the same choice.
var ARENA: std.heap.ArenaAllocator = undefined;
var ARENA_LIVE = false;

/// What a subject returns. A Zig error carries no payload and the corpus
/// matches on error TEXT, so a failing subject reports a message rather than
/// an error value.
pub const SubResult = union(enum) {
    ok: JsonValue,
    err: []const u8,

    pub fn val(v: JsonValue) SubResult {
        return .{ .ok = v };
    }

    pub fn fail(msg: []const u8) SubResult {
        return .{ .err = msg };
    }
};

/// A binding that cannot fail in the corpus's sense: its groups carry no
/// `err:` entries, so it answers with a value or nothing at all.
pub const ValFn = fn (Allocator, JsonValue) JsonValue;

/// A binding whose groups DO carry `err:` entries - `transform` and
/// `validate`, and only those two, across all 75 groups.
pub const ResFn = fn (Allocator, JsonValue) SubResult;

/// Build an omni.Subject from a value binding. `comptime f` is what stands
/// in for the closure Zig does not have: each instantiation gets its own
/// `call`, so the function to invoke is baked into the type rather than
/// carried in `data`.
pub fn sub(comptime f: ValFn) *const omni.Subject {
    const S = struct {
        fn wrapped(alloc: Allocator, val: JsonValue) SubResult {
            return SubResult.val(f(alloc, val));
        }
    };
    return subres(S.wrapped);
}

/// Build an omni.Subject from a binding that may report a message.
pub fn subres(comptime f: ResFn) *const omni.Subject {
    const S = struct {
        fn call(_: *const omni.Subject, args: []const omni.Json) omni.SubjectResult {
            const in: omni.Json = if (0 < args.len) args[0] else .null;
            const sv = voxgig_struct.fromStdJson(ALLOC, in) catch |e|
                return .{ .err = @errorName(e) };
            switch (f(ALLOC, sv)) {
                .err => |m| return .{ .err = m },
                .ok => |rv| {
                    const out = voxgig_struct.toStdJson(ALLOC, rv) catch |e|
                        return .{ .err = @errorName(e) };
                    return .{ .ok = out };
                },
            }
        }
        const instance = omni.Subject{ .call = call };
    };
    return &S.instance;
}

/// A subject that may REWRITE its arguments. `minor/setpath` and
/// `merge/integrity` asserts on `match.args`, and the bridge above is a COPY -
/// what a subject does to this port's nodes is invisible to omni unless the
/// arguments are handed back. See omni's SubjectArgs.
pub fn subargs(comptime f: ValFn) *const omni.SubjectArgs {
    const S = struct {
        fn call(_: *const omni.SubjectArgs, args: []const omni.Json) omni.SubjectArgsResult {
            const in: omni.Json = if (0 < args.len) args[0] else .null;
            const sv = voxgig_struct.fromStdJson(ALLOC, in) catch |e|
                return .{ .err = @errorName(e) };
            const rv = f(ALLOC, sv);
            const out = voxgig_struct.toStdJson(ALLOC, rv) catch |e|
                return .{ .err = @errorName(e) };
            // The subject mutates the node it was handed, so the argument to
            // report back is that same node re-read through the bridge.
            const back = voxgig_struct.toStdJson(ALLOC, sv) catch |e|
                return .{ .err = @errorName(e) };
            const list = ALLOC.alloc(omni.Json, 1) catch |e|
                return .{ .err = @errorName(e) };
            list[0] = back;
            return .{ .ok = .{ .args = list, .res = out } };
        }
        const instance = omni.SubjectArgs{ .call = call };
    };
    return &S.instance;
}

/// This port answers every group from the same set of bindings, so the
/// provider has no subject of its own: each group names its own.
const PROVIDER = omni.Provider{};

/// Load the corpus and resolve the `struct` section. One per test block, the
/// way the in-situ runner was used; each call drops the previous arena.
pub fn makeRunner() !omni.RunPack {
    if (ARENA_LIVE) {
        ARENA.deinit();
    }
    ARENA = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    ARENA_LIVE = true;
    ALLOC = ARENA.allocator();
    const runner = try omni.makeRunner(ALLOC, std.testing.io, TEST_JSON_FILE, &PROVIDER);
    return runner.runner("struct", null);
}

/// Run one group and turn omni's failure message into a test failure.
pub fn rungroup(
    pack: *const omni.RunPack,
    section: []const u8,
    name: []const u8,
    subject: *const omni.Subject,
    flags: omni.Flags,
) !void {
    const spec = groupspec(pack, section, name) orelse {
        std.debug.print("omni: no such group: {s}.{s}\n", .{ section, name });
        return error.NoSuchGroup;
    };
    if (try pack.runsetflags(spec, flags, subject)) |msg| {
        std.debug.print("{s}.{s}: {s}\n", .{ section, name, msg });
        return error.CorpusFailure;
    }
}

/// `rungroup` for a subject that rewrites its arguments.
pub fn rungroupargs(
    pack: *const omni.RunPack,
    section: []const u8,
    name: []const u8,
    subject: *const omni.SubjectArgs,
    flags: omni.Flags,
) !void {
    const spec = groupspec(pack, section, name) orelse {
        std.debug.print("omni: no such group: {s}.{s}\n", .{ section, name });
        return error.NoSuchGroup;
    };
    if (try pack.runsetflagsargs(spec, flags, subject)) |msg| {
        std.debug.print("{s}.{s}: {s}\n", .{ section, name, msg });
        return error.CorpusFailure;
    }
}

/// The corpus nests one level deeper than omni's own spec: `minor.isnode`
/// rather than `isnode`.
fn groupspec(pack: *const omni.RunPack, section: []const u8, name: []const u8) omni.Maybe {
    const sec = omni.jget(pack.spec, section) orelse return null;
    return omni.jget(sec, name);
}
