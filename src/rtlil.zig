const std = @import("std");
const Allocator = std.mem.Allocator;
const common = @import("common.zig");
const rtlil_parser = @import("rtlil_parser.zig");
const Parser = rtlil_parser.Parser;

test {
    _ = rtlil_parser;
}

pub fn output(writer: anytype, what: anytype) !void {
    var w = mkWriter(writer);
    try w.printObject(what);
}

pub fn allocOutput(allocator: Allocator, what: anytype) ![]const u8 {
    var out = std.ArrayListUnmanaged(u8){};
    defer out.deinit(allocator);
    try output(out.writer(allocator), what);
    return try out.toOwnedSlice(allocator);
}

pub const Doc = struct {
    const Self = @This();

    modules: []const Module,

    pub fn parse(allocator: Allocator, buffer: []const u8) Parser.Error!Self {
        var parser = Parser.mk(allocator, buffer);
        return Self.fromModules(try parser.parse());
    }

    pub fn fromModules(modules: []Module) Self {
        return Self{ .modules = modules };
    }

    pub fn deinit(self: Self, allocator: Allocator) void {
        common.deinit(allocator, self.modules);
    }
};

pub const Module = struct {
    const Self = @This();

    attributes: []const Attribute = &.{},
    name: []const u8,
    memories: []const Memory = &.{},
    wires: []const Wire = &.{},
    connections: []const Connection = &.{},
    cells: []const Cell = &.{},
    processes: []const Process = &.{},

    pub fn deinit(self: Self, allocator: Allocator) void {
        common.deinit(allocator, self.attributes);
        allocator.free(self.name);
        common.deinit(allocator, self.memories);
        common.deinit(allocator, self.wires);
        common.deinit(allocator, self.connections);
        common.deinit(allocator, self.cells);
        common.deinit(allocator, self.processes);
    }
};

pub const Attribute = struct {
    const Self = @This();

    name: []const u8,
    value: Value,

    pub fn deinit(self: Self, allocator: Allocator) void {
        allocator.free(self.name);
        self.value.deinit(allocator);
    }
};

pub const Memory = struct {
    const Self = @This();

    attributes: []const Attribute = &.{},
    width: usize,
    size: usize,
    name: []const u8,

    pub fn deinit(self: Self, allocator: Allocator) void {
        common.deinit(allocator, self.attributes);
        allocator.free(self.name);
    }
};

pub const Wire = struct {
    const Self = @This();

    pub const Spec = struct {
        pub const Dir = enum { input, output, inout };
        dir: Dir,
        index: usize,
    };

    width: usize,
    spec: ?Spec = null,
    name: []const u8,

    pub fn deinit(self: Self, allocator: Allocator) void {
        allocator.free(self.name);
    }
};

pub const Cell = struct {
    const Self = @This();

    attributes: []const Attribute = &.{},
    kind: []const u8,
    name: []const u8,
    parameters: []const Parameter,
    connections: []const Connection,

    pub fn deinit(self: Self, allocator: Allocator) void {
        common.deinit(allocator, self.attributes);
        allocator.free(self.kind);
        allocator.free(self.name);
        common.deinit(allocator, self.parameters);
        common.deinit(allocator, self.connections);
    }
};

pub const Parameter = struct {
    const Self = @This();

    name: []const u8,
    value: Value,

    pub fn deinit(self: Self, allocator: Allocator) void {
        allocator.free(self.name);
        self.value.deinit(allocator);
    }
};

pub const Value = union(enum) {
    const Self = @This();

    number: i64,
    string: []const u8,
    bv: Bitvector,

    pub fn deinit(self: Self, allocator: Allocator) void {
        switch (self) {
            .number => {},
            .string => |string| allocator.free(string),
            .bv => |bv| bv.deinit(allocator),
        }
    }

    pub fn format(self: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        switch (self) {
            .number => |n| try std.fmt.format(writer, "{}", .{n}),
            .string => |s| {
                try writer.writeByte('"');
                for (s) |c| {
                    switch (c) {
                        inline '"', '\\' => try writer.writeAll(&.{ '\\', c }),
                        else => try writer.writeByte(c),
                    }
                }
                try writer.writeByte('"');
            },
            .bv => |bv| try bv.format(fmt, options, writer),
        }
    }
};

pub const Connection = struct {
    const Self = @This();

    name: []const u8,
    target: RValue,

    pub fn deinit(self: Self, allocator: Allocator) void {
        allocator.free(self.name);
        self.target.deinit(allocator);
    }
};

