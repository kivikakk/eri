const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Document = union(enum) {
    Boolean: bool,
    Null,
    Number: i64,
    String: []u8,
    Interpolated: []Document,
    Bareword: []u8,
    Attrset: Attrset,
    Let: Let,

    pub fn eql(lhs: Document, rhs: Document) bool {
        return lhs.eqlDebug(rhs, false);
    }

    pub fn eqlDebug(lhs: Document, rhs: Document, comptime debug: bool) bool {
        return switch (lhs) {
            .Boolean => |lh| switch (rhs) {
                .Boolean => |rh| lh == rh,
                else => false,
            },
            .Null => switch (rhs) {
                .Null => true,
                else => false,
            },
            .Number => |lh| switch (rhs) {
                .Number => |rh| lh == rh,
                else => false,
            },
            .String => |lh| switch (rhs) {
                .String => |rh| std.mem.eql(u8, lh, rh),
                else => false,
            },
            .Interpolated => |lh| switch (rhs) {
                .Interpolated => |rh| {
                    if (lh.len != rh.len) return false;
                    var i: usize = 0;
                    while (i < lh.len) : (i += 1) {
                        if (!lh[i].eqlDebug(rh[i], debug)) return false;
                    }
                    return true;
                },
                else => false,
            },
            .Bareword => |lh| switch (rhs) {
                .Bareword => |rh| std.mem.eql(u8, lh, rh),
                else => false,
            },
            .Attrset => |lh| switch (rhs) {
                .Attrset => |rh| {
                    if (lh.rec != rh.rec) {
                        if (debug) std.debug.print("lh.rec {} != rh.rec {}\n", .{ lh.rec, rh.rec });
                        return false;
                    }
                    if (lh.pairs.len != rh.pairs.len) {
                        if (debug) std.debug.print("lh.pairs.len {} != rh.pairs.len {}\n", .{ lh.pairs.len, rh.pairs.len });
                        return false;
                    }
                    for (lh.pairs, 0..) |pair, i| {
                        if (!pair.eql(rh.pairs[i])) {
                            if (debug) std.debug.print("attrset index {d}: lh {} != rh {}\n", .{ i, pair, rh.pairs[i] });
                            return false;
                        }
                    }
                    return true;
                },
                else => false,
            },
            .Let => |lh| switch (rhs) {
                .Let => |rh| {
                    if (lh.pairs.len != rh.pairs.len) {
                        return false;
                    }
                    for (lh.pairs, 0..) |pair, i| {
                        if (!pair.eql(rh.pairs[i])) {
                            return false;
                        }
                    }
                    if (!lh.body.eqlDebug(rh.body.*, debug)) {
                        return false;
                    }
                    return true;
                },
                else => false,
            },
        };
    }

    pub fn format(self: Document, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        switch (self) {
            .Boolean => |b| try writer.print("{}", .{b}),
            .Null => try writer.print("null", .{}),
            .Number => |n| try writer.print("{d}", .{n}),
            .String => |s| try writer.print("\"{s}\"", .{s}), // XXX
            .Interpolated => |_| @panic("todo"), // XXX
            .Bareword => |w| try writer.print("{s}", .{w}),
            .Attrset => |*as| try as.format(fmt, options, writer),
            .Let => |l| try l.format(fmt, options, writer),
        }
    }

    pub fn deinit(self: Document, alloc: Allocator) void {
        switch (self) {
            .String, .Bareword => |s| alloc.free(s),
            .Interpolated => |ds| {
                for (ds) |d| d.deinit(alloc);
                alloc.free(ds);
            },
            .Attrset => |ar| ar.deinit(alloc),
            .Let => |l| l.deinit(alloc),
            else => {},
        }
    }
};
pub const DocumentTag = std.meta.Tag(Document);

pub const Pair = struct {
    path: [][]u8,
    value: Document,

    fn eql(lhs: Pair, rhs: Pair) bool {
        if (lhs.path.len != rhs.path.len) return false;
        for (lhs.path, 0..) |key, i| {
            if (!std.mem.eql(u8, key, rhs.path[i])) return false;
        }
        if (!lhs.value.eql(rhs.value)) return false;
        return true;
    }

    pub fn format(self: Pair, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;

        for (self.path, 0..) |key, i|
            try writer.print("{s}{s}", .{ if (i == 0) "" else ".", key });
        try writer.print(" = {}", .{self.value});
    }

    pub fn deinit(self: Pair, alloc: Allocator) void {
        for (self.path) |key| alloc.free(key);
        alloc.free(self.path);
        self.value.deinit(alloc);
    }
};

pub const Attrset = struct {
    rec: bool,
    pairs: []Pair,

    pub fn format(self: Attrset, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;

        if (self.rec) try writer.print("rec ", .{});
        if (self.pairs.len == 0) {
            try writer.print("{{}}", .{});
            return;
        }
        try writer.print("{{ ", .{});
        for (self.pairs) |pair| {
            try writer.print("{}; ", .{pair});
        }
        try writer.print("}}", .{});
    }

    fn deinit(self: Attrset, alloc: Allocator) void {
        for (self.pairs) |pair|
            pair.deinit(alloc);
        alloc.free(self.pairs);
    }
};

pub const Let = struct {
    pairs: []Pair,
    body: *const Document,

    pub fn format(self: Let, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;

        try writer.print("let ", .{});
        for (self.pairs) |pair|
            try writer.print("{}; ", .{pair});
        try writer.print("in {}", .{self.body.*});
    }

    fn deinit(self: Let, alloc: Allocator) void {
        for (self.pairs) |pair|
            pair.deinit(alloc);
        alloc.free(self.pairs);
        self.body.deinit(alloc);
        alloc.destroy(self.body);
    }
};
