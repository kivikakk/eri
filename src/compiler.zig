const std = @import("std");
const Allocator = std.mem.Allocator;
const ast = @import("ast.zig");
const rtlil = @import("rtlil.zig");

    pub fn compileBuffer(allocator: Allocator, input: []const u8) !rtlil.Doc {
        var compiler = Compiler.mk(allocator);
        defer compiler.deinit();

        const doc = try ast.parse(allocator, input);
        defer doc.deinit(allocator);

        for (doc.forms) |form| {
            try compiler.nomTop(form);
        }

        return try compiler.finalise();
    }

pub const Compiler = struct {
    const Self = @This();

    const Error = error{Unexpected} || Allocator.Error;

    allocator: Allocator,
    registers: std.ArrayListUnmanaged(Register) = .{},

    pub fn mk(allocator: Allocator) Self {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Self) void {
        for (self.registers.items) |register| register.deinit(self.allocator);
        self.registers.deinit(self.allocator);
    }

    fn nomTop(self: *Self, form: ast.Form) Error!void {
        const els = switch (form.value) {
            .list => |forms| forms,
            else => return error.Unexpected,
        };

        std.debug.assert(els.len > 0);

        switch (els[0].value) {
            .label => |label| {
                if (std.mem.eql(u8, label, "reg")) {
                    const reg = try self.nomReg(els[1..]);
                    errdefer reg.deinit(self.allocator);
                    try self.registers.append(self.allocator, reg);
                } else if (std.mem.eql(u8, label, "sync")) {} else if (std.mem.eql(u8, label, "connect")) {} else {
                    return error.Unexpected;
                }
            },
            else => return error.Unexpected,
        }
    }

    fn nomReg(self: Self, args: []const ast.Form) Error!Register {
        std.debug.assert(args.len >= 1);

        const name = try std.fmt.allocPrint(self.allocator, "\\{s}", .{args[0].value.label});
        errdefer self.allocator.free(name);

        const width: usize = if (args.len >= 2) @intCast(args[1].value.number) else 1;

        var init = try self.allocator.alloc(u1, width);
        if (args.len >= 3) {
            switch (args[2].value) {
                .number => |number| {
                    if (number < 0)
                        std.debug.assert(number >= -std.math.pow(i64, 2, @intCast(width - 1)))
                    else
                        std.debug.assert(number < std.math.pow(i64, 2, @intCast(width)));
                    var p: i64 = 1;
                    var i: usize = 0;
                    while (i < width) : (i += 1) {
                        init[i] = if ((number & p) == p) 1 else 0;
                        p *= 2;
                    }
                },
                else => return error.Unexpected,
            }
        }

        return .{
            .name = name,
            .width = width,
            .init = init,
        };
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

fn expectCompilesTo(allocator: Allocator, input: []const u8, il: []const u8) !void {
    const doc = try compileBuffer(allocator, input);
    defer doc.deinit(allocator);

    const expIl = try rtlil.parse(rtlil.Doc, allocator, il);
    defer expIl.deinit(allocator);

    const output = try rtlil.allocOutput(allocator, doc);
    defer allocator.free(output);

    try std.testing.expectEqualDeep(expIl, doc);
}

test "compile - CAAF" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, compileTest, .{});
}

fn compileTest(allocator: Allocator) !void {
    try expectCompilesTo(allocator, "(reg x 8 -2)",
        \\module top
        \\  wire width 8 \x
        \\end
    );
}

