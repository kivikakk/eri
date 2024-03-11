const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn parse(allocator: Allocator, input: []const u8) !Doc {
    const tokens = try Token.allFromBuffer(allocator, input);
    defer {
        for (tokens) |token|
            token.deinit(allocator);
        allocator.free(tokens);
    }

    const forms = try Form.allFromTokens(allocator, tokens);
    errdefer {
        for (forms) |form|
            form.deinit(allocator);
        allocator.free(forms);
    }

    return Doc.fromForms(forms);
}

pub fn print(allocator: Allocator, formattable: anytype) ![]u8 {
    return try std.fmt.allocPrint(allocator, "{}", .{formattable});
}

fn expectRoundtrip(input0: []const u8) !void {
    const doc0 = try parse(std.testing.allocator, input0);
    defer doc0.deinit(std.testing.allocator);

    const input1 = try print(std.testing.allocator, doc0);
    defer std.testing.allocator.free(input1);

    const doc1 = try parse(std.testing.allocator, input1);
    defer doc1.deinit(std.testing.allocator);

    const input2 = try print(std.testing.allocator, doc1);
    defer std.testing.allocator.free(input2);

    try std.testing.expectEqualStrings(input1, input2);
}

test "parse" {
    try expectRoundtrip("(abc (def))");
    try expectRoundtrip("   123  8 \n\t  x");
    try expectRoundtrip("((((((((((((((((((((((()))))))))))))))))))))))");
}

pub const Loc = usize;

pub const Doc = struct {
    const Self = @This();

    forms: []Form,

    pub fn fromForms(forms: []Form) Self {
        return Self{
            .forms = forms,
        };
    }

    pub fn format(self: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        for (self.forms) |form| {
            try form.format(fmt, options, writer);
            try writer.writeByte('\n');
        }
    }

    pub fn deinit(self: Self, alloc: Allocator) void {
        for (self.forms) |form| {
            form.deinit(alloc);
        }
        alloc.free(self.forms);
    }
};

pub const Form = struct {
    const Self = @This();

    const Error = error{
        Unexpected,
    } || Allocator.Error;

    pub const Value = union(enum) {
        number: u64,
        label: []const u8,
        list: []const Self,
    };

    value: Value,
    start: Loc,
    end: Loc,

    fn nextFromTokens(allocator: Allocator, tokens: []const Token) Error!struct {
        form: Self,
        consumed: usize,
    } {
        var state: union(enum) {
            initial,
            list: struct {
                start: Loc,
                forms: std.ArrayList(Self),
            },
        } = .initial;
        errdefer {
            switch (state) {
                .list => |list_state| {
                    for (list_state.forms.items) |f| f.deinit(allocator);
                    list_state.forms.deinit();
                },
                else => {},
            }
        }

        var consumed: usize = 0;
        var skip: usize = 0;

        const form = for (tokens, 0..) |token, i| {
            if (skip > 0) {
                skip -= 1;
                continue;
            }
            consumed = i + 1;

            switch (state) {
                .initial => switch (token.value) {
                    .number => |number| break Self.mk(.{ .number = number }, token.start, token.end),
                    .label => |label| break Self.mk(.{ .label = try allocator.dupe(u8, label) }, token.start, token.end),
                    .popen => state = .{ .list = .{
                        .start = token.start,
                        .forms = std.ArrayList(Self).init(allocator),
                    } },
                    else => return error.Unexpected,
                },
                .list => |*list_state| switch (token.value) {
                    .pclose => break Self.mk(.{ .list = try list_state.forms.toOwnedSlice() }, list_state.start, token.end),
                    else => {
                        const fc = try Self.nextFromTokens(allocator, tokens[i..]);
                        try list_state.forms.append(fc.form);
                        skip = fc.consumed - 1;
                    },
                },
            }
        } else return error.Unexpected;

        return .{
            .form = form,
            .consumed = consumed,
        };
    }

    fn allFromTokens(allocator: Allocator, tokens: []const Token) Error![]Self {
        var offset: usize = 0;

        var forms = std.ArrayList(Self).init(allocator);
        errdefer {
            for (forms.items) |form| form.deinit(allocator);
            forms.deinit();
        }

        while (offset < tokens.len) {
            const fc = try Self.nextFromTokens(allocator, tokens[offset..]);
            try forms.append(fc.form);
            offset += fc.consumed;
        }

        return try forms.toOwnedSlice();
    }

    fn mk(value: Value, start: Loc, end: Loc) Self {
        return Self{
            .value = value,
            .start = start,
            .end = end,
        };
    }

    pub fn format(self: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        switch (self.value) {
            .number => |number| try std.fmt.format(writer, "{}", .{number}),
            .label => |label| try writer.writeAll(label),
            .list => |forms| {
                try writer.writeByte('(');
                for (forms, 0..) |form, i| {
                    if (i > 0) try writer.writeByte(' ');
                    try form.format(fmt, options, writer);
                }
                try writer.writeByte(')');
            }
        }
    }

    pub fn deinit(self: Self, alloc: Allocator) void {
        switch (self.value) {
            .number => {},
            .label => |label| alloc.free(label),
            .list => |forms| {
                for (forms) |form|
                    form.deinit(alloc);
                alloc.free(forms);
            },
        }
    }
};

