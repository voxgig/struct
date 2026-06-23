// Test Provider (prototype) — Zig port of the canonical TypeScript
// implementation (../ts/provider.ts).
//
// Reads the shared corpus (build/test/test.json) and hands test code clean,
// normalized cases. It is NOT a test runner: it never calls the subject and
// never asserts. See ../PROVIDER.md for the model and ../AGENTS.md for usage.
//
// Zero runtime dependencies (Zig standard library only — std.json is stdlib),
// matching repo policy. Tested-against API: Zig 0.13.0, same as
// ../../../zig/test/runner.zig (std.json.parseFromSlice + std.json.Value).
//
// std.json.Value's `.object` is a std.json.ObjectMap, which is backed by an
// array hash map: it preserves *insertion order*, so iterating its keys yields
// corpus-faithful ordering for functions()/groups() without a side table (the
// Go port needs one only because encoding/json drops key order).

const std = @import("std");
const Allocator = std.mem.Allocator;
const Value = std.json.Value;
const ObjectMap = std.json.ObjectMap;

pub const NULLMARK = "__NULL__";
pub const UNDEFMARK = "__UNDEF__";
pub const EXISTSMARK = "__EXISTS__";

// Default corpus path, relative to this source file's directory
// (test/proto/zig). The runner is typically invoked from the proto/zig dir.
pub const DEFAULT_TEST_FILE = "../../../build/test/test.json";

pub const InputKind = enum { in, args, ctx };
pub const ExpectKind = enum { value, error_, match, absent };

// Tagged invocation: exactly one of in/args/ctx is meaningful, selected by
// `kind` (mirrors the runner's ctx -> args -> in precedence).
//
// `in` carries `null` for kind == .in when the raw entry has no "in" key
// (native null per §3). To distinguish "absent" from an explicit JSON null we
// keep `has_in`: when kind == .in and has_in is false, the corpus had no key.
pub const Input = struct {
    kind: InputKind,
    has_in: bool = false,
    in: ?Value = null,
    args: ?Value = null, // a JSON array value when kind == .args
    ctx: ?Value = null, // a JSON object value when kind == .ctx
};

// Parsed form of a raw `err` spec.
pub const ErrorCheck = struct {
    any: bool = false,
    text: ?[]const u8 = null,
    regex: bool = false,
};

// Tagged expectation: value | error | match | absent.
pub const Expect = struct {
    kind: ExpectKind,
    // kind == .value — expected result (may be literal JSON null). has_value
    // distinguishes a present-null `out` from an absent one.
    has_value: bool = false,
    value: ?Value = null,
    error_: ?ErrorCheck = null,
    // Populated whenever a `match` key is present (even alongside err/out).
    has_match: bool = false,
    match: ?Value = null,
};

// Normalized record for a single corpus test case.
pub const Entry = struct {
    function: []const u8,
    group: []const u8,
    index: usize,
    id: ?[]const u8,
    doc: bool,
    client: ?[]const u8,
    input: Input,
    expect: Expect,
    raw: Value,
};

// Outcome of a structural match.
pub const MatchResult = struct {
    ok: bool,
    path: ?[][]const u8 = null,
    expected: ?Value = null,
    actual: ?Value = null,
};

