// The corpus runner is voxgig/omni. This file is the Zig bridge and subject factory.
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

var ALLOC: Allocator = undefined;
var ARENA: std.heap.ArenaAllocator = undefined;
var ARENA_LIVE = false;

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

pub const ValFn = fn (Allocator, JsonValue) JsonValue;
pub const ResFn = fn (Allocator, JsonValue) SubResult;

pub fn sub(comptime f: ValFn) *const omni.Subject {
    const S = struct {
        fn wrapped(alloc: Allocator, val: JsonValue) SubResult {
            return SubResult.val(f(alloc, val));
        }
    };
    return subres(S.wrapped);
}

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

pub fn subargs(comptime f: ValFn) *const omni.SubjectArgs {
    const S = struct {
        fn call(_: *const omni.SubjectArgs, args: []const omni.Json) omni.SubjectArgsResult {
            const in: omni.Json = if (0 < args.len) args[0] else .null;
            const sv = voxgig_struct.fromStdJson(ALLOC, in) catch |e|
                return .{ .err = @errorName(e) };
            const rv = f(ALLOC, sv);
            const out = voxgig_struct.toStdJson(ALLOC, rv) catch |e|
                return .{ .err = @errorName(e) };
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

const PROVIDER = omni.Provider{};

pub fn makeRunner() !omni.RunPack {
    if (ARENA_LIVE) ARENA.deinit();
    ARENA = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    ARENA_LIVE = true;
    ALLOC = ARENA.allocator();
    const runner = try omni.makeRunner(ALLOC, std.testing.io, TEST_JSON_FILE, &PROVIDER);
    return runner.runner("struct", null);
}

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

fn groupspec(pack: *const omni.RunPack, section: []const u8, name: []const u8) omni.Maybe {
    const sec = omni.jget(pack.spec, section) orelse return null;
    return omni.jget(sec, name);
}