pub const RValue = union(enum) {
    const Self = @This();

    signal: Signal,
    bv: Bitvector,
    number: i32,
    cat: Cat,

    pub fn deinit(self: Self, allocator: Allocator) void {
        switch (self) {
            .number => {},
            inline else => |payload| payload.deinit(allocator),
        }
    }

    pub fn format(
        self: Self,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) @TypeOf(writer).Error!void {
        switch (self) {
            .number => |number| try std.fmt.formatInt(number, 10, .lower, options, writer),
            inline else => |payload| try payload.format(fmt, options, writer),
        }
    }
};

pub const Signal = struct {
    const Self = @This();

    name: []const u8,
    range: ?Range = null,

    pub fn deinit(self: Self, allocator: Allocator) void {
        allocator.free(self.name);
    }

    pub fn format(
        self: Self,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        if (self.range) |range|
            try std.fmt.format(writer, "{s} [{}]", .{ self.name, range })
        else
            try writer.writeAll(self.name);
    }
};

pub const Bitvector = struct {
    const Self = @This();

    pub const Bit = enum(u2) {
        zero = 0,
        one = 1,
        dont_care = 2,
        _unused = 3,
    };

    bits: []const Bit,

    pub fn fromU1s(allocator: Allocator, src: []u1) Allocator.Error!Self {
        var bits = try allocator.alloc(Bit, src.len) ;
        for (src, 0..) |bit, i|
            bits[i] = if (bit == 0) .zero else .one;
        return .{ .bits = bits };
    }

    pub fn dupe(self: Self, allocator: Allocator) Allocator.Error!Self {
        return .{ .bits = try allocator.dupe(Bit, self.bits) };
    }

    pub fn deinit(self: Self, allocator: Allocator) void {
        allocator.free(self.bits);
    }

    pub fn format(
        self: Self,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        try std.fmt.format(writer, "{}'", .{self.bits.len});
        var it = std.mem.reverseIterator(self.bits);
        while (it.next()) |bit| {
            try writer.writeByte(switch (bit) {
                .zero => '0',
                .one => '1',
                .dont_care => '-',
                else => unreachable,
            });
        }
    }
};

pub const Cat = struct { // meow :"3
    const Self = @This();

    values: []const RValue,

    pub fn deinit(self: Self, allocator: Allocator) void {
        common.deinit(allocator, self.values);
    }

    pub fn format(
        self: Self,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try writer.writeAll("{ ");
        for (self.values) |value| {
            try value.format(fmt, options, writer);
            try writer.writeByte(' ');
        }
        try writer.writeByte('}');
    }
};

pub const Range = struct {
    const Self = @This();

    upper: usize = 0,
    lower: usize = 0,

    pub fn format(self: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;

        if (self.upper == self.lower) {
            try std.fmt.format(writer, "{}", .{self.upper});
        } else {
            try std.fmt.format(writer, "{}:{}", .{ self.upper, self.lower });
        }
    }
};

pub const Process = struct {
    const Self = @This();

    attributes: []const Attribute = &.{},
    name: []const u8,
    assigns: []const Assign = &.{},
    switches: []const Switch = &.{},

    pub fn deinit(self: Self, allocator: Allocator) void {
        common.deinit(allocator, self.attributes);
        allocator.free(self.name);
        common.deinit(allocator, self.assigns);
        common.deinit(allocator, self.switches);
    }
};

pub const Assign = struct {
    const Self = @This();

    lhs: Signal,
    rhs: RValue,

    pub fn deinit(self: Self, allocator: Allocator) void {
        self.lhs.deinit(allocator);
        self.rhs.deinit(allocator);
    }
};

pub const Switch = struct {
    const Self = @This();

    lhs: Signal,
    cases: []const Case,

    pub fn deinit(self: Self, allocator: Allocator) void {
        self.lhs.deinit(allocator);
        common.deinit(allocator, self.cases);
    }

    pub const Case = struct {
        value: ?Bitvector,
        assigns: []const Assign = &.{},
        switches: []const Switch = &.{},

        pub fn deinit(self: Case, allocator: Allocator) void {
            if (self.value) |value|
                value.deinit(allocator);
            common.deinit(allocator, self.assigns);
            common.deinit(allocator, self.switches);
        }
    };
};