pub const TestProvider = struct {
    allocator: Allocator,
    parsed: std.json.Parsed(Value),
    file_data: []const u8,
    spec: Value,

    /// Parse test.json. Pass null for `testfile` to use the default corpus
    /// path (../../../build/test/test.json relative to this source's dir).
    pub fn load(allocator: Allocator, testfile: ?[]const u8) !TestProvider {
        const path = testfile orelse DEFAULT_TEST_FILE;
        const data = try std.fs.cwd().readFileAlloc(allocator, path, 64 * 1024 * 1024);
        const parsed = try std.json.parseFromSlice(Value, allocator, data, .{});
        return TestProvider{
            .allocator = allocator,
            .parsed = parsed,
            .file_data = data,
            .spec = parsed.value,
        };
    }

    pub fn deinit(self: *TestProvider) void {
        self.parsed.deinit();
        self.allocator.free(self.file_data);
    }

    /// The parsed test.json (escape hatch).
    pub fn raw(self: TestProvider) Value {
        return self.spec;
    }

    // spec.struct if present, else spec itself, as an object map.
    fn root(self: TestProvider) ?*const ObjectMap {
        if (self.spec != .object) return null;
        if (self.spec.object.getPtr("struct")) |s| {
            if (s.* == .object) return &s.object;
        }
        return &self.spec.object;
    }

    // The node for a function (under struct, falling back to root).
    fn fnNode(self: TestProvider, fn_name: []const u8) ?*const ObjectMap {
        if (self.spec != .object) return null;
        if (self.spec.object.getPtr("struct")) |s| {
            if (s.* == .object) {
                if (s.object.getPtr(fn_name)) |n| {
                    if (n.* == .object) return &n.object;
                }
            }
        }
        if (self.spec.object.getPtr(fn_name)) |n| {
            if (n.* == .object) return &n.object;
        }
        return null;
    }

    /// Function names in corpus (insertion) order. Caller owns the returned
    /// slice (allocated with `alloc`); the strings borrow the parsed JSON.
    pub fn functions(self: TestProvider, alloc: Allocator) ![][]const u8 {
        var out = std.ArrayList([]const u8).init(alloc);
        const r = self.root() orelse return out.toOwnedSlice();
        var it = r.iterator();
        while (it.next()) |kv| {
            const v = kv.value_ptr.*;
            if (isGroupBag(v) or hasGroups(v)) {
                try out.append(kv.key_ptr.*);
            }
        }
        return out.toOwnedSlice();
    }

    /// Group names for a function in corpus order. Caller owns the slice.
    pub fn groups(self: TestProvider, alloc: Allocator, fn_name: []const u8) ![][]const u8 {
        var out = std.ArrayList([]const u8).init(alloc);
        const node = self.fnNode(fn_name) orelse return out.toOwnedSlice();
        var it = node.iterator();
        while (it.next()) |kv| {
            const k = kv.key_ptr.*;
            if (!std.mem.eql(u8, k, "name") and isGroupBag(kv.value_ptr.*)) {
                try out.append(k);
            }
        }
        return out.toOwnedSlice();
    }

    /// All entries for a function across its groups. Caller owns the slice.
    pub fn entries(self: TestProvider, alloc: Allocator, fn_name: []const u8) ![]Entry {
        return self.entriesImpl(alloc, fn_name, null);
    }

    /// Entries for one specific group of a function. Caller owns the slice.
    pub fn entriesGroup(self: TestProvider, alloc: Allocator, fn_name: []const u8, group: []const u8) ![]Entry {
        return self.entriesImpl(alloc, fn_name, group);
    }

    fn entriesImpl(self: TestProvider, alloc: Allocator, fn_name: []const u8, group: ?[]const u8) ![]Entry {
        var out = std.ArrayList(Entry).init(alloc);
        const node = self.fnNode(fn_name) orelse return out.toOwnedSlice();

        const group_names = if (group) |g|
            try alloc.dupe([]const u8, &[_][]const u8{g})
        else
            try self.groups(alloc, fn_name);

        for (group_names) |g| {
            const bag_ptr = node.getPtr(g) orelse continue;
            const bag = bag_ptr.*;
            if (!isGroupBag(bag)) continue;
            const set = bag.object.get("set").?; // isGroupBag guarantees .set array
            const items = set.array.items;
            for (items, 0..) |raw_val, i| {
                try out.append(normalize(fn_name, g, i, raw_val));
            }
        }
        return out.toOwnedSlice();
    }
};

// A group bag is an object containing a `set` array.
fn isGroupBag(v: Value) bool {
    if (v != .object) return false;
    const set = v.object.get("set") orelse return false;
    return set == .array;
}

