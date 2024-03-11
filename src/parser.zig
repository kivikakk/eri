const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Loc = struct {
    const Self = @This();

    line: usize = 1,
    column: usize = 0,

    fn mk(line: usize, column: usize) Self {
        return Self{ .line = line, .column = column };
    }

    fn left(self: Self) Self {
        std.debug.assert(self.column > 0);
        return .{ .line = self.line, .column = self.column - 1 };
    }

    fn right(self: Self) Self {
        return .{ .line = self.line, .column = self.column + 1 };
    }

    fn down(self: Self) Self {
        return .{ .line = self.line + 1, .column = 0 };
    }

    pub fn format(self: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;

        try std.fmt.format(writer, "{}:{}", .{ self.line, self.column });
    }
};

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

fn expectRoundtrip(allocator: Allocator, input0: []const u8) !void {
    const doc0 = try parse(allocator, input0);
    defer doc0.deinit(allocator);

    const input1 = try print(allocator, doc0);
    defer allocator.free(input1);

    const doc1 = try parse(allocator, input1);
    defer doc1.deinit(allocator);

    const input2 = try print(allocator, doc1);
    defer allocator.free(input2);

    try std.testing.expectEqualStrings(input1, input2);
}

fn roundtrips(allocator: Allocator) !void {
    try expectRoundtrip(allocator, "(abc (def))");
    try expectRoundtrip(allocator, "   123  8 \n\t  x");
    try expectRoundtrip(allocator, "((((((((((((((((((((((()))))))))))))))))))))))");
    try expectRoundtrip(allocator,
        \\ (x ; ... yeah )
        \\  y)
    );
}

test "parse" {
    try roundtrips(std.testing.allocator);
}

