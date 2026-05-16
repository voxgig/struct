// Copyright (c) 2025-2026 Voxgig Ltd. MIT LICENSE.
//
// Voxgig Struct — RE2-subset regex engine, pure Zig, no third-party deps.
//
// Direct port of c/src/regex.c (Thompson NFA via two state sets) and
// rs/src/re.rs. The public surface in struct.zig only needs compile +
// isMatch; this module provides those plus a Captures helper for the
// inevitable future where the engine is reused for replace / find_all
// at the API boundary.
//
// Dialect mirrors c/src/regex.h:
//   . anchors ^ $ . groups (...) (?:...) (?P<name>...) (names ignored)
//   . classes [abc] [^abc] [a-z]   predefined \d \D \s \S \w \W
//   . quantifiers * + ? {n} {n,} {n,m}   plus lazy *? +? ?? {..}?
//   . word boundary \b \B   . alternation a|b
//   . NOT supported: backref, lookaround, possessive, atomic.

const std = @import("std");

const MAX_GROUPS: usize = 16;

const Op = enum {
    char_op,
    any_op,
    class_op,
    match_op,
    jmp_op,
    split_op,
    save_op,
    bol_op,
    eol_op,
    wb_op,
    nwb_op,
};

const CharClass = struct {
    bits: [32]u8 = [_]u8{0} ** 32,

    fn set(self: *CharClass, c: u8) void {
        self.bits[c >> 3] |= @as(u8, 1) << @intCast(c & 7);
    }

    fn setRange(self: *CharClass, lo: u8, hi: u8) void {
        const a: u8 = if (lo > hi) hi else lo;
        const b: u8 = if (lo > hi) lo else hi;
        var c = a;
        while (true) : (c += 1) {
            self.set(c);
            if (c == b) break;
        }
    }

    fn has(self: CharClass, c: u8) bool {
        return (self.bits[c >> 3] >> @intCast(c & 7)) & 1 == 1;
    }

    fn negate(self: *CharClass) void {
        for (&self.bits) |*b| b.* = ~b.*;
    }

    fn predef(self: *CharClass, c: u8) void {
        switch (c) {
            'd' => self.setRange('0', '9'),
            'D' => {
                self.setRange(0, 255);
                var x: u8 = '0';
                while (x <= '9') : (x += 1) self.bits[x >> 3] &= ~(@as(u8, 1) << @intCast(x & 7));
            },
            's' => {
                self.set(' ');
                self.set('\t');
                self.set('\n');
                self.set('\r');
                self.set(0x0C);
                self.set(0x0B);
            },
            'S' => {
                self.setRange(0, 255);
                self.bits[' ' >> 3] &= ~(@as(u8, 1) << (' ' & 7));
                self.bits['\t' >> 3] &= ~(@as(u8, 1) << ('\t' & 7));
                self.bits['\n' >> 3] &= ~(@as(u8, 1) << ('\n' & 7));
                self.bits['\r' >> 3] &= ~(@as(u8, 1) << ('\r' & 7));
                self.bits[0x0C >> 3] &= ~(@as(u8, 1) << (0x0C & 7));
                self.bits[0x0B >> 3] &= ~(@as(u8, 1) << (0x0B & 7));
            },
            'w' => {
                self.setRange('0', '9');
                self.setRange('A', 'Z');
                self.setRange('a', 'z');
                self.set('_');
            },
            'W' => {
                self.setRange(0, 255);
                var x: u8 = '0';
                while (x <= '9') : (x += 1) self.bits[x >> 3] &= ~(@as(u8, 1) << @intCast(x & 7));
                x = 'A';
                while (x <= 'Z') : (x += 1) self.bits[x >> 3] &= ~(@as(u8, 1) << @intCast(x & 7));
                x = 'a';
                while (x <= 'z') : (x += 1) self.bits[x >> 3] &= ~(@as(u8, 1) << @intCast(x & 7));
                self.bits['_' >> 3] &= ~(@as(u8, 1) << ('_' & 7));
            },
            else => {},
        }
    }
};

