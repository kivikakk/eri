const std = @import("std");
const Allocator = std.mem.Allocator;
const rtlil = @import("rtlil.zig");
const common = @import("common.zig");

pub fn parse(comptime T: type, allocator: Allocator, buffer: []const u8) Parser.Error!T {
    var parser = Parser.mk(allocator, buffer);
    return switch (T) {
        rtlil.Doc => .{ .modules = try parser.parse() },
        rtlil.Cell => try parser.parseCell("kind", "name", &.{}),
        else => @compileError("no parse() for " ++ @typeName(T)),
    };
}

const Parser = struct {
    const Self = @This();

    pub const Error = error{
        Empty,
        Invalid,
    } || Allocator.Error;

    allocator: Allocator,
    line_it: std.mem.TokenIterator(u8, .scalar),

    fn mk(allocator: Allocator, buffer: []const u8) Self {
        return Self{
            .allocator = allocator,
            .line_it = std.mem.tokenizeScalar(u8, buffer, '\n'),
        };
    }

    fn parse(self: *Self) Error![]rtlil.Module {
        var modules = std.ArrayListUnmanaged(rtlil.Module){};

        var attributes = std.ArrayListUnmanaged(rtlil.Attribute){};
        var name: ?[]const u8 = null;
        var module_attributes: []rtlil.Attribute = &.{};
        var wires = std.ArrayListUnmanaged(rtlil.Wire){};
        var memories = std.ArrayListUnmanaged(rtlil.Memory){};
        var connects = std.ArrayListUnmanaged(rtlil.Connection){};
        var cells = std.ArrayListUnmanaged(rtlil.Cell){};

        errdefer {
            common.deinit(self.allocator, &modules);
            common.deinit(self.allocator, &attributes);
            common.deinit(self.allocator, module_attributes);
            if (name) |n|
                self.allocator.free(n);
            common.deinit(self.allocator, &wires);
            common.deinit(self.allocator, &memories);
            common.deinit(self.allocator, &connects);
            common.deinit(self.allocator, &cells);
        }

        while (true) {
            const line = try self.parseLine();
            errdefer line.deinit(self.allocator);

            switch (line) {
                .attribute => |props| {
                    try attributes.append(self.allocator, .{
                        .name = props.name,
                        .value = props.value,
                    });
                },
                .module => |props| {
                    name = props.name;
                    module_attributes = try attributes.toOwnedSlice(self.allocator);
                },
                .wire => |props| {
                    std.debug.assert(attributes.items.len == 0);
                    try wires.append(self.allocator, .{
                        .width = props.width,
                        .spec = props.spec,
                        .name = props.name,
                    });
                },
                .memory => |props| {
                    const memory_attributes = try attributes.toOwnedSlice(self.allocator);
                    errdefer common.deinit(self.allocator, memory_attributes);
                    try memories.append(self.allocator, .{
                        .attributes = memory_attributes,
                        .width = props.width,
                        .size = props.size,
                        .name = props.name,
                    });
                },
                .connect => |props| {
                    std.debug.assert(attributes.items.len == 0);
                    try connects.append(self.allocator, .{
                        .name = props.name,
                        .target = props.target,
                    });
                },
                .cell => |props| {
                    const cell_attributes = try attributes.toOwnedSlice(self.allocator);
                    errdefer common.deinit(self.allocator, cell_attributes);
                    // XXX errdefer and cell_attributes ownership isn't right.
                    const cell = try self.parseCell(props.kind, props.name, cell_attributes);
                    errdefer cell.deinit(self.allocator);
                    try cells.append(self.allocator, cell);
                },
                else => std.debug.panic("unexpected while parsing module: .{}\n", .{line}),
            }
        }

        std.debug.assert(attributes.items.len == 0);
        std.debug.assert(name == null);
        std.debug.assert(module_attributes.items.len == 0);
        std.debug.assert(wires.items.len == 0);
        std.debug.assert(memories.items.len == 0);
        std.debug.assert(connects.items.len == 0);
        std.debug.assert(cells.items.len == 0);

        return modules;
    }

    fn parseCell(
        self: *Self,
        kind: []const u8,
        name: []const u8,
        attributes: []const rtlil.Attribute,
    ) Error!rtlil.Cell {
        var parameters = std.ArrayListUnmanaged(rtlil.Parameter){};
        var connects = std.ArrayListUnmanaged(rtlil.Connection){};

        errdefer {
            common.deinit(self.allocator, parameters);
            common.deinit(self.allocator, connects);
        }

        while (true) {
            const line = try self.parseLine();
            errdefer line.deinit(self.allocator);

            switch (line) {
                .parameter => |props| try parameters.append(self.allocator, .{
                    .name = props.name,
                    .value = props.value,
                }),
                .connect => |props| try connects.append(self.allocator, .{
                    .name = props.name,
                    .target = props.target,
                }),
                .end => {
                    const o_parameters = try parameters.toOwnedSlice(self.allocator);
                    errdefer common.deinit(self.allocator, parameters);
                    const o_connects = try connects.toOwnedSlice(self.allocator);

                    return .{
                        .attributes = attributes,
                        .kind = kind,
                        .name = name,
                        .parameters = o_parameters,
                        .connections = o_connects,
                    };
                },
                else => std.debug.panic("unexpected while parsing cell: .{}\n", .{line}),
            }
        }
    }

    fn parseLine(self: *Self) Error!Line {
        const next = self.line_it.next() orelse return error.Empty;
        return try Line.parse(self.allocator, next);
    }
};

