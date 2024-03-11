const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn parse(alloc: Allocator, input: []const u8) !Doc {
    _ = alloc;
    _ = input;

    unreachable;
}

pub const Doc = struct {
    const Self = @This();

    forms: []Form,

    pub fn fromForms(forms: []Form) Self {
        return Self{
            .forms = forms,
        };
    }

    pub fn deinit(self: *const Self, alloc: Allocator) void {
        for (self.forms) |*form| {
            form.deinit(alloc);
        }
        alloc.free(self.forms);
        alloc.destroy(self);
    }
};

pub const Form = union(enum) {
    const Self = @This();

    number: u64,
    label: []const u8,
    list: []Form,

    pub fn deinit(self: *const Self, alloc: Allocator) void {
        switch (self.*) {
            .number => |_| {},
            .label => |l| alloc.free(l),
            .list => |fs| {
                for (fs) |f| {
                    f.deinit(alloc);
                }
                alloc.free(fs);
            },
        }
        alloc.destroy(self);
    }
};

const Token = struct {
    const Self = @This();

    const Error = error{
        Empty,
        Invalid,
    } || Allocator.Error;

    const Value = union(enum) {
        number: u64,
        label: []const u8,
        popen,
        pclose,
    };

    value: Value,

    start: usize,
    end: usize,

    fn nextFromBuffer(allocator: Allocator, buffer: []const u8, offset: usize) Error!Self {
        var state: union(enum) {
            initial,
            number: usize,
            label: usize,
        } = .initial;

        for (buffer[offset..], offset..) |c, i| {
            switch (state) {
                .initial => switch (c) {
                    ' ', '\r', '\n', '\t' => {},
                    '0'...'9' => state = .{ .number = i },
                    'a'...'z', 'A'...'Z' => state = .{ .label = i },
                    '(' => return Self.mk(.popen, i, i),
                    ')' => return Self.mk(.pclose, i, i),
                    else => return error.Invalid,
                },
                .number => |s| switch (c) {
                    '0'...'9' => {},
                    else => return try Self.mkNumber(buffer, s, i - 1),
                },
                .label => |s| switch (c) {
                    'a'...'z', 'A'...'Z' => {},
                    else => return try Self.mkLabel(allocator, buffer, s, i - 1),
                },
            }
        }

        return switch (state) {
            .initial => error.Empty,
            .number => |s| try Self.mkNumber(buffer, s, buffer.len - 1),
            .label => |s| try Self.mkLabel(allocator, buffer, s, buffer.len - 1),
        };
    }

    fn allFromBuffer(allocator: Allocator, buffer: []const u8) Error![]Self {
        var offset: usize = 0;

        var tokens = std.ArrayList(Self).init(allocator);
        errdefer {
            for (tokens.items) |token| token.deinit(allocator);
            tokens.deinit();
        }

        while (true) {
            const token = Self.nextFromBuffer(allocator, buffer, offset) catch |err| switch (err) {
                error.Empty => break,
                else => return err,
            };
            try tokens.append(token);
            offset = token.end + 1;
        }

        return try tokens.toOwnedSlice();
    }

    fn mk(value: Value, start: usize, end: usize) Self {
        return Self{ .value = value, .start = start, .end = end };
    }

    fn mkNumber(buffer: []const u8, s: usize, i: usize) Error!Self {
        const number = std.fmt.parseInt(u64, buffer[s .. i + 1], 10) catch return error.Invalid;
        return Self.mk(.{ .number = number }, s, i);
    }

    fn mkLabel(allocator: Allocator, buffer: []const u8, s: usize, i: usize) Error!Self {
        const label = try allocator.dupe(u8, buffer[s .. i + 1]);
        return Self.mk(.{ .label = label }, s, i);
    }

    fn deinit(self: Self, allocator: Allocator) void {
        switch (self.value) {
            .label => |l| allocator.free(l),
            else => {},
        }
    }
};

fn expectNextFromBuffer(expectedValue: Token.Value, expectedStart: usize, expectedEnd: usize, buffer: []const u8, offset: usize) !void {
    const token = try Token.nextFromBuffer(std.testing.allocator, buffer, offset);
    defer token.deinit(std.testing.allocator);
    try std.testing.expectEqualDeep(Token.mk(expectedValue, expectedStart, expectedEnd), token);
}

test "Token.nextFromBuffer" {
    try expectNextFromBuffer(.{ .number = 123 }, 0, 2, "123", 0);
    try expectNextFromBuffer(.{ .number = 123 }, 2, 4, "  123 ", 1);
    try expectNextFromBuffer(.popen, 0, 0, "(", 0);
    try expectNextFromBuffer(.pclose, 2, 2, "\t\n)", 1);
    try expectNextFromBuffer(.{ .label = "awawa" }, 1, 5, " awawa", 0);
}

fn expectAllFromBuffer(expected: []const Token.Value, buffer: []const u8) !void {
    const tokens = try Token.allFromBuffer(std.testing.allocator, buffer);
    defer {
        for (tokens) |token|
            token.deinit(std.testing.allocator);
        std.testing.allocator.free(tokens);
    }


    for (expected, tokens) |value, token| {
        try std.testing.expectEqualDeep(value, token.value);
    }
}

test "Token.allFromBuffer" {
    try expectAllFromBuffer(&.{
        .popen,
        .{ .label = "awa" },
        .popen,
        .{ .number = 123_456 },
        .pclose,
        .pclose,
    }, "(awa (123456))");
}