fn expectNextFromTokens(
    expectedForm: Form.Error!Form,
    expectedConsumed: usize,
    buffer: []const u8,
) !void {
    const tokens = try Token.allFromBuffer(std.testing.allocator, buffer);
    defer {
        for (tokens) |token|
            token.deinit(std.testing.allocator);
        std.testing.allocator.free(tokens);
    }

    const fce = Form.nextFromTokens(std.testing.allocator, tokens);
    defer {
        if (fce) |fc| fc.form.deinit(std.testing.allocator) else |_| {}
    }

    if (expectedForm) |expForm| {
        const fc = try fce;
        try std.testing.expectEqualDeep(expForm, fc.form);
        try std.testing.expectEqual(expectedConsumed, fc.consumed);
    } else |expErr| {
        try std.testing.expectError(expErr, fce);
    }
}

test "Form.nextFromTokens" {
    try expectNextFromTokens(Form.mk(.{ .number = 123 }, 0, 2), 1, "123");
    try expectNextFromTokens(Form.mk(.{ .label = "aroo" }, 1, 4), 1, " aroo ");
    try expectNextFromTokens(Form.mk(.{ .list = &.{} }, 1, 2), 2, " () ");
    try expectNextFromTokens(Form.mk(.{ .list = &.{
        Form.mk(.{ .label = "uwah" }, 1, 4),
    } }, 0, 5), 3, "(uwah)");
    try expectNextFromTokens(Form.mk(.{ .list = &.{
        Form.mk(.{ .label = "awa" }, 1, 3),
        Form.mk(.{ .list = &.{Form.mk(.{ .number = 123456 }, 6, 11)} }, 5, 12),
    } }, 0, 13), 6, "(awa (123456))");
    try expectNextFromTokens(error.Unexpected, 0, "(awa");
    try expectNextFromTokens(error.Unexpected, 0, ")");
}

fn expectAllFromTokens(
    expectedForms: []const Form,
    buffer: []const u8,
) !void {
    const tokens = try Token.allFromBuffer(std.testing.allocator, buffer);
    defer {
        for (tokens) |token|
            token.deinit(std.testing.allocator);
        std.testing.allocator.free(tokens);
    }

    const forms = try Form.allFromTokens(std.testing.allocator, tokens);
    defer {
        for (forms) |form|
            form.deinit(std.testing.allocator);
        std.testing.allocator.free(forms);
    }

    try std.testing.expectEqualDeep(expectedForms, forms);
}

test "Form.allFromTokens" {
    try expectAllFromTokens(&.{
        Form.mk(.{ .number = 123 }, 0, 2),
        Form.mk(.{ .number = 456 }, 4, 6),
    }, "123 456");
    try expectAllFromTokens(&.{}, "   ");
}

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

        pub fn format(self: Value, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = fmt;
            _ = options;

            switch (self) {
                .number => |n| try std.fmt.format(writer, "{}", .{n}),
                .label => |l| try writer.writeAll(l),
                .popen => try writer.writeAll("popen"),
                .pclose => try writer.writeAll("pclose"),
            }
        }
    };

    value: Value,

    start: Loc,
    end: Loc,

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

    fn mk(value: Value, start: Loc, end: Loc) Self {
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

    pub fn format(self: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;

        try std.fmt.format(writer, "({}-{}: {})", .{ self.start, self.end, self.value });
    }
};

fn expectNextFromBuffer(
    expectedValue: Token.Value,
    expectedStart: Loc,
    expectedEnd: Loc,
    buffer: []const u8,
    offset: usize,
) !void {
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

fn expectAllFromBuffer(expected: Token.Error![]const Token.Value, buffer: []const u8) !void {
    const tokense = Token.allFromBuffer(std.testing.allocator, buffer);
    defer {
        if (tokense) |tokens| {
            for (tokens) |token|
                token.deinit(std.testing.allocator);
            std.testing.allocator.free(tokens);
        } else |_| {}
    }

    if (expected) |expectedTokens| {
        for (expectedTokens, try tokense) |value, token| {
            try std.testing.expectEqualDeep(value, token.value);
        }
    } else |expectedError| {
        try std.testing.expectError(expectedError, tokense);
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

    try expectAllFromBuffer(error.Invalid, "(abc!");
}