// A function node is an object with at least one child group bag.
fn hasGroups(v: Value) bool {
    if (v != .object) return false;
    var it = v.object.iterator();
    while (it.next()) |kv| {
        if (!std.mem.eql(u8, kv.key_ptr.*, "name") and isGroupBag(kv.value_ptr.*)) {
            return true;
        }
    }
    return false;
}

// KEY PRESENCE check (object.contains) — NOT a null-check. This is what makes
// `out: null` resolve to VALUE rather than ABSENT (§4).
fn has(obj: ObjectMap, key: []const u8) bool {
    return obj.contains(key);
}

fn normalize(fn_name: []const u8, group: []const u8, index: usize, raw_val: Value) Entry {
    // raw entries are always objects in the corpus; guard defensively.
    if (raw_val != .object) {
        return Entry{
            .function = fn_name,
            .group = group,
            .index = index,
            .id = null,
            .doc = false,
            .client = null,
            .input = Input{ .kind = .in, .has_in = false, .in = null },
            .expect = Expect{ .kind = .absent },
            .raw = raw_val,
        };
    }
    const obj = raw_val.object;

    var id: ?[]const u8 = null;
    if (obj.get("id")) |v| {
        if (v != .null) id = stringifyId(v);
    }
    var client: ?[]const u8 = null;
    if (obj.get("client")) |v| {
        if (v != .null) client = stringifyId(v);
    }
    const doc = if (obj.get("doc")) |v| (v == .bool and v.bool == true) else false;

    return Entry{
        .function = fn_name,
        .group = group,
        .index = index,
        .id = id,
        .doc = doc,
        .client = client,
        .input = resolveInput(obj),
        .expect = resolveExpect(obj),
        .raw = raw_val,
    };
}

// For id/client we only ever expect strings in the corpus; if not a string,
// fall back to the borrowed JSON string when present, else a literal label.
// (The TS port does String(raw.id); we keep the borrowed slice for strings.)
fn stringifyId(v: Value) ?[]const u8 {
    return switch (v) {
        .string => |s| s,
        .number_string => |s| s,
        else => null,
    };
}

fn resolveInput(obj: ObjectMap) Input {
    if (has(obj, "ctx")) {
        return Input{ .kind = .ctx, .ctx = obj.get("ctx").? };
    }
    if (has(obj, "args")) {
        return Input{ .kind = .args, .args = obj.get("args").? };
    }
    if (has(obj, "in")) {
        return Input{ .kind = .in, .has_in = true, .in = obj.get("in").? };
    }
    // No "in" key => native null.
    return Input{ .kind = .in, .has_in = false, .in = null };
}

fn parseErr(err: Value) ErrorCheck {
    switch (err) {
        .bool => |b| if (b) return ErrorCheck{ .any = true },
        .string => |s| {
            // "/re/" => regex; other string => literal substring text.
            if (s.len >= 3 and s[0] == '/' and s[s.len - 1] == '/') {
                return ErrorCheck{ .any = false, .text = s[1 .. s.len - 1], .regex = true };
            }
            return ErrorCheck{ .any = false, .text = s, .regex = false };
        },
        else => {},
    }
    // Non-true, non-string err spec: treat as "any error".
    return ErrorCheck{ .any = true };
}

fn resolveExpect(obj: ObjectMap) Expect {
    const has_match = has(obj, "match");
    const match_part: ?Value = if (has_match) obj.get("match").? else null;

    // 1. err -> ERROR
    if (has(obj, "err")) {
        return Expect{
            .kind = .error_,
            .error_ = parseErr(obj.get("err").?),
            .has_match = has_match,
            .match = match_part,
        };
    }
    // 2. out present (KEY PRESENCE, even if JSON null) -> VALUE
    if (has(obj, "out")) {
        return Expect{
            .kind = .value,
            .has_value = true,
            .value = obj.get("out").?,
            .has_match = has_match,
            .match = match_part,
        };
    }
    // 3. match -> MATCH
    if (has_match) {
        return Expect{ .kind = .match, .has_match = true, .match = match_part };
    }
    // 4. ABSENT
    return Expect{ .kind = .absent };
}