test "parse - exhaustive allocation failure check" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, roundtrips, .{});
}

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
        number: i64,
        label: []const u8,
        list: []const Self,
    };

    value: Value,
    start: Loc,
    end: Loc,

    const NextResult = struct {
        form: Self,
        consumed: usize,
    };

    fn nextFromTokens(allocator: Allocator, tokens: []const Token) Error!NextResult {
        var state: union(enum) {
            initial,
            list: struct {
                start: Loc,
                forms: std.ArrayListUnmanaged(Self),
            },
        } = .initial;
        errdefer {
            switch (state) {
                .list => |*list_state| {
                    for (list_state.forms.items) |form| form.deinit(allocator);
                    list_state.forms.deinit(allocator);
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
                        .forms = std.ArrayListUnmanaged(Self){},
                    } },
                    else => return error.Unexpected,
                },
                .list => |*list_state| switch (token.value) {
                    .pclose => break Self.mk(.{ .list = try list_state.forms.toOwnedSlice(allocator) }, list_state.start, token.end),
                    else => {
                        const next_result = try Self.nextFromTokens(allocator, tokens[i..]);
                        errdefer next_result.form.deinit(allocator);
                        try list_state.forms.append(allocator, next_result.form);
                        skip = next_result.consumed - 1;
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

        var forms = std.ArrayListUnmanaged(Self){};
        errdefer {
            for (forms.items) |form| form.deinit(allocator);
            forms.deinit(allocator);
        }

        while (offset < tokens.len) {
            const next_result = try Self.nextFromTokens(allocator, tokens[offset..]);
            errdefer next_result.form.deinit(allocator);
            try forms.append(allocator, next_result.form);
            offset += next_result.consumed;
        }

        return try forms.toOwnedSlice(allocator);
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
            },
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

    const form_err = Form.nextFromTokens(std.testing.allocator, tokens);
    defer {
        if (form_err) |next_result| next_result.form.deinit(std.testing.allocator) else |_| {}
    }

    if (expectedForm) |expForm| {
        const next_result = try form_err;
        try std.testing.expectEqualDeep(expForm, next_result.form);
        try std.testing.expectEqual(expectedConsumed, next_result.consumed);
    } else |expErr| {
        try std.testing.expectError(expErr, form_err);
    }
}

test "Form.nextFromTokens" {
    try expectNextFromTokens(Form.mk(.{ .number = 123 }, Loc.mk(1, 0), Loc.mk(1, 2)), 1, "123");
    try expectNextFromTokens(Form.mk(.{ .label = "aroo" }, Loc.mk(1, 1), Loc.mk(1, 4)), 1, " aroo ");
    try expectNextFromTokens(Form.mk(.{ .list = &.{} }, Loc.mk(1, 1), Loc.mk(1, 2)), 2, " () ");
    try expectNextFromTokens(Form.mk(.{ .list = &.{
        Form.mk(.{ .label = "uwah" }, Loc.mk(1, 1), Loc.mk(1, 4)),
    } }, Loc.mk(1, 0), Loc.mk(1, 5)), 3, "(uwah)");
    try expectNextFromTokens(Form.mk(.{ .list = &.{
        Form.mk(.{ .label = "awa" }, Loc.mk(1, 1), Loc.mk(1, 3)),
        Form.mk(.{ .list = &.{Form.mk(.{ .number = 123456 }, Loc.mk(1, 6), Loc.mk(1, 11))} }, Loc.mk(1, 5), Loc.mk(1, 12)),
    } }, Loc.mk(1, 0), Loc.mk(1, 13)), 6, "(awa (123456))");
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
        Form.mk(.{ .number = 123 }, Loc.mk(1, 0), Loc.mk(1, 2)),
        Form.mk(.{ .number = 456 }, Loc.mk(1, 4), Loc.mk(1, 6)),
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
        number: i64,
        label: []const u8,
        popen,
        pclose,

        pub fn format(self: Value, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = fmt;
            _ = options;

            switch (self) {
                .number => |n| try std.fmt.format(writer, "number {}", .{n}),
                .label => |l| try std.fmt.format(writer, "label {s}", .{l}),
                .popen => try writer.writeAll("popen"),
                .pclose => try writer.writeAll("pclose"),
            }
        }
    };

    value: Value,

    start: Loc,
    end: Loc,

    const NextResult = struct {
        token: Self,
        next_offset: usize,
        next_loc: Loc,
    };

    fn nextFromBuffer(allocator: Allocator, buffer: []const u8, offset: usize, start_loc: Loc) Error!NextResult {
        var state: union(enum) {
            initial,
            number: struct { usize, Loc },
            label: struct { usize, Loc },
            comment,
        } = .initial;
        var loc = start_loc;

        for (buffer[offset..], offset..) |c, i| {
            switch (state) {
                .initial => switch (c) {
                    ' ', '\r', '\n', '\t' => {},
                    '-', '0'...'9' => state = .{ .number = .{ i, loc } },
                    'a'...'z', 'A'...'Z' => state = .{ .label = .{ i, loc } },
                    '(' => return Self.mkResult(.popen, loc, loc, i + 1, loc.right()),
                    ')' => return Self.mkResult(.pclose, loc, loc, i + 1, loc.right()),
                    ';' => state = .comment,
                    else => return error.Invalid,
                },
                .number => |s| switch (c) {
                    '0'...'9' => {},
                    else => return try Self.mkNumber(
                        buffer[s[0]..i],
                        s[1],
                        loc.left(),
                        i,
                        loc,
                    ),
                },
                .label => |s| switch (c) {
                    'a'...'z', 'A'...'Z' => {},
                    else => return try Self.mkLabel(
                        allocator,
                        buffer[s[0]..i],
                        s[1],
                        loc.left(),
                        i,
                        loc,
                    ),
                },
                .comment => switch (c) {
                    '\n' => state = .initial,
                    else => {},
                },
            }

            loc = if (c == '\n') loc.down() else loc.right();
        }

        return switch (state) {
            .initial, .comment => error.Empty,
            .number => |s| try Self.mkNumber(
                buffer[s[0]..],
                s[1],
                loc.left(),
                buffer.len,
                loc,
            ),
            .label => |s| try Self.mkLabel(
                allocator,
                buffer[s[0]..],
                s[1],
                loc.left(),
                buffer.len,
                loc,
            ),
        };
    }

    fn allFromBuffer(allocator: Allocator, buffer: []const u8) Error![]Self {
        var offset: usize = 0;
        var loc: Loc = .{};

        var tokens = std.ArrayListUnmanaged(Self){};
        errdefer {
            for (tokens.items) |token| token.deinit(allocator);
            tokens.deinit(allocator);
        }

        while (true) {
            const result = Self.nextFromBuffer(allocator, buffer, offset, loc) catch |err| switch (err) {
                error.Empty => break,
                else => return err,
            };
            try tokens.append(allocator, result.token);
            offset = result.next_offset;
            loc = result.next_loc;
        }

        return try tokens.toOwnedSlice(allocator);
    }

    fn mk(value: Value, start: Loc, end: Loc) Self {
        return Self{ .value = value, .start = start, .end = end };
    }

    fn mkResult(value: Value, start: Loc, end: Loc, next_offset: usize, next_loc: Loc) NextResult {
        return .{
            .token = Self.mk(value, start, end),
            .next_offset = next_offset,
            .next_loc = next_loc,
        };
    }

    fn mkNumber(
        number_string: []const u8,
        start: Loc,
        end: Loc,
        next_offset: usize,
        next_loc: Loc,
    ) Error!NextResult {
        const number = std.fmt.parseInt(i64, number_string, 10) catch return error.Invalid;
        return Self.mkResult(.{ .number = number }, start, end, next_offset, next_loc);
    }

    fn mkLabel(
        allocator: Allocator,
        label: []const u8,
        start: Loc,
        end: Loc,
        next_offset: usize,
        next_loc: Loc,
    ) Error!NextResult {
        return Self.mkResult(.{ .label = try allocator.dupe(u8, label) }, start, end, next_offset, next_loc);
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
    loc: Loc,
) !void {
    const result = try Token.nextFromBuffer(std.testing.allocator, buffer, offset, loc);
    defer result.token.deinit(std.testing.allocator);
    try std.testing.expectEqualDeep(Token.mk(expectedValue, expectedStart, expectedEnd), result.token);
}

test "Token.nextFromBuffer" {
    try expectNextFromBuffer(.{ .number = 123 }, Loc.mk(1, 0), Loc.mk(1, 2), "123", 0, .{});
    try expectNextFromBuffer(.{ .number = 123 }, Loc.mk(1, 2), Loc.mk(1, 4), "  123 ", 1, .{ .column = 1 });
    try expectNextFromBuffer(.popen, Loc.mk(1, 0), Loc.mk(1, 0), "(", 0, .{});
    try expectNextFromBuffer(.pclose, Loc.mk(2, 1), Loc.mk(2, 1), "\t\n )", 1, .{ .column = 1 });
    try expectNextFromBuffer(.{ .label = "awawa" }, Loc.mk(1, 1), Loc.mk(1, 5), " awawa", 0, .{});
}

fn expectAllFromBuffer(expected: Token.Error![]const Token, buffer: []const u8) !void {
    const tokens_err = Token.allFromBuffer(std.testing.allocator, buffer);
    defer {
        if (tokens_err) |tokens| {
            for (tokens) |token|
                token.deinit(std.testing.allocator);
            std.testing.allocator.free(tokens);
        } else |_| {}
    }

    if (expected) |expectedTokens| {
        try std.testing.expectEqualDeep(expectedTokens, try tokens_err);
    } else |expectedError| {
        try std.testing.expectError(expectedError, tokens_err);
    }
}

test "Token.allFromBuffer" {
    try expectAllFromBuffer(&.{
        Token.mk(.popen, Loc.mk(1, 0), Loc.mk(1, 0)),
        Token.mk(.{ .label = "awa" }, Loc.mk(1, 1), Loc.mk(1, 3)),
        Token.mk(.popen, Loc.mk(1, 5), Loc.mk(1, 5)),
        Token.mk(.{ .number = -123_456 }, Loc.mk(1, 6), Loc.mk(1, 12)),
        Token.mk(.pclose, Loc.mk(1, 13), Loc.mk(1, 13)),
        Token.mk(.pclose, Loc.mk(1, 14), Loc.mk(1, 14)),
    }, "(awa (-123456))");

    try expectAllFromBuffer(error.Invalid, "(abc!");
}
