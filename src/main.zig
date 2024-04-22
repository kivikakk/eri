const std = @import("std");
const Allocator = std.mem.Allocator;

const rtlil = @import("./rtlil.zig");
const hdl = @import("./hdl.zig");
const common = @import("common.zig");

test {
    _ = rtlil;
    _ = hdl;
    _ = common;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    hdl.arena = arena.allocator();

    var module = hdl.Module.make("top");
    const led0 = hdl.Resource.find("led0");
    const counter = hdl.Signal.make("counter", 16);
    module.comb(.{
        led0.o.eq(counter.expr().bit(-1)),
    });
    module.sync(.{
        counter.eq(counter.expr().add(1)),
    });

    module.dump();

    // var il = il: {
    //     var wires = std.ArrayListUnmanaged(rtlil.Wire){};
    //     var connections = std.ArrayListUnmanaged(rtlil.Connection){};
    //     errdefer {
    //         common.deinit(allocator, &wires);
    //         common.deinit(allocator, &connections);
    //     }

    //     var modules = try allocator.alloc(rtlil.Module, 1);
    //     modules[0] = .{ .name = "" };
    //     errdefer common.deinit(allocator, modules);

    //     const name = try allocator.dupe(u8, "\\top");
    //     errdefer allocator.free(name);

    //     const o_wires = try wires.toOwnedSlice(allocator);
    //     errdefer common.deinit(allocator, o_wires);

    //     const o_connections = try connections.toOwnedSlice(allocator);

    //     modules[0] = rtlil.Module{
    //         .name = name,
    //         .wires = o_wires,
    //         .connections = o_connections,
    //     };

    //     break :il rtlil.Doc.fromModules(modules);
    // };
    // defer il.deinit(allocator);

    // try rtlil.output(std.io.getStdOut().writer(), il);
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