const Insn = struct {
    op: Op,
    // Op-specific operands (union by field).
    c: u8 = 0, // char_op
    slot: usize = 0, // save_op
    jmp_t: i32 = 0, // jmp_op
    split_x: i32 = 0, // split_op
    split_y: i32 = 0, // split_op
    cc: CharClass = .{},
};

pub const Regex = struct {
    allocator: std.mem.Allocator,
    code: []Insn,
    ngroups: usize,
    anchored_start: bool,

    pub fn deinit(self: *Regex) void {
        self.allocator.free(self.code);
    }

    pub fn isMatch(self: Regex, input: []const u8) bool {
        if (self.findFirst(input)) |slots| {
            self.allocator.free(slots);
            return true;
        }
        return false;
    }

    pub fn findFirst(self: Regex, input: []const u8) ?[]i32 {
        var start: usize = 0;
        while (true) {
            if (self.matchAt(input, start)) |slots| return slots;
            if (self.anchored_start) return null;
            if (start > input.len) return null;
            start += 1;
        }
    }

    pub fn findFrom(self: Regex, input: []const u8, from: usize) ?[]i32 {
        var start: usize = from;
        while (true) {
            if (self.matchAt(input, start)) |slots| return slots;
            if (self.anchored_start) return null;
            if (start > input.len) return null;
            start += 1;
        }
    }

    fn matchAt(self: Regex, input: []const u8, start: usize) ?[]i32 {
        const nslots = self.ngroups * 2;
        var cur = ThreadList.init(self.allocator, self.code.len) catch return null;
        defer cur.deinit();
        var nxt = ThreadList.init(self.allocator, self.code.len) catch return null;
        defer nxt.deinit();
        const init_slots = self.allocator.alloc(i32, nslots) catch return null;
        defer self.allocator.free(init_slots);
        for (init_slots) |*s| s.* = -1;
        cur.gen = 1;
        cur.add(&self, input, 0, init_slots, start) catch return null;

        var best: ?[]i32 = null;
        errdefer if (best) |b| self.allocator.free(b);
        var sp = start;
        while (cur.threads.items.len > 0) {
            nxt.reset();
            const c: i32 = if (sp < input.len) @intCast(input[sp]) else -1;
            var done = false;
            for (cur.threads.items) |th| {
                const insn = self.code[th.pc];
                switch (insn.op) {
                    .char_op => {
                        if (c == @as(i32, insn.c)) {
                            nxt.add(&self, input, th.pc + 1, th.slots, sp + 1) catch {};
                        }
                    },
                    .any_op => {
                        if (c >= 0 and c != '\n') {
                            nxt.add(&self, input, th.pc + 1, th.slots, sp + 1) catch {};
                        }
                    },
                    .class_op => {
                        if (c >= 0 and insn.cc.has(@intCast(c))) {
                            nxt.add(&self, input, th.pc + 1, th.slots, sp + 1) catch {};
                        }
                    },
                    .match_op => {
                        if (best) |b| self.allocator.free(b);
                        best = self.allocator.dupe(i32, th.slots) catch null;
                        done = true;
                        break;
                    },
                    else => {},
                }
                if (done) break;
            }
            std.mem.swap(ThreadList, &cur, &nxt);
            sp += 1;
            if (cur.threads.items.len == 0) break;
        }
        // Drain remaining cur threads at EOI.
        for (cur.threads.items) |th| {
            if (self.code[th.pc].op == .match_op) {
                if (best) |b| self.allocator.free(b);
                best = self.allocator.dupe(i32, th.slots) catch null;
                break;
            }
        }
        return best;
    }
};

// ---------- ThreadList ----------

const Thread = struct {
    pc: usize,
    slots: []i32,
};

