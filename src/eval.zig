const std = @import("std");
const Allocator = std.mem.Allocator;
const Doc = @import("parser.zig").Doc;
const rtlil = @import("rtlil.zig");

const Register = struct {
    const Self = @This();

    name: []const u8,
    width: usize,
    init: []u1,
};

pub fn eval(allocator: Allocator, doc: Doc) ![]rtlil.Module {
    var registers = std.ArrayListUnmanaged(Register){};
    defer {
        for (registers) |register| register.deinit(allocator);
        registers.deinit(allocator);
    }
    std.debug.print("evaluating: \n{}", .{doc});

    return &.{};
}
