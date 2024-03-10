const std = @import("std");
const Allocator = std.mem.Allocator;

const rtlil = @import("./rtlil.zig");
const parser = @import("./parser.zig");
const eval = @import("./eval.zig").eval;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    defer _ = gpa.deinit();

    std.debug.print("", .{});

    const input = try std.io.getStdIn().readToEndAlloc(alloc, 1048576);
    defer alloc.free(input);

    var doc = try parser.parse(alloc, input);
    defer doc.deinit(alloc);

    const mods = try eval(alloc, doc);

    try rtlil.output(std.io.getStdOut().writer(), mods);
}

// Gourd zero for synthesis:
// yosys -q -g -l top.rpt top.ys
// <<top.ys:
//   read_ilang top.il
//   synth_ice40 -top top
//   write_json top.json
// <<
// nextpnr-ice40 --quiet --log top.tim --up5k --package sg48 --json top.json --pcf top.pcf --asc top.asc
// <<top.pcf:
//   set_io led_0__io 11
//   set_io led_1__io 37
//   set_io button_0__io 10
//   ...
//   set_io i2c_0__scl__io 2
//   set_io i2c_0__sda__io 4
//   set_io clk12_0__io 35
//   set_frequency pin_clk12_0.\clk_12_0__i 12.0
// <<
// icepack top.asc top.bin
//
//
// cd_sync:
//

comptime {
    std.testing.refAllDecls(@import("test.zig"));
}

// iCEBreaker: 12MHz.
//
// (reg x 24)
// (sync (set x (+ x 1)))
// (connect x[-1] led0)