const Line = union(enum) {
    const Self = @This();

    // TODO: big overlap with rtlil, but not always exactly.
    attribute: struct { name: []const u8, value: rtlil.Value },
    module: struct { name: []const u8 },
    memory: struct { width: usize, size: usize, name: []const u8 },
    wire: struct { width: usize, spec: ?rtlil.Wire.Spec, name: []const u8 },
    connect: struct { name: []const u8, target: rtlil.RValue },
    cell: struct { kind: []const u8, name: []const u8 },
    parameter: struct { name: []const u8, value: rtlil.Value },
    end,

    fn deinit(self: Self, allocator: Allocator) void {
        switch (self) {
            inline .attribute, .parameter => |props| {
                allocator.free(props.name);
                props.value.deinit(allocator);
            },
            inline .module, .memory, .wire => |props| allocator.free(props.name),
            .connect => |props| {
                allocator.free(props.name);
                props.target.deinit(allocator);
            },
            .cell => |props| {
                allocator.free(props.kind);
                allocator.free(props.name);
            },
            .end => {},
        }
    }

    fn parse(allocator: Allocator, line: []const u8) Parser.Error!Self {
        const tokens = try Token.allFromBuffer(allocator, line);
        defer common.deinit(allocator, tokens);

        std.debug.print("handling: \"{s}\" ({any})\n", .{ line, tokens });

        std.debug.assert(tokens.len > 0);
        const kind = tokens[0].bareword;

        if (std.mem.eql(u8, kind, "attribute")) {
            std.debug.assert(tokens.len == 3);
            const name = try allocator.dupe(u8, tokens[1].bareword);
            errdefer allocator.free(name);
            const value: rtlil.Value = try Self.parseValue(allocator, tokens[2]);
            return .{ .attribute = .{ .name = name, .value = value } };
        } else if (std.mem.eql(u8, kind, "module")) {
            std.debug.assert(tokens.len == 2);
            return .{ .module = .{ .name = try allocator.dupe(u8, tokens[1].bareword) } };
        } else if (std.mem.eql(u8, kind, "memory")) {
            std.debug.assert(tokens.len == 6);
            std.debug.assert(std.mem.eql(u8, tokens[1].bareword, "width"));
            const width: usize = @intCast(tokens[2].number);
            std.debug.assert(std.mem.eql(u8, tokens[3].bareword, "size"));
            const size: usize = @intCast(tokens[4].number);
            return .{ .memory = .{
                .name = try allocator.dupe(u8, tokens[5].bareword),
                .width = width,
                .size = size,
            } };
        } else if (std.mem.eql(u8, kind, "wire")) {
            std.debug.assert(tokens.len == 4 or tokens.len == 6);
            std.debug.assert(std.mem.eql(u8, tokens[1].bareword, "width"));
            const width: usize = @intCast(tokens[2].number);
            const spec: ?rtlil.Wire.Spec = spec: {
                if (tokens.len == 4)
                    break :spec null;
                const dir: rtlil.Wire.Spec.Dir = dir: {
                    inline for (@typeInfo(rtlil.Wire.Spec.Dir).Enum.fields) |f|
                        if (std.mem.eql(u8, tokens[3].bareword, f.name))
                            break :dir @enumFromInt(f.value);
                    std.debug.panic("bad wire spec direction: {s}\n", .{tokens[3].bareword});
                };
                break :spec .{ .dir = dir, .index = @intCast(tokens[4].number) };
            };
            return .{ .wire = .{
                .name = try allocator.dupe(u8, tokens[tokens.len - 1].bareword),
                .width = width,
                .spec = spec,
            } };
        } else if (std.mem.eql(u8, kind, "connect")) {
            return Self.parseConnect(allocator, tokens);
        } else if (std.mem.eql(u8, kind, "cell")) {
            std.debug.assert(tokens.len == 3);
            const cell_kind = try allocator.dupe(u8, tokens[1].bareword);
            errdefer allocator.free(cell_kind);
            const name = try allocator.dupe(u8, tokens[2].bareword);
            return .{ .cell = .{ .kind = cell_kind, .name = name } };
        } else if (std.mem.eql(u8, kind, "parameter")) {
            std.debug.assert(tokens.len == 3);
            const name = try allocator.dupe(u8, tokens[1].bareword);
            errdefer allocator.free(name);
            const value: rtlil.Value = try Self.parseValue(allocator, tokens[2]);
            return .{ .parameter = .{ .name = name, .value = value } };
        } else if (std.mem.eql(u8, kind, "end")) {
            return .end;
        } else {
            std.debug.panic("unhandled rtlil keyword: {s}\n", .{kind});
        }

        unreachable;
    }

    fn parseValue(allocator: Allocator, value: Token) Parser.Error!rtlil.Value {
        return switch (value) {
            .number => |number| .{ .number = number },
            .string => |string| .{ .string = try allocator.dupe(u8, string) },
            else => @panic("unhandled attribute value type"),
        };
    }

    fn parseConnect(allocator: Allocator, tokens: []Token) Parser.Error!Self {
        std.debug.assert(tokens.len == 3 or tokens.len == 4);
        const name = try allocator.dupe(u8, tokens[1].bareword);
        errdefer allocator.free(name);
        const target: rtlil.RValue = rvalue: {
            switch (tokens[2]) {
                .bareword => |bareword| {
                    // m h trailing range, m n
                    const rname = try allocator.dupe(u8, bareword);
                    const range = range: {
                        if (tokens.len == 3)
                            break :range null;
                        break :range tokens[3].range;
                    };
                    break :rvalue .{ .signal = .{ .name = rname, .range = range } };
                },
                .bv => |bv| {
                    std.debug.assert(tokens.len == 3);
                    break :rvalue .{ .constant = bv };
                },
                .copen => {
                    @panic("big todo"); // TODO
                },
                else => std.debug.panic("unhandled rtlil rvalue: {}\n", .{tokens[2]}),
            }
        };
        return .{ .connect = .{
            .name = name,
            .target = target,
        } };
    }
};

