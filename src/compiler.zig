const std = @import("std");
const Allocator = std.mem.Allocator;
const ast = @import("ast.zig");
const rtlil = @import("rtlil.zig");
const common = @import("common.zig");

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
        common.deinit(self.allocator, &self.registers);
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
                } else if (std.mem.eql(u8, label, "sync")) {
                    // TODO
                } else if (std.mem.eql(u8, label, "connect")) {
                    // TODO
                } else {
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

        const init: ?Register.Init = init: {
            if (args.len >= 3) {
                switch (args[2].value) {
                    .number => |number| break :init .{ .number = @intCast(number) },
                    else => return error.Unexpected,
                }
            }
            break :init null;
        };

        return .{ .name = name, .width = width, .init = init };
    }

    fn finalise(self: *Self) !rtlil.Doc {
        var wires = std.ArrayListUnmanaged(rtlil.Wire){};
        var connections = std.ArrayListUnmanaged(rtlil.Connection){};
        errdefer {
            common.deinit(self.allocator, &wires);
            common.deinit(self.allocator, &connections);
        }

        for (self.registers.items) |register| {
            {
                const name = try self.allocator.dupe(u8, register.name);
                errdefer self.allocator.free(name);
                try wires.append(self.allocator, .{
                    .name = name,
                    .width = register.width,
                });
            }
            if (register.init) |init| {
                const name = try self.allocator.dupe(u8, register.name);
                errdefer self.allocator.free(name);
                const target = try init.rvalue(self.allocator);
                errdefer target.deinit(self.allocator);
                try connections.append(self.allocator, .{
                    .name = name,
                    .target = target,
                });
            }
        }

        var modules = try self.allocator.alloc(rtlil.Module, 1);
        modules[0] = .{ .name = "" };
        errdefer common.deinit(self.allocator, modules);

        const name = try self.allocator.dupe(u8, "\\top");
        errdefer self.allocator.free(name);

        const o_wires = try wires.toOwnedSlice(self.allocator);
        errdefer common.deinit(self.allocator, o_wires);

        const o_connections = try connections.toOwnedSlice(self.allocator);

        modules[0] = rtlil.Module{
            .name = name,
            .wires = o_wires,
            .connections = o_connections,
        };

        return rtlil.Doc.fromModules(modules);
    }
};

// A register is a wire which has an initial value and is updated synchronously.
const Register = struct {
    const Self = @This();

    const Init = union(enum) {
        bv: []u1,
        number: i32,

        fn rvalue(self: Init, allocator: Allocator) Allocator.Error!rtlil.RValue {
            return switch (self) {
                .bv => |bv| .{ .bv = try rtlil.Bitvector.fromU1s(allocator, bv) },
                .number => |number| .{ .number = number },
            };
        }
    };

    name: []const u8,
    width: usize,
    init: ?Init,

    pub fn deinit(self: Self, allocator: Allocator) void {
        allocator.free(self.name);
        if (self.init) |init|
            switch (init) {
                .bv => |bv| allocator.free(bv),
                else => {},
            };
    }
};

fn expectCompilesTo(allocator: Allocator, input: []const u8, il: []const u8) !void {
    const doc = try compileBuffer(allocator, input);
    defer doc.deinit(allocator);

    const expIl = try rtlil.Doc.parse(allocator, il);
    defer expIl.deinit(allocator);

    const output = try rtlil.allocOutput(allocator, doc);
    defer allocator.free(output);

    try std.testing.expectEqualDeep(expIl, doc);
}

test "compile - CAAF" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, compileTest, .{});
}

fn compileTest(allocator: Allocator) !void {
    try expectCompilesTo(allocator,
        \\(reg x 8)
    ,
        \\module \top
        \\  wire width 8 \x
        \\end
    );

    try expectCompilesTo(allocator,
        \\(reg x 8 -2)
    ,
        \\module \top
        \\  wire width 8 \x
        \\  connect \x -2
        \\end
    );

    try expectCompilesTo(allocator,
        \\(reg x 8)
        \\(sync (set x (add x 1)))
    ,
        \\module \top
        \\  wire width 1 \clk
        \\  wire width 1 \rst
        \\  wire width 8 \x
        \\  wire width 8 $1
        \\  wire width 8 $2
        \\  cell $dff $3
        \\    parameter \WIDTH 8
        \\    parameter \CLK_POLARITY 1
        \\    connect \D $1
        \\    connect \CLK \clk
        \\    connect \Q \x
        \\  end
        \\  cell $add $4
        \\    parameter \A_SIGNED 0
        \\    parameter \B_SIGNED 0
        \\    parameter \A_WIDTH 8
        \\    parameter \B_WIDTH 8
        \\    parameter \Y_WIDTH 8
        \\    connect \A \x
        \\    connect \B 8'00000001
        \\    connect \Y $2
        \\  end
        \\  process $5
        \\    assign $1 $2
        \\    switch \rst
        \\      case 1'1
        \\        assign $1 0
        \\    end
        \\  end
        \\end
    );
}