// ─── pure comparison helpers ───────────────────────────────────────────────

/// stringify(x) = x if it is already a string, else compact JSON.
/// Result is allocated with `alloc` (caller owns it) except the string case,
/// which borrows. Use `allocStringify` when you need a uniform owned buffer.
pub fn stringify(alloc: Allocator, x: Value) ![]const u8 {
    if (x == .string) return x.string;
    var buf = std.ArrayList(u8).init(alloc);
    errdefer buf.deinit();
    try std.json.stringify(x, .{}, buf.writer());
    return buf.toOwnedSlice();
}

fn normVal(x: Value) Value {
    // Collapse the "__NULL__" sentinel to a real null (mirrors normNull leaf).
    if (x == .string and std.mem.eql(u8, x.string, NULLMARK)) return Value{ .null = {} };
    return x;
}

/// Deep equality collapsing "__NULL__" (and absent, treated as null at leaves)
/// to null on both sides. Mirrors the runner's `flags.null == true` round-trip.
pub fn equal(expected: Value, actual: Value) bool {
    return deepEq(expected, actual, true);
}

/// Strict deep equality: only "__NULL__" is normalized to null; absent and
/// JSON null stay distinct (the runner's `null:false` functions). Within
/// std.json.Value both sides are already concrete, so the only difference from
/// `equal` is whether we further collapse — here we still normalize __NULL__.
pub fn equalStrict(expected: Value, actual: Value) bool {
    return deepEq(expected, actual, false);
}

// collapse_null: when true, a leaf null and a missing object key are treated
// equivalently. Both modes normalize the __NULL__ string sentinel.
fn deepEq(a_in: Value, b_in: Value, collapse_null: bool) bool {
    const a = normVal(a_in);
    const b = normVal(b_in);

    const TagType = std.meta.Tag(Value);
    const ta: TagType = a;
    const tb: TagType = b;

    // Numeric cross-type equality (integer vs float).
    if ((ta == .integer or ta == .float) and (tb == .integer or tb == .float)) {
        const fa: f64 = if (ta == .integer) @floatFromInt(a.integer) else a.float;
        const fb: f64 = if (tb == .integer) @floatFromInt(b.integer) else b.float;
        return fa == fb;
    }

    if (ta != tb) return false;

    return switch (a) {
        .null => true,
        .bool => |av| av == b.bool,
        .integer => |av| av == b.integer,
        .float => |av| av == b.float,
        .number_string => |av| std.mem.eql(u8, av, b.number_string),
        .string => |av| std.mem.eql(u8, av, b.string),
        .array => |av| {
            const bv = b.array;
            if (av.items.len != bv.items.len) return false;
            for (av.items, bv.items) |ai, bi| {
                if (!deepEq(ai, bi, collapse_null)) return false;
            }
            return true;
        },
        .object => |av| {
            const bv = b.object;
            if (collapse_null) {
                // Keys whose value is null on one side may be absent on the
                // other; compare on the union, treating absent as null.
                if (!objEqCollapse(av, bv)) return false;
                if (!objEqCollapse(bv, av)) return false;
                return true;
            }
            if (av.count() != bv.count()) return false;
            var it = av.iterator();
            while (it.next()) |kv| {
                const bval = bv.get(kv.key_ptr.*) orelse return false;
                if (!deepEq(kv.value_ptr.*, bval, collapse_null)) return false;
            }
            return true;
        },
    };
}

fn isNullish(v: Value) bool {
    if (v == .null) return true;
    if (v == .string and std.mem.eql(u8, v.string, NULLMARK)) return true;
    return false;
}