const ThreadList = struct {
    allocator: std.mem.Allocator,
    threads: std.ArrayList(Thread),
    visited: []u32,
    gen: u32 = 0,

    fn init(allocator: std.mem.Allocator, code_len: usize) !ThreadList {
        const v = try allocator.alloc(u32, code_len);
        @memset(v, 0);
        return .{
            .allocator = allocator,
            .threads = std.ArrayList(Thread).init(allocator),
            .visited = v,
            .gen = 0,
        };
    }

    fn deinit(self: *ThreadList) void {
        for (self.threads.items) |th| self.allocator.free(th.slots);
        self.threads.deinit();
        self.allocator.free(self.visited);
    }

    fn reset(self: *ThreadList) void {
        for (self.threads.items) |th| self.allocator.free(th.slots);
        self.threads.clearRetainingCapacity();
        self.gen +%= 1;
        if (self.gen == 0) {
            @memset(self.visited, 0);
            self.gen = 1;
        }
    }

    fn add(self: *ThreadList, re: *const Regex, input: []const u8, pc: usize, slots: []const i32, sp: usize) !void {
        if (pc >= re.code.len) return;
        if (self.visited[pc] == self.gen) return;
        self.visited[pc] = self.gen;
        const insn = re.code[pc];
        switch (insn.op) {
            .jmp_op => return self.add(re, input, @intCast(insn.jmp_t), slots, sp),
            .split_op => {
                try self.add(re, input, @intCast(insn.split_x), slots, sp);
                return self.add(re, input, @intCast(insn.split_y), slots, sp);
            },
            .save_op => {
                const ns = try self.allocator.alloc(i32, slots.len);
                @memcpy(ns, slots);
                ns[insn.slot] = @intCast(sp);
                defer self.allocator.free(ns);
                return self.add(re, input, pc + 1, ns, sp);
            },
            .bol_op => {
                if (sp == 0 or (sp > 0 and sp - 1 < input.len and input[sp - 1] == '\n')) {
                    return self.add(re, input, pc + 1, slots, sp);
                }
                return;
            },
            .eol_op => {
                if (sp >= input.len or input[sp] == '\n') {
                    return self.add(re, input, pc + 1, slots, sp);
                }
                return;
            },
            .wb_op, .nwb_op => {
                const left = sp > 0 and sp - 1 < input.len and isWord(input[sp - 1]);
                const right = sp < input.len and isWord(input[sp]);
                const at_boundary = left != right;
                const want = insn.op == .wb_op;
                if (at_boundary == want) return self.add(re, input, pc + 1, slots, sp);
                return;
            },
            else => {},
        }
        const ns = try self.allocator.alloc(i32, slots.len);
        @memcpy(ns, slots);
        try self.threads.append(.{ .pc = pc, .slots = ns });
    }
};

