const std = @import("std");

pub const Module = struct {
    name: []const u8,
    memories: []Memory,
    cells: []Cell,

    fn print(mod: Module, writer: *Writer) !void {
        try writer.print("module {s}", .{mod.name});
        writer.indent += 1;

        for (mod.memories) |mem| {
            try writer.print("memory width {} size {} {s}", .{ mem.width, mem.size, mem.name });
        }

        for (mod.cells) |cell| {
            try cell.print(writer);
        }

        defer writer.indent -= 1;
        try writer.print("end", .{});
    }
};

pub const Memory = struct {
    width: u8,
    size: u32,
    name: []const u8,
};

pub const Cell = struct {
    const Self = @This();

    kind: []const u8,
    name: []const u8,
    parameters: []const Parameter,
    connections: []const Connection,

    fn print(self: Self, writer: *Writer) !void {
        try writer.print("cell {s} {s}", .{ self.kind, self.name });
        writer.indent += 1;
        for (self.parameters) |parameter| {
            try writer.print("parameter {s} {}", .{ parameter.name, parameter.value });
        }
        for (self.connections) |connection| {
            try writer.print("connect {s} {}", .{ connection.name, connection.target });
        }
        writer.indent -= 1;
        try writer.print("end", .{});
    }
};

pub const Parameter = struct {
    name: []const u8,
    value: Value,
};

pub const Value = union(enum) {
    const Self = @This();

    number: u64,
    string: []const u8,
    bv: Bitvector,

    pub fn format(self: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;

        switch (self) {
            .number => |n| try std.fmt.format(writer, "{}", .{n}),
            .string => |s| try std.fmt.format(writer, "\"{s}\"", .{s}),
            .bv => |bv| try std.fmt.format(writer, "{}", .{bv}),
        }
    }
};

pub const Connection = struct {
    name: []const u8,
    target: union(enum) {
        wire: struct {
            name: []const u8,
            range: Range,
        },
        constant: Bitvector,

        pub fn format(self: @This(), comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = fmt;
            _ = options;

            switch (self) {
                .wire => |wire| try std.fmt.format(writer, "{s} [{}:{}]", .{ wire.name, wire.range.upper, wire.range.lower }),
                .constant => |bv| try std.fmt.format(writer, "{}", .{bv}),
            }
        }
    },
};

pub const Bitvector = struct {
    const Self = @This();

    bits: []const u1,

    pub fn format(self: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try std.fmt.format(writer, "{}'", .{self.bits.len});
        for (self.bits) |bit| {
            try writer.writeAll(if (bit == 1) "1" else "0");
        }
    }
};

pub const Range = struct {
    upper: usize,
    lower: usize,
};

pub fn output(writer: anytype, mods: []const Module) !void {
    var w = Writer.init(writer.any());

    for (mods) |mod| {
        try mod.print(&w);
    }
}

const Writer = struct {
    const Self = @This();

    inner: std.io.AnyWriter,

    indent: u8 = 0,

    fn init(inner: std.io.AnyWriter) Writer {
        return .{ .inner = inner };
    }

    fn print(self: Self, comptime fmt: []const u8, args: anytype) !void {
        try self.inner.writeByteNTimes(' ', self.indent * 2);
        try std.fmt.format(self.inner, fmt ++ "\n", args);
    }
};