// Every key of `a` must equal the corresponding key of `b`, where a missing
// key in `b` counts as null (so null == absent under collapse semantics).
fn objEqCollapse(a: ObjectMap, b: ObjectMap) bool {
    var it = a.iterator();
    while (it.next()) |kv| {
        const av = kv.value_ptr.*;
        if (b.get(kv.key_ptr.*)) |bv| {
            if (!deepEq(av, bv, true)) return false;
        } else {
            // absent on the other side == null
            if (!isNullish(av)) return false;
        }
    }
    return true;
}

/// matchval(check, base): deep-equal (strict), then string rules:
///   "/re/"  => RegExp(re).test(stringify(base))
///   string  => stringify(base).toLowerCase() contains check.toLowerCase()
/// A "function" check is always true in TS; not representable here.
pub fn matchval(alloc: Allocator, check: Value, base: Value) bool {
    if (equalStrict(check, base)) return true;
    if (check == .string) {
        const basestr = stringify(alloc, base) catch return false;
        const cs = check.string;
        if (cs.len >= 3 and cs[0] == '/' and cs[cs.len - 1] == '/') {
            return regexTest(cs[1 .. cs.len - 1], basestr);
        }
        return containsCaseInsensitive(basestr, cs);
    }
    return false;
}

// Case-insensitive substring (ASCII). Mirrors
// stringify(base).toLowerCase().includes(check.toLowerCase()).
fn containsCaseInsensitive(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (needle.len > haystack.len) return false;
    var i: usize = 0;
    const last = haystack.len - needle.len;
    while (i <= last) : (i += 1) {
        var j: usize = 0;
        while (j < needle.len) : (j += 1) {
            if (std.ascii.toLower(haystack[i + j]) != std.ascii.toLower(needle[j])) break;
        }
        if (j == needle.len) return true;
    }
    return false;
}

/// errorMatches(check, message): any => true; regex => RegExp(text).test(msg);
/// else case-insensitive substring.
pub fn errorMatches(check: ErrorCheck, message: []const u8) bool {
    if (check.any) return true;
    const text = check.text orelse return false;
    if (check.regex) return regexTest(text, message);
    return containsCaseInsensitive(message, text);
}

// ── minimal regex matcher ──────────────────────────────────────────────────
//
// SIMPLIFICATION: the std library has no general regex engine. This is a tiny
// fallback supporting only unanchored literal substring matching (with `.` as
// any-char). It is sufficient for the corpus's "/re/" error checks, which are
// predominantly plain substrings. Patterns using real regex metacharacters
// (alternation, classes, quantifiers, anchors) are NOT fully supported and
// will degrade to a literal-ish scan. Documented here as a known limitation;
// the canonical TS/Go ports use their host regex engine.
fn regexTest(pattern: []const u8, text: []const u8) bool {
    // Fast path: if the pattern has no metacharacters, it's a substring test.
    var plain = true;
    for (pattern) |c| {
        switch (c) {
            '.', '*', '+', '?', '(', ')', '[', ']', '{', '}', '|', '^', '$', '\\' => {
                plain = false;
                break;
            },
            else => {},
        }
    }
    if (plain) return std.mem.indexOf(u8, text, pattern) != null;
    return regexMatchAnywhere(pattern, text);
}

// `.`-aware unanchored matcher: tries to match `pattern` (with `.` = any char)
// as a contiguous run starting at each position. Other metacharacters are
// treated literally (best effort).
fn regexMatchAnywhere(pattern: []const u8, text: []const u8) bool {
    const anchored_start = pattern.len > 0 and pattern[0] == '^';
    const pat = if (anchored_start) pattern[1..] else pattern;
    if (anchored_start) return regexMatchAt(pat, text, 0);
    if (text.len < pat.len) {
        // still allow empty pattern
        if (pat.len == 0) return true;
        return false;
    }
    var i: usize = 0;
    while (i + pat.len <= text.len) : (i += 1) {
        if (regexMatchAt(pat, text, i)) return true;
    }
    return false;
}