fn isWord(c: u8) bool {
    return (c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z') or (c >= '0' and c <= '9') or c == '_';
}

// ---------- Parser / Compiler ----------

const Parser = struct {
    allocator: std.mem.Allocator,
    src: []const u8,
    pos: usize = 0,
    next_group: usize = 1,
    code: std.ArrayList(Insn),
    err: ?[]const u8 = null,

    fn init(allocator: std.mem.Allocator, src: []const u8) Parser {
        return .{
            .allocator = allocator,
            .src = src,
            .code = std.ArrayList(Insn).init(allocator),
        };
    }

    fn emit(self: *Parser, op: Op) std.mem.Allocator.Error!usize {
        const ix = self.code.items.len;
        try self.code.append(.{ .op = op });
        return ix;
    }

    fn perror(self: *Parser, msg: []const u8) void {
        if (self.err == null) self.err = msg;
    }

    // Returns (byte, predef_letter, kind) — kind 0=byte, 1=predef class, 2=\b/\B.
    fn parseEscape(self: *Parser) struct { b: u8, p: u8, k: u8 } {
        if (self.pos >= self.src.len) {
            self.perror("trailing backslash");
            return .{ .b = 0, .p = 0, .k = 0 };
        }
        const c = self.src[self.pos];
        self.pos += 1;
        return switch (c) {
            'n' => .{ .b = '\n', .p = 0, .k = 0 },
            't' => .{ .b = '\t', .p = 0, .k = 0 },
            'r' => .{ .b = '\r', .p = 0, .k = 0 },
            'f' => .{ .b = 0x0C, .p = 0, .k = 0 },
            'v' => .{ .b = 0x0B, .p = 0, .k = 0 },
            '0' => .{ .b = 0, .p = 0, .k = 0 },
            'a' => .{ .b = 0x07, .p = 0, .k = 0 },
            'e' => .{ .b = 27, .p = 0, .k = 0 },
            'x' => blk: {
                if (self.pos + 1 >= self.src.len) {
                    self.perror("bad \\xNN");
                    break :blk .{ .b = 0, .p = 0, .k = 0 };
                }
                const h1 = hexval(self.src[self.pos]);
                const h2 = hexval(self.src[self.pos + 1]);
                if (h1 < 0 or h2 < 0) {
                    self.perror("bad \\xNN");
                    break :blk .{ .b = 0, .p = 0, .k = 0 };
                }
                self.pos += 2;
                break :blk .{ .b = @intCast(((h1 << 4) | h2) & 0xFF), .p = 0, .k = 0 };
            },
            'd', 'D', 's', 'S', 'w', 'W' => .{ .b = 0, .p = c, .k = 1 },
            'b', 'B' => .{ .b = 0, .p = c, .k = 2 },
            else => .{ .b = c, .p = 0, .k = 0 },
        };
    }

    fn parseClass(self: *Parser) CharClass {
        var out: CharClass = .{};
        var neg = false;
        if (self.pos < self.src.len and self.src[self.pos] == '^') {
            neg = true;
            self.pos += 1;
        }
        var first = true;
        while (self.pos < self.src.len and (first or self.src[self.pos] != ']')) : (first = false) {
            var c: u8 = 0;
            if (self.src[self.pos] == '\\') {
                self.pos += 1;
                const e = self.parseEscape();
                if (e.k == 1) {
                    var sub: CharClass = .{};
                    sub.predef(e.p);
                    for (&out.bits, sub.bits) |*o, s| o.* |= s;
                    continue;
                }
                c = if (e.k == 2) 8 else e.b;
            } else {
                c = self.src[self.pos];
                self.pos += 1;
            }
            if (self.pos + 1 < self.src.len and self.src[self.pos] == '-' and self.src[self.pos + 1] != ']') {
                self.pos += 1;
                var hi: u8 = 0;
                if (self.src[self.pos] == '\\') {
                    self.pos += 1;
                    const e = self.parseEscape();
                    hi = if (e.k == 0) e.b else '-';
                } else {
                    hi = self.src[self.pos];
                    self.pos += 1;
                }
                out.setRange(c, hi);
            } else {
                out.set(c);
            }
        }
        if (self.pos >= self.src.len or self.src[self.pos] != ']') {
            self.perror("unclosed [");
            return out;
        }
        self.pos += 1;
        if (neg) out.negate();
        return out;
    }

    fn parseAtom(self: *Parser) std.mem.Allocator.Error!usize {
        if (self.pos >= self.src.len) return self.code.items.len;
        const start = self.code.items.len;
        const c = self.src[self.pos];
        if (c == '(') {
            self.pos += 1;
            var capture = true;
            if (self.pos + 1 < self.src.len and self.src[self.pos] == '?' and self.src[self.pos + 1] == ':') {
                capture = false;
                self.pos += 2;
            } else if (self.pos + 2 < self.src.len and self.src[self.pos] == '?' and self.src[self.pos + 1] == 'P' and self.src[self.pos + 2] == '<') {
                self.pos += 3;
                while (self.pos < self.src.len and self.src[self.pos] != '>') self.pos += 1;
                if (self.pos < self.src.len) self.pos += 1;
            }
            var group: usize = 0;
            if (capture) {
                group = self.next_group;
                self.next_group += 1;
                const ix = try self.emit(.save_op);
                self.code.items[ix].slot = group * 2;
            }
            _ = try self.parseAlt();
            if (self.pos >= self.src.len or self.src[self.pos] != ')') {
                self.perror("unclosed (");
                return start;
            }
            self.pos += 1;
            if (capture) {
                const ix = try self.emit(.save_op);
                self.code.items[ix].slot = group * 2 + 1;
            }
        } else if (c == '[') {
            self.pos += 1;
            const cc = self.parseClass();
            const ix = try self.emit(.class_op);
            self.code.items[ix].cc = cc;
        } else if (c == '.') {
            self.pos += 1;
            _ = try self.emit(.any_op);
        } else if (c == '^') {
            self.pos += 1;
            _ = try self.emit(.bol_op);
        } else if (c == '$') {
            self.pos += 1;
            _ = try self.emit(.eol_op);
        } else if (c == '\\') {
            self.pos += 1;
            const e = self.parseEscape();
            switch (e.k) {
                1 => {
                    var cc: CharClass = .{};
                    cc.predef(e.p);
                    const ix = try self.emit(.class_op);
                    self.code.items[ix].cc = cc;
                },
                2 => {
                    _ = try self.emit(if (e.p == 'b') .wb_op else .nwb_op);
                },
                else => {
                    const ix = try self.emit(.char_op);
                    self.code.items[ix].c = e.b;
                },
            }
        } else if (c == ')' or c == '|') {
            return start;
        } else {
            self.pos += 1;
            const ix = try self.emit(.char_op);
            self.code.items[ix].c = c;
        }
        return start;
    }

    fn codeClone(self: *Parser, from: usize, to: usize) std.mem.Allocator.Error!usize {
        const delta: i32 = @intCast(@as(i64, @intCast(self.code.items.len)) - @as(i64, @intCast(from)));
        const start = self.code.items.len;
        var i = from;
        while (i < to) : (i += 1) {
            var insn = self.code.items[i];
            switch (insn.op) {
                .jmp_op => {
                    const t = insn.jmp_t;
                    if (@as(usize, @intCast(t)) >= from and @as(usize, @intCast(t)) < to) insn.jmp_t = t + delta;
                },
                .split_op => {
                    const x = insn.split_x;
                    const y = insn.split_y;
                    if (@as(usize, @intCast(x)) >= from and @as(usize, @intCast(x)) < to) insn.split_x = x + delta;
                    if (@as(usize, @intCast(y)) >= from and @as(usize, @intCast(y)) < to) insn.split_y = y + delta;
                },
                else => {},
            }
            try self.code.append(insn);
        }
        return start;
    }

    fn shiftTargetsAfter(self: *Parser, from: usize, by: i32) void {
        var i = from + 1;
        while (i < self.code.items.len) : (i += 1) {
            switch (self.code.items[i].op) {
                .jmp_op => {
                    if (@as(usize, @intCast(self.code.items[i].jmp_t)) >= from) self.code.items[i].jmp_t += by;
                },
                .split_op => {
                    if (@as(usize, @intCast(self.code.items[i].split_x)) >= from) self.code.items[i].split_x += by;
                    if (@as(usize, @intCast(self.code.items[i].split_y)) >= from) self.code.items[i].split_y += by;
                },
                else => {},
            }
        }
    }

    fn applyQuant(self: *Parser, start: usize, q: u8, n_lo: i32, n_hi: i32, lazy: bool) std.mem.Allocator.Error!void {
        const end = self.code.items.len;
        const alen = end - start;
        if (alen == 0) return;
        switch (q) {
            '?' => {
                // Split before atom, falling through after.
                try self.code.insert(start, .{ .op = .split_op });
                const after = self.code.items.len;
                const to_atom: i32 = @intCast(start + 1);
                self.code.items[start].split_x = if (lazy) @intCast(after) else to_atom;
                self.code.items[start].split_y = if (lazy) to_atom else @intCast(after);
                self.shiftTargetsAfter(start, 1);
            },
            '*' => {
                try self.code.insert(start, .{ .op = .split_op });
                self.shiftTargetsAfter(start, 1);
                _ = try self.emit(.jmp_op);
                const jmp_ix = self.code.items.len - 1;
                self.code.items[jmp_ix].jmp_t = @intCast(start);
                const exit_ix: i32 = @intCast(self.code.items.len);
                const to_atom: i32 = @intCast(start + 1);
                self.code.items[start].split_x = if (lazy) exit_ix else to_atom;
                self.code.items[start].split_y = if (lazy) to_atom else exit_ix;
            },
            '+' => {
                _ = try self.emit(.split_op);
                const s_ix = self.code.items.len - 1;
                const after: i32 = @intCast(self.code.items.len);
                self.code.items[s_ix].split_x = if (lazy) after else @intCast(start);
                self.code.items[s_ix].split_y = if (lazy) @intCast(start) else after;
            },
            '{' => {
                var k: i32 = 1;
                while (k < n_lo) : (k += 1) _ = try self.codeClone(start, end);
                if (n_hi == -1) {
                    const split_ix = try self.emit(.split_op);
                    const atom_start = self.code.items.len;
                    _ = try self.codeClone(start, end);
                    const jmp_ix = try self.emit(.jmp_op);
                    self.code.items[jmp_ix].jmp_t = @intCast(split_ix);
                    const exit_pc: i32 = @intCast(self.code.items.len);
                    self.code.items[split_ix].split_x = if (lazy) exit_pc else @intCast(atom_start);
                    self.code.items[split_ix].split_y = if (lazy) @intCast(atom_start) else exit_pc;
                } else if (n_hi > n_lo) {
                    var i: i32 = 0;
                    while (i < n_hi - n_lo) : (i += 1) {
                        const sp = try self.emit(.split_op);
                        const clone_start = self.code.items.len;
                        _ = try self.codeClone(start, end);
                        const after: i32 = @intCast(self.code.items.len);
                        self.code.items[sp].split_x = if (lazy) after else @intCast(clone_start);
                        self.code.items[sp].split_y = if (lazy) @intCast(clone_start) else after;
                    }
                }
            },
            else => {},
        }
    }

    fn parseConcat(self: *Parser) std.mem.Allocator.Error!usize {
        const start = self.code.items.len;
        while (self.pos < self.src.len and self.src[self.pos] != ')' and self.src[self.pos] != '|') {
            const atom_start = try self.parseAtom();
            if (self.err != null) return start;
            if (self.pos < self.src.len) {
                const q = self.src[self.pos];
                if (q == '*' or q == '+' or q == '?') {
                    self.pos += 1;
                    var lazy = false;
                    if (self.pos < self.src.len and self.src[self.pos] == '?') {
                        lazy = true;
                        self.pos += 1;
                    }
                    try self.applyQuant(atom_start, q, 0, 0, lazy);
                } else if (q == '{') {
                    const save = self.pos;
                    self.pos += 1;
                    var n_lo: i32 = 0;
                    var got_lo = false;
                    while (self.pos < self.src.len and isDigit(self.src[self.pos])) {
                        n_lo = n_lo * 10 + (self.src[self.pos] - '0');
                        got_lo = true;
                        self.pos += 1;
                    }
                    var n_hi: i32 = n_lo;
                    var open = false;
                    if (!got_lo) {
                        self.pos = save;
                    } else {
                        if (self.pos < self.src.len and self.src[self.pos] == ',') {
                            self.pos += 1;
                            n_hi = -1;
                            var hi: i32 = 0;
                            var got_hi = false;
                            while (self.pos < self.src.len and isDigit(self.src[self.pos])) {
                                hi = hi * 10 + (self.src[self.pos] - '0');
                                got_hi = true;
                                self.pos += 1;
                            }
                            if (got_hi) n_hi = hi else open = true;
                        }
                        if (self.pos < self.src.len and self.src[self.pos] == '}') {
                            self.pos += 1;
                            var lazy = false;
                            if (self.pos < self.src.len and self.src[self.pos] == '?') {
                                lazy = true;
                                self.pos += 1;
                            }
                            try self.applyQuant(atom_start, '{', n_lo, if (open) -1 else n_hi, lazy);
                        } else {
                            self.perror("bad {n,m}");
                        }
                    }
                }
            }
        }
        return start;
    }

    fn parseAlt(self: *Parser) std.mem.Allocator.Error!usize {
        const start = try self.parseConcat();
        if (self.err != null) return start;
        while (self.pos < self.src.len and self.src[self.pos] == '|') {
            _ = try self.emit(.jmp_op);
            const jmp_ix0 = self.code.items.len - 1;
            const branch2_start = self.code.items.len;
            try self.code.insert(start, .{ .op = .split_op });
            // Patch jumps inside the moved block.
            var i = start + 1;
            while (i < self.code.items.len) : (i += 1) {
                switch (self.code.items[i].op) {
                    .jmp_op => {
                        if (@as(usize, @intCast(self.code.items[i].jmp_t)) >= start) self.code.items[i].jmp_t += 1;
                    },
                    .split_op => {
                        if (@as(usize, @intCast(self.code.items[i].split_x)) >= start) self.code.items[i].split_x += 1;
                        if (@as(usize, @intCast(self.code.items[i].split_y)) >= start) self.code.items[i].split_y += 1;
                    },
                    else => {},
                }
            }
            self.code.items[start].split_x = @intCast(start + 1);
            self.code.items[start].split_y = @intCast(branch2_start + 1);
            const jmp_ix = jmp_ix0 + 1;
            self.pos += 1;
            _ = try self.parseConcat();
            self.code.items[jmp_ix].jmp_t = @intCast(self.code.items.len);
        }
        return start;
    }
};

fn hexval(c: u8) i32 {
    return switch (c) {
        '0'...'9' => @intCast(c - '0'),
        'a'...'f' => @intCast(c - 'a' + 10),
        'A'...'F' => @intCast(c - 'A' + 10),
        else => -1,
    };
}

fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}

