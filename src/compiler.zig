const std = @import("std");
const Allocator = std.mem.Allocator;
const parser = @import("parser.zig");
const rtlil = @import("rtlil.zig");

const Register = struct {
    const Self = @This();

    name: []const u8,
    width: usize,
    init: []u1,

    fn deinit(self: Self, allocator: Allocator) void {
        allocator.free(self.name);
        allocator.free(self.init);
    }
};

pub const Compiler = struct {
    const Self = @This();

    const Error = error{Unexpected} || Allocator.Error;

    allocator: Allocator,
    registers: std.ArrayListUnmanaged(Register) = .{},

    pub fn compileBuffer(allocator: Allocator, input: []const u8) !rtlil.Doc {
        var compiler = Self.mk(allocator);
        defer compiler.deinit();

        const doc = try parser.parse(allocator, input);
        defer doc.deinit(allocator);

        for (doc.forms) |form| {
            try compiler.nomTop(form);
        }

        return try compiler.finalise();
    }

    pub fn mk(allocator: Allocator) Self {
        return .{ .allocator = allocator };
    }

    fn finalise(self: *Self) !rtlil.Doc {
        var wires = std.ArrayListUnmanaged(rtlil.Wire){};
        errdefer {
            for (wires.items) |wire| wire.deinit(self.allocator);
            wires.deinit(self.allocator);
        }

        for (self.registers.items) |register| {
            const name = try self.allocator.dupe(u8, register.name);
            errdefer self.allocator.free(name);
            try wires.append(self.allocator, .{
                .width = register.width,
                .name = name,
            });
        }

        var modules = try self.allocator.alloc(rtlil.Module, 1);
        modules[0] = .{ .name = "uninitialised" };
        errdefer {
            for (modules) |module| module.deinit(self.allocator);
            self.allocator.free(modules);
        }

        modules[0] = rtlil.Module{
            .name = "top",
            .wires = try wires.toOwnedSlice(self.allocator),
        };

        return rtlil.Doc.fromModules(modules);
    }
};

fn compileTest(allocator: Allocator) !void {
    const doc = try Compiler.compileBuffer(allocator, "(reg x 8 -2)");
    defer doc.deinit(allocator);

    const output = try rtlil.allocOutput(allocator, doc);
    defer allocator.free(output);

    std.debug.print("{s}\n", .{output});
}

test "compile" {
    try compileTest(std.testing.allocator);
}

test "compile - CAAF" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, compileTest, .{});
}