const Token = union(enum) {
    const Self = @This();

    const Error = error{
        Empty,
        Invalid,
    } || Allocator.Error;

    number: i64,
    bareword: []const u8,
    string: []const u8,
    range: rtlil.Range,
    bv: rtlil.Bitvector,
    copen,
    cclose,

    const NextResult = struct {
        token: Self,
        next_offset: usize,
    };

    fn nextFromBuffer(allocator: Allocator, buffer: []const u8, offset: usize) Error!NextResult {
        var state: union(enum) {
            initial,
            number: usize,
            bareword: usize,
            string: usize,
            range_open: usize,
            range_upper: usize,
            range_lower: usize,
            bv: usize,
        } = .initial;

        for (buffer[offset..], offset..) |c, i| {
            switch (state) {
                .initial => switch (c) {
                    ' ', '\t', '\r' => {},
                    '-', '0'...'9' => state = .{ .number = i },
                    'a'...'z', 'A'...'Z', '$', '\\' => state = .{ .bareword = i },
                    '"' => state = .{ .string = i },
                    '[' => state = .{ .range_open = i },
                    else => return error.Invalid,
                },
                .number => |s| switch (c) {
                    '0'...'9' => {},
                    ' ' => return try Self.mkNumber(buffer[s..i], i),
                    '\'' => state = .{ .bv = s },
                    else => return error.Invalid,
                },
                .bareword => |s| switch (c) {
                    'a'...'z', 'A'...'Z', '0'...'9', '_', '$' => {},
                    ' ' => return try Self.mkBareword(allocator, buffer[s..i], i),
                    else => return error.Invalid,
                },
                .string => |s| switch (c) {
                    '"' => return try Self.mkString(allocator, buffer[s + 1 .. i], i + 1),
                    '\\' => return error.Invalid, // XXX escapes (if any?) unhandled
                    else => {},
                },
                .range_open => |s| switch (c) {
                    '0'...'9' => state = .{ .range_upper = s },
                    else => return error.Invalid,
                },
                .range_upper => |s| switch (c) {
                    '0'...'9' => {},
                    ':' => state = .{ .range_lower = s },
                    ']' => return try Self.mkRange(buffer[s + 1 .. i], i + 1),
                    else => return error.Invalid,
                },
                .range_lower => |s| switch (c) {
                    '0'...'9' => {},
                    ']' => return try Self.mkRange(buffer[s + 1 .. i], i + 1),
                    else => return error.Invalid,
                },
                .bv => |s| switch (c) {
                    '0', '1' => {}, // TODO: -, any others?
                    ' ' => return try Self.mkBv(allocator, buffer[s..i], i),
                    else => return error.Invalid,
                },
            }
        }

        return switch (state) {
            .initial => error.Empty,
            .number => |s| return try Self.mkNumber(buffer[s..], buffer.len),
            .bareword => |s| return try Self.mkBareword(allocator, buffer[s..], buffer.len),
            .string => {
                std.debug.print("buffer[offset..]: \"{s}\"\n", .{buffer[offset..]});
                return error.Invalid; // unterminated
            },
            .bv => |s| return try Self.mkBv(allocator, buffer[s..], buffer.len),
            else => unreachable,
        };
    }

    fn allFromBuffer(allocator: Allocator, buffer: []const u8) Error![]Self {
        var offset: usize = 0;

        var tokens = std.ArrayListUnmanaged(Self){};
        errdefer common.deinit(allocator, &tokens);

        while (true) {
            var result = Self.nextFromBuffer(allocator, buffer, offset) catch |err| switch (err) {
                error.Empty => break,
                else => return err,
            };
            {
                errdefer result.token.deinit(allocator);
                try tokens.append(allocator, result.token);
            }
            offset = result.next_offset;
        }

        return try tokens.toOwnedSlice(allocator);
    }

    fn mkNumber(number_string: []const u8, next_offset: usize) Error!NextResult {
        const number = std.fmt.parseInt(i64, number_string, 10) catch return error.Invalid;
        return .{ .token = .{ .number = number }, .next_offset = next_offset };
    }

    fn mkBareword(allocator: Allocator, slice: []const u8, next_offset: usize) Error!NextResult {
        const bareword = try allocator.dupe(u8, slice);
        return .{ .token = .{ .bareword = bareword }, .next_offset = next_offset };
    }

    fn mkString(allocator: Allocator, slice: []const u8, next_offset: usize) Error!NextResult {
        const string = try allocator.dupe(u8, slice);
        return .{ .token = .{ .string = string }, .next_offset = next_offset };
    }

    fn mkRange(slice: []const u8, next_offset: usize) Error!NextResult {
        var it = std.mem.tokenizeScalar(u8, slice, ':');
        const upper_s = it.next().?;
        const lower_s = it.next();
        std.debug.assert(it.next() == null);

        const upper = std.fmt.parseInt(usize, upper_s, 10) catch return error.Invalid;
        const lower = if (lower_s) |s| std.fmt.parseInt(usize, s, 10) catch return error.Invalid else upper;

        return .{
            .token = .{ .range = .{ .upper = upper, .lower = lower } },
            .next_offset = next_offset,
        };
    }

    fn mkBv(allocator: Allocator, slice: []const u8, next_offset: usize) Error!NextResult {
        var it = std.mem.tokenizeScalar(u8, slice, '\'');
        const len_s = it.next().?;
        const bs = it.next().?;
        std.debug.assert(it.next() == null);
        const len = std.fmt.parseInt(usize, len_s, 10) catch return error.Invalid;
        std.debug.assert(bs.len == len);
        var bits = try allocator.alloc(u1, len);
        for (bs, 0..) |bit, i| {
            bits[bits.len - i - 1] = if (bit == '1') 1 else 0;
        }
        return .{
            .token = .{ .bv = .{ .bits = bits } },
            .next_offset = next_offset,
        };
    }

    pub fn deinit(self: *Self, allocator: Allocator) void {
        switch (self.*) {
            .number => {},
            .bareword => |bareword| allocator.free(bareword),
            .string => |string| allocator.free(string),
            .range => {},
            .bv => |bv| bv.deinit(allocator),
            .copen, .cclose => {},
        }
    }

    pub fn format(self: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;

        switch (self) {
            .number => |number| try std.fmt.format(writer, "(number {})", .{number}),
            .bareword => |bareword| try std.fmt.format(writer, "(bareword {s})", .{bareword}),
            .string => |string| try std.fmt.format(writer, "(string \"{s}\")", .{string}),
            .range => |range| try std.fmt.format(writer, "(range {})", .{range}),
            .bv => |bv| try std.fmt.format(writer, "(bv {})", .{bv}),
            .copen => try writer.writeAll("copen"),
            .cclose => try writer.writeAll("cclose"),
        }
    }
};