// ---------- Public compile ----------

pub fn compile(allocator: std.mem.Allocator, pattern: []const u8) ?Regex {
    var p = Parser.init(allocator, pattern);
    defer p.code.deinit();
    // Wrap whole pattern in implicit group 0.
    p.code.append(.{ .op = .save_op, .slot = 0 }) catch return null;
    const anchored_start = pattern.len > 0 and pattern[0] == '^';
    _ = p.parseAlt() catch return null;
    if (p.err != null) return null;
    if (p.pos < pattern.len) return null;
    p.code.append(.{ .op = .save_op, .slot = 1 }) catch return null;
    p.code.append(.{ .op = .match_op }) catch return null;
    const owned = allocator.dupe(Insn, p.code.items) catch return null;
    return .{
        .allocator = allocator,
        .code = owned,
        .ngroups = p.next_group,
        .anchored_start = anchored_start,
    };
}

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "compile and match simple" {
    var r = compile(testing.allocator, "^hello$") orelse return error.CompileFailed;
    defer r.deinit();
    try testing.expect(r.isMatch("hello"));
    try testing.expect(!r.isMatch("hello world"));
}

test "alternation" {
    var r = compile(testing.allocator, "cat|dog") orelse return error.CompileFailed;
    defer r.deinit();
    try testing.expect(r.isMatch("cat"));
    try testing.expect(r.isMatch("dog"));
    try testing.expect(!r.isMatch("fish"));
}

test "quantifier {n,m}" {
    var r = compile(testing.allocator, "a{2,4}") orelse return error.CompileFailed;
    defer r.deinit();
    try testing.expect(r.isMatch("aa"));
    try testing.expect(r.isMatch("aaaa"));
    try testing.expect(!r.isMatch("a"));
}

test "predef class" {
    var r = compile(testing.allocator, "^\\d+$") orelse return error.CompileFailed;
    defer r.deinit();
    try testing.expect(r.isMatch("123"));
    try testing.expect(!r.isMatch("12a"));
}

test "word boundary" {
    var r = compile(testing.allocator, "\\bcat\\b") orelse return error.CompileFailed;
    defer r.deinit();
    try testing.expect(r.isMatch("the cat sat"));
    try testing.expect(!r.isMatch("category"));
}

test "greedy plus" {
    var r = compile(testing.allocator, "\\d+") orelse return error.CompileFailed;
    defer r.deinit();
    try testing.expect(r.isMatch("123"));
}

test "char class" {
    var r = compile(testing.allocator, "^[a-z]+$") orelse return error.CompileFailed;
    defer r.deinit();
    try testing.expect(r.isMatch("hello"));
    try testing.expect(!r.isMatch("Hello"));
}