fn regexMatchAt(pat: []const u8, text: []const u8, start: usize) bool {
    var anchored_end = false;
    var p = pat;
    if (p.len > 0 and p[p.len - 1] == '$') {
        anchored_end = true;
        p = p[0 .. p.len - 1];
    }
    if (start + p.len > text.len) return false;
    var k: usize = 0;
    while (k < p.len) : (k += 1) {
        if (p[k] == '.') continue;
        if (p[k] != text[start + k]) return false;
    }
    if (anchored_end and start + p.len != text.len) return false;
    return true;
}

// ── structural match ────────────────────────────────────────────────────────

/// structMatch(check, base): every leaf of `check` must match `base` at its
/// path. equal leaf => ok; __UNDEF__ => require absent; __EXISTS__ => require
/// present; else fall back to matchval. First failure returns its path + both
/// values. Allocations (the failing path, scratch strings) use `alloc`.
pub fn structMatch(alloc: Allocator, check: Value, base: Value) MatchResult {
    var result = MatchResult{ .ok = true };
    var path = std.ArrayList([]const u8).init(alloc);
    defer path.deinit();
    walkLeaves(alloc, check, &path, base, &result);
    return result;
}

fn walkLeaves(
    alloc: Allocator,
    node: Value,
    path: *std.ArrayList([]const u8),
    base: Value,
    result: *MatchResult,
) void {
    if (!result.ok) return;
    switch (node) {
        .array => |arr| {
            for (arr.items, 0..) |child, i| {
                var buf: [24]u8 = undefined;
                const seg = std.fmt.bufPrint(&buf, "{d}", .{i}) catch "?";
                // Duplicate so the segment survives buf going out of scope.
                const owned = alloc.dupe(u8, seg) catch return;
                path.append(owned) catch return;
                walkLeaves(alloc, child, path, base, result);
                _ = path.pop();
                if (!result.ok) return;
            }
        },
        .object => |obj| {
            var it = obj.iterator();
            while (it.next()) |kv| {
                path.append(kv.key_ptr.*) catch return;
                walkLeaves(alloc, kv.value_ptr.*, path, base, result);
                _ = path.pop();
                if (!result.ok) return;
            }
        },
        else => {
            checkLeaf(alloc, node, path.items, base, result);
        },
    }
}

fn checkLeaf(
    alloc: Allocator,
    val: Value,
    path: []const []const u8,
    base: Value,
    result: *MatchResult,
) void {
    const found = getpath(base, path);
    const baseval: Value = found orelse Value{ .null = {} };

    // equal leaf (strict) => ok
    if (found != null and equalStrict(val, baseval)) return;

    // __UNDEF__ => require absent
    if (val == .string and std.mem.eql(u8, val.string, UNDEFMARK)) {
        if (found == null or baseval == .null) return;
    }
    // __EXISTS__ => require present (and non-null)
    if (val == .string and std.mem.eql(u8, val.string, EXISTSMARK)) {
        if (found != null and baseval != .null) return;
    }
    if (!matchval(alloc, val, baseval)) {
        // Record a stable copy of the failing path.
        const owned = alloc.alloc([]const u8, path.len) catch {
            result.* = MatchResult{ .ok = false, .expected = val, .actual = if (found != null) baseval else null };
            return;
        };
        std.mem.copyForwards([]const u8, owned, path);
        result.* = MatchResult{
            .ok = false,
            .path = owned,
            .expected = val,
            .actual = if (found != null) baseval else null,
        };
    }
}

// Descend `store` following string path segments. Returns null if it runs off
// a null/missing key or an out-of-range/non-numeric array index.
fn getpath(store: Value, path: []const []const u8) ?Value {
    var cur = store;
    for (path) |key| {
        switch (cur) {
            .object => |obj| {
                cur = obj.get(key) orelse return null;
            },
            .array => |arr| {
                const idx = std.fmt.parseInt(usize, key, 10) catch return null;
                if (idx >= arr.items.len) return null;
                cur = arr.items[idx];
            },
            else => return null,
        }
    }
    return cur;
}