// <<top.il:
//   attribute \generator "Amaranth"
//   attribute \top 1
//   module \top
//     attribute \src "/Users/blah/xyz.py:123"
//     memory width 8 size 71 \rom_rd
//     wire width 1 \clk
//     wire width 1 \rst
//     ...
//     wire width 1 \led_0__o
//     wire width 1 \button_0__i
//     ...
//     wire width 1 inout 0 \led_0__io
//     ..
//     wire width 1 inout 2 \button_0__io
//     ..
//     wire width 1 inout 17 \clk12_0__io
//     wire width 1 $1
//     wire width 1 $2
//     ...
//     connect \i2c_bus__busy \led_0__o [0]
//     connect \button_0__i \i [0]
//     ...
//     cell \top.oled \oled
//       connect \spi_flash_1x_0__clk__o $13 [0]
//       connect \w_rdy \w_rdy [0]
//       connect \rst \rst [0]
//       connect \clk \clk [0]
//       ...
//     end
//     ..
//     cell \top.cd_sync \cd_sync
//       connect \rst \rst [0]
//       connect \clk \clk [0]
//     end
//     cell \top.pin_led_0 \pin_led_0
//       connect \led_0__io \led_0__io [0]
//       connect \led_0__o \led_0__o [0]
//     end
//     ..
//     cell $and $21
//       parameter \A_SIGNED 0
//       parameter \B_SIGNED 0
//       parameter \A_WIDTH 1
//       parameter \B_WIDTH 1
//       parameter \Y_WIDTH 1
//       connect \A \up [0]
//       connect \B \w_rdy [0]
//       connect \Y $1
//     end
//     ..
//     attribute \src "/Users/...:123"
//     cell $eq $25
//       parameter \A_SIGNED 0
//       parameter \B_SIGNED 0
//       parameter \A_WIDTH 7
//       parameter \B_WIDTH 7
//       parameter \Y_WIDTH 1
//       connect \A \remain [6:0]
//       connect \B 7'0000001
//       connect \Y $5
//     end
//     ...
//     process $30
//       assign $8 [0] \w_en [0]
//       switch \fsm_state [1:0]
//         case 2'00
//           assign $8 [0] 1'0
//         case 2'01
//         case 2'10
//           switch \w_rdy [0]
//             case 1'1
//               assign $8 [0] 1'1
//           end
//         case 2'11
//           assign $8 [0] 1'0
//       end
//       switch \rst [0]
//         case 1'1
//           assign $8 [0] 1'0
//       end
//     end
//     cell $dff $31
//       parameter \WIDTH 1
//       parameter \CLK_POLARITY 1
//       connect \D $8 [0]
//       connect \CLK \clk [0]
//       connect \Q \w_en
//     end
//     ..
//     ...
//       switch { $1 [0] \spifr_bus__valid [0] }
//         case 2'-1
//           assign $91 [5:0] 6'000011
//         case 2'1-
//           assign $91 [5:0] 6'000100
//       end
//     ...
//       process $322
//         assign \i2c_bus__in_fifo_w_rdy$125 [0] 1'0
//         switch { \busy$74 [0] \busy$70 [0] \busy [0] \busy$71 [0] }
//           case 4'---1
//           case 4'--1-
//           case 4'-1--
//           case 4'1---
//             assign \i2c_bus__in_fifo_w_rdy$125 [0] \i2c_bus__in_fifo_w_rdy [0]
//           case          # ? XXX
//         end
//     ..
// cell $meminit_v2 $68
//   parameter \MEMID "\\storage"
//   parameter \ABITS 0
//   parameter \WIDTH 8
//   parameter \WORDS 31
//   parameter \PRIORITY 0
//   connect \ADDR {  }
//   connect \DATA 248'00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
//   connect \EN 8'11111111
// end
// attribute \src "/nix/store/07fwg07nvi4mbbd65793nrqg3az16pdw-python3.11-amaranth-0.4.4dev1+gc40cfc9/lib/python3.11/site-packages/amaranth/lib/memory.py:97"
// cell $memwr_v2 $69
//   parameter \MEMID "\\storage"
//   parameter \ABITS 5
//   parameter \WIDTH 8
//   parameter \CLK_ENABLE 1
//   parameter \CLK_POLARITY 1
//   parameter \PORTID 0
//   parameter \PRIORITY_MASK 0
//   connect \ADDR $signature__addr [4:0]
//   connect \DATA \w_data [7:0]
//   connect \EN { $signature__en [0] $signature__en [0] $signature__en [0] $signature__en [0] $signature__en [0] $signature__en [0] $signature__en [0] $signature__en [0] }
//   connect \CLK \clk [0]
// end
// attribute \src "/nix/store/07fwg07nvi4mbbd65793nrqg3az16pdw-python3.11-amaranth-0.4.4dev1+gc40cfc9/lib/python3.11/site-packages/amaranth/lib/memory.py:204"
// cell $memrd_v2 $70
//   parameter \MEMID "\\storage"
//   parameter \ABITS 5
//   parameter \WIDTH 8
//   parameter \TRANSPARENCY_MASK 1'0
//   parameter \COLLISION_X_MASK 1'0
//   parameter \ARST_VALUE 8'00000000
//   parameter \SRST_VALUE 8'00000000
//   parameter \INIT_VALUE 8'00000000
//   parameter \CE_OVER_SRST 0
//   parameter \CLK_ENABLE 1
//   parameter \CLK_POLARITY 1
//   connect \ADDR $signature__addr$18 [4:0]
//   connect \DATA \r_data
//   connect \ARST 1'0
//   connect \SRST 1'0
//   connect \EN $signature__en$21 [0]
//   connect \CLK \clk [0]
// end
//   end
// <<

// TODO: checkAllAllocationFailures
test "cell print" {
    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    var w = Writer.init(out.writer().any());

    const cell = Cell{
        .kind = "$memrd_v2",
        .name = "$70",
        .parameters = &.{
            .{ .name = "\\WIDTH", .value = .{ .number = 8 } },
            .{ .name = "\\ABITS", .value = .{ .number = 5 } },
        },
        .connections = &.{ .{ .name = "\\ADDR", .target = .{ .wire = .{
            .name = "$signature__addr$18",
            .range = .{ .upper = 4, .lower = 0 },
        } } }, .{ .name = "\\ARST", .target = .{ .constant = .{
            .bits = &.{0},
        } } } },
    };

    try cell.print(&w);
    try std.testing.expectEqualStrings(
        \\cell $memrd_v2 $70
        \\  parameter \WIDTH 8
        \\  parameter \ABITS 5
        \\  connect \ADDR $signature__addr$18 [4:0]
        \\  connect \ARST 1'0
        \\end
        \\
    , out.items);
}
