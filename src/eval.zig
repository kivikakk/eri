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

const Compiler = struct {
    const Self = @This();

    const Error = error{Unexpected} || Allocator.Error;

    allocator: Allocator,
    registers: std.ArrayListUnmanaged(Register) = .{},

    pub fn mk(allocator: Allocator) Self {
        return .{ .allocator = allocator };
    }

    pub fn top(self: *Self, form: parser.Form) Error!void {
        std.debug.print("compiling form: {}\n", .{form});

        const els = switch (form.value) {
            .list => |forms| forms,
            else => return error.Unexpected,
        };

        std.debug.assert(els.len > 0);

        switch (els[0].value) {
            .label => |label| {
                if (std.mem.eql(u8, label, "reg")) {
                    try self.registers.append(self.allocator, try self.reg(els[1..]));
                } else if (std.mem.eql(u8, label, "sync")) {} else if (std.mem.eql(u8, label, "connect")) {} else {
                    return error.Unexpected;
                }
            },
            else => return error.Unexpected,
        }
    }

    fn reg(self: Self, args: []const parser.Form) Error!Register {
        std.debug.assert(args.len >= 1);

        const name = try self.allocator.dupe(u8, args[0].value.label);
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

    pub fn finalise(self: *Self) ![]rtlil.Wire {
        var wires = std.ArrayListUnmanaged(rtlil.Wire){};
        errdefer {
            for (wires.items) |wire| wire.deinit(self.allocator);
            wires.deinit(self.allocator);
        }

        for (self.registers.items) |register| {
            std.debug.print("transforming register into wire: {}\n", .{register});
            try wires.append(self.allocator, .{
                .width = register.width,
                .name = try self.allocator.dupe(u8, register.name),
            });
        }

        return try wires.toOwnedSlice(self.allocator);
    }

    pub fn deinit(self: *Self) void {
        for (self.registers.items) |register| register.deinit(self.allocator);
        self.registers.deinit(self.allocator);
    }
};

pub fn eval(allocator: Allocator, doc: parser.Doc) ![]rtlil.Module {
    var compiler = Compiler.mk(allocator);
    defer compiler.deinit();

    for (doc.forms) |form| {
        try compiler.top(form);
    }

    const wires = try compiler.finalise();

    const module = rtlil.Module{
        .name = "top",
        .wires = wires,
    };

    return try allocator.dupe(rtlil.Module, &.{module});
}