fn Writer(comptime T: type) type {
    return struct {
        const Self = @This();

        inner: T,
        indent: u8 = 0,

        fn mk(inner: T) Self {
            return .{ .inner = inner };
        }

        fn writeIndent(self: Self) !void {
            try self.inner.writeByteNTimes(' ', self.indent * 2);
        }

        fn printLine(self: Self, comptime fmt: []const u8, args: anytype) !void {
            try self.writeIndent();
            try std.fmt.format(self.inner, fmt ++ "\n", args);
        }

        fn printAttributes(self: Self, target: anytype) !void {
            for (target.attributes) |attribute| {
                try self.printLine("attribute {s} {}", .{ attribute.name, attribute.value });
            }
        }

        fn printObject(self: *Self, what: anytype) T.Error!void {
            if (@hasField(@TypeOf(what), "attributes"))
                try self.printAttributes(what);

            switch (@TypeOf(what)) {
                Doc => {
                    for (what.modules) |module|
                        try self.printObject(module);
                },
                Module => {
                    try self.printLine("module {s}", .{what.name});
                    self.indent += 1;

                    for (what.memories) |memory|
                        try self.printObject(memory);

                    for (what.wires) |wire|
                        try self.printObject(wire);

                    for (what.connections) |connection|
                        try self.printObject(connection);

                    for (what.cells) |cell|
                        try self.printObject(cell);

                    for (what.processes) |process|
                        try self.printObject(process);

                    self.indent -= 1;
                    try self.printLine("end", .{});
                },
                Attribute => {
                    try self.printLine("attribute {s} {}", .{ what.name, what.value });
                },
                Memory => {
                    try self.printLine("memory width {} size {} {s}", .{ what.width, what.size, what.name });
                },
                Wire => {
                    if (what.spec) |spec| {
                        try self.printLine("wire width {} {s} {} {s}", .{
                            what.width,
                            @tagName(spec.dir),
                            spec.index,
                            what.name,
                        });
                    } else {
                        try self.printLine("wire width {} {s}", .{ what.width, what.name });
                    }
                },
                Cell => {
                    try self.printLine("cell {s} {s}", .{ what.kind, what.name });
                    self.indent += 1;

                    for (what.parameters) |parameter|
                        try self.printObject(parameter);

                    for (what.connections) |connection|
                        try self.printObject(connection);

                    self.indent -= 1;
                    try self.printLine("end", .{});
                },
                Parameter => {
                    try self.printLine("parameter {s} {}", .{ what.name, what.value });
                },
                Connection => {
                    try self.printLine("connect {s} {}", .{ what.name, what.target });
                },
                Process => {
                    try self.printLine("process {s}", .{what.name});
                    self.indent += 1;

                    for (what.assigns) |assign|
                        try self.printObject(assign);

                    for (what.switches) |switch_|
                        try self.printObject(switch_);

                    self.indent -= 1;
                    try self.printLine("end", .{});
                },
                Assign => {
                    try self.printLine("assign {} {}", .{ what.lhs, what.rhs });
                },
                Switch => {
                    try self.printLine("switch {}", .{what.lhs});
                    self.indent += 1;

                    for (what.cases) |case|
                        try self.printObject(case);

                    self.indent -= 1;
                    try self.printLine("end", .{});
                },
                Switch.Case => {
                    if (what.value) |value| {
                        try self.printLine("case {}", .{value});
                    } else {
                        try self.printLine("case", .{});
                    }
                    self.indent += 1;
                    for (what.assigns) |assign|
                        try self.printObject(assign);
                    for (what.switches) |switch_|
                        try self.printObject(switch_);
                    self.indent -= 1;
                },
                else => std.debug.print("unhandled in printObject: {any}\n", .{what}),
            }
        }
    };
}

fn mkWriter(inner: anytype) Writer(@TypeOf(inner)) {
    return Writer(@TypeOf(inner)).mk(inner);
}

fn expectOutputAndRoundtrip(allocator: Allocator, arg: Doc, expected: []const u8) !void {
    const out = try allocOutput(allocator, arg);
    defer allocator.free(out);
    try std.testing.expectEqualStrings(expected, out);

    const comp = try Doc.parse(allocator, out);
    defer common.deinit(allocator, comp);

    try std.testing.expectEqualDeep(arg, comp);
}

test "module print - CAAF" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, testModulePrint, .{});
}