fn expectNextFromBuffer(
    expectedToken: Token,
    buffer: []const u8,
    offset: usize,
) !void {
    var result = try Token.nextFromBuffer(std.testing.allocator, buffer, offset);
    defer result.token.deinit(std.testing.allocator);
    try std.testing.expectEqualDeep(expectedToken, result.token);
}

test "Token.nextFromBuffer" {
    try expectNextFromBuffer(.{ .number = 123 }, "123", 0);
    try expectNextFromBuffer(.{ .number = 123 }, "  123 ", 1);
    try expectNextFromBuffer(.{ .bareword = "awawa" }, " awawa", 0);
    try expectNextFromBuffer(.{ .string = "xyz" }, "  \"xyz\"", 1);
    try expectNextFromBuffer(.{ .range = .{ .upper = 0, .lower = 0 } }, " [0]", 0);
    try expectNextFromBuffer(.{ .range = .{ .upper = 64, .lower = 48 } }, " [64:48]", 0);
    try expectNextFromBuffer(.{ .bv = .{ .bits = &.{ 0, 0, 0, 0 } } }, "4'0000", 0);
    try expectNextFromBuffer(.{ .bv = .{ .bits = &.{ 0, 0, 0, 0, 0, 0, 0, 1 } } }, "8'10000000", 0);
}

fn expectAllFromBuffer(
    allocator: Allocator,
    expected: Token.Error![]const Token,
    buffer: []const u8,
) !void {
    const tokens_err = Token.allFromBuffer(allocator, buffer);
    defer {
        if (tokens_err) |tokens| {
            for (tokens) |*token|
                token.deinit(allocator);
            allocator.free(tokens);
        } else |_| {}
    }

    if (expected) |expectedTokens| {
        try std.testing.expectEqualDeep(expectedTokens, try tokens_err);
    } else |expectedError| {
        try std.testing.expectError(expectedError, tokens_err);
    }
}

test "Token.allFromBuffer - CAAF" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, testAllFromBuffer, .{});
}

fn testAllFromBuffer(allocator: Allocator) !void {
    try expectAllFromBuffer(allocator, &.{
        Token{ .bareword = "attribute" },
        Token{ .bareword = "\\init" },
        Token{ .bv = .{ .bits = &.{ 0, 0 } } },
    }, "attribute \\init 2'00");

    try expectAllFromBuffer(allocator, error.Invalid, "abc!");
}