fn testModulePrint(allocator: Allocator) !void {
    try expectOutputAndRoundtrip(allocator, .{ .modules = &.{.{
        .attributes = &.{
            .{ .name = "\\generator", .value = .{ .string = "eri" } },
            .{ .name = "\\top", .value = .{ .number = 1 } },
        },
        .name = "\\top",
        .memories = &.{.{
            .attributes = &.{
                .{ .name = "\\src", .value = .{ .string = "module print test" } },
            },
            .width = 8,
            .size = 71,
            .name = "\\rom_rd",
        }},
        .wires = &.{
            .{ .width = 1, .name = "\\clk" },
            .{ .width = 1, .spec = .{ .dir = .inout, .index = 0 }, .name = "\\led_0__io" },
        },
        .connections = &.{.{ .name = "\\i2c_bus__busy", .target = .{
            .signal = .{ .name = "\\led_0__o", .range = .{} },
        } }},
        .cells = &.{ .{
            .attributes = &.{
                .{ .name = "\\src", .value = .{ .string = "module print test again" } },
            },
            .kind = "$dff",
            .name = "$31",
            .parameters = &.{
                .{ .name = "\\WIDTH", .value = .{ .number = 1 } },
                .{ .name = "\\CLK_POLARITY", .value = .{ .number = 1 } },
            },
            .connections = &.{
                .{ .name = "\\D", .target = .{ .signal = .{
                    .name = "$8",
                } } },
                .{ .name = "\\CLK", .target = .{ .signal = .{
                    .name = "\\clk",
                } } },
                .{ .name = "\\Q", .target = .{ .signal = .{
                    .name = "\\w_en",
                } } },
            },
        }, .{
            .kind = "$memrd_v2",
            .name = "$70",
            .parameters = &.{
                .{ .name = "\\MEMID", .value = .{ .string = "\\storage" } },
                .{ .name = "\\WIDTH", .value = .{ .number = 8 } },
                .{ .name = "\\ABITS", .value = .{ .number = 5 } },
            },
            .connections = &.{ .{ .name = "\\ADDR", .target = .{ .signal = .{
                .name = "$signature__addr$18",
                .range = .{ .upper = 4 },
            } } }, .{ .name = "\\ARST", .target = .{ .bv = .{
                .bits = &.{.zero},
            } } } },
        } },
        .processes = &.{.{
            .name = "$30",
            .assigns = &.{.{
                .lhs = .{ .name = "$8", .range = .{} },
                .rhs = .{ .signal = .{ .name = "\\w_en", .range = .{} } },
            }},
            .switches = &.{ .{
                .lhs = .{ .name = "\\fsm_state", .range = .{ .upper = 1 } },
                .cases = &.{ .{
                    .value = .{ .bits = &.{ .zero, .zero } },
                    .assigns = &.{
                        .{
                            .lhs = .{ .name = "$8", .range = .{} },
                            .rhs = .{ .bv = .{ .bits = &.{.zero} } },
                        },
                    },
                }, .{ .value = .{ .bits = &.{ .one, .zero } } }, .{
                    .value = .{ .bits = &.{ .zero, .one } },
                    .switches = &.{.{
                        .lhs = .{ .name = "\\w_rdy", .range = .{} },
                        .cases = &.{.{
                            .value = .{ .bits = &.{.one} },
                            .assigns = &.{.{
                                .lhs = .{ .name = "$8", .range = .{} },
                                .rhs = .{ .bv = .{ .bits = &.{.one} } },
                            }},
                        }},
                    }},
                }, .{ .value = .{ .bits = &.{ .one, .one } }, .assigns = &.{
                    .{
                        .lhs = .{ .name = "$8", .range = .{} },
                        .rhs = .{ .bv = .{ .bits = &.{.zero} } },
                    },
                } }, .{ .value = .{ .bits = &.{ .one, .dont_care } } } },
            }, .{
                .lhs = .{ .name = "\\rst", .range = .{} },
                .cases = &.{
                    .{
                        .value = .{ .bits = &.{.one} },
                        .assigns = &.{.{
                            .lhs = .{ .name = "$8", .range = .{} },
                            .rhs = .{ .cat = .{ .values = &.{
                                .{ .bv = .{ .bits = &.{ .zero, .zero, .zero, .zero } } },
                                .{ .signal = .{ .name = "\\read__value", .range = .{ .upper = 15, .lower = 15 } } },
                            } } },
                        }},
                    },
                    .{ .value = null },
                },
            } },
        }},
    }} },
        \\attribute \generator "eri"
        \\attribute \top 1
        \\module \top
        \\  attribute \src "module print test"
        \\  memory width 8 size 71 \rom_rd
        \\  wire width 1 \clk
        \\  wire width 1 inout 0 \led_0__io
        \\  connect \i2c_bus__busy \led_0__o [0]
        \\  attribute \src "module print test again"
        \\  cell $dff $31
        \\    parameter \WIDTH 1
        \\    parameter \CLK_POLARITY 1
        \\    connect \D $8
        \\    connect \CLK \clk
        \\    connect \Q \w_en
        \\  end
        \\  cell $memrd_v2 $70
        \\    parameter \MEMID "\\storage"
        \\    parameter \WIDTH 8
        \\    parameter \ABITS 5
        \\    connect \ADDR $signature__addr$18 [4:0]
        \\    connect \ARST 1'0
        \\  end
        \\  process $30
        \\    assign $8 [0] \w_en [0]
        \\    switch \fsm_state [1:0]
        \\      case 2'00
        \\        assign $8 [0] 1'0
        \\      case 2'01
        \\      case 2'10
        \\        switch \w_rdy [0]
        \\          case 1'1
        \\            assign $8 [0] 1'1
        \\        end
        \\      case 2'11
        \\        assign $8 [0] 1'0
        \\      case 2'-1
        \\    end
        \\    switch \rst [0]
        \\      case 1'1
        \\        assign $8 [0] { 4'0000 \read__value [15] }
        \\      case
        \\    end
        \\  end
        \\end
        \\
    );
}
