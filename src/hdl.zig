const std = @import("std");
const Allocator = std.mem.Allocator;
const rtlil = @import("rtlil.zig");
const common = @import("common.zig");

// pub const Compiler = struct {
//     const Self = @This();

//     const Error = error{Unexpected} || Allocator.Error;

//     allocator: Allocator,
//     registers: std.ArrayListUnmanaged(Register) = .{},

//     pub fn mk(allocator: Allocator) Self {
//         return .{ .allocator = allocator };
//     }

//     pub fn deinit(self: *Self) void {
//         common.deinit(self.allocator, &self.registers);
//     }

//     fn nomTop(self: *Self, form: ast.Form) Error!void {
//         const els = switch (form.value) {
//             .list => |forms| forms,
//             else => return error.Unexpected,
//         };

//         std.debug.assert(els.len > 0);

//         switch (els[0].value) {
//             .label => |label| {
//                 if (std.mem.eql(u8, label, "reg")) {
//                     const reg = try self.nomReg(els[1..]);
//                     errdefer reg.deinit(self.allocator);
//                     try self.registers.append(self.allocator, reg);
//                 } else if (std.mem.eql(u8, label, "sync")) {
//                     // TODO
//                 } else if (std.mem.eql(u8, label, "connect")) {
//                     // TODO
//                 } else {
//                     return error.Unexpected;
//                 }
//             },
//             else => return error.Unexpected,
//         }
//     }

//     fn nomReg(self: Self, args: []const ast.Form) Error!Register {
//         std.debug.assert(args.len >= 1);

//         const name = try std.fmt.allocPrint(self.allocator, "\\{s}", .{args[0].value.label});
//         errdefer self.allocator.free(name);

//         const width: usize = if (args.len >= 2) @intCast(args[1].value.number) else 1;

//         const init: ?Register.Init = init: {
//             if (args.len >= 3) {
//                 switch (args[2].value) {
//                     .number => |number| break :init .{ .number = @intCast(number) },
//                     else => return error.Unexpected,
//                 }
//             }
//             break :init null;
//         };

//         return .{ .name = name, .width = width, .init = init };
//     }

//     fn finalise(self: *Self) !rtlil.Doc {
//         var wires = std.ArrayListUnmanaged(rtlil.Wire){};
//         var connections = std.ArrayListUnmanaged(rtlil.Connection){};
//         errdefer {
//             common.deinit(self.allocator, &wires);
//             common.deinit(self.allocator, &connections);
//         }

//         for (self.registers.items) |register| {
//             {
//                 const name = try self.allocator.dupe(u8, register.name);
//                 errdefer self.allocator.free(name);
//                 try wires.append(self.allocator, .{
//                     .name = name,
//                     .width = register.width,
//                 });
//             }
//             if (register.init) |init| {
//                 const name = try self.allocator.dupe(u8, register.name);
//                 errdefer self.allocator.free(name);
//                 const target = try init.rvalue(self.allocator);
//                 errdefer target.deinit(self.allocator);
//                 try connections.append(self.allocator, .{
//                     .name = name,
//                     .target = target,
//                 });
//             }
//         }

//         var modules = try self.allocator.alloc(rtlil.Module, 1);
//         modules[0] = .{ .name = "" };
//         errdefer common.deinit(self.allocator, modules);

//         const name = try self.allocator.dupe(u8, "\\top");
//         errdefer self.allocator.free(name);

//         const o_wires = try wires.toOwnedSlice(self.allocator);
//         errdefer common.deinit(self.allocator, o_wires);

//         const o_connections = try connections.toOwnedSlice(self.allocator);

//         modules[0] = rtlil.Module{
//             .name = name,
//             .wires = o_wires,
//             .connections = o_connections,
//         };

//         return rtlil.Doc.fromModules(modules);
//     }
// };

pub var arena: std.mem.Allocator = undefined;

const Where = enum { lv, rv };

pub const Signal = struct {
    name: []const u8,
    size: usize,

    pub fn make(name: []const u8, size: usize) *Signal {
        const self = arena.create(Signal) catch unreachable;
        self.* = .{
            .name = name,
            .size = size,
        };
        return self;
    }

    pub fn dump(self: *const Signal, where: Where) void {
        switch (where) {
            .lv => std.debug.print("<Signal {s} ({d})>", .{ self.name, self.size }),
            .rv => std.debug.print("{s}", .{self.name}),
        }
    }

    pub fn eq(self: *Signal, rhs: anytype) *Stmt {
        const stmt = arena.create(Stmt) catch unreachable;
        stmt.* = .{ .eq = .{
            .lhs = self,
            .rhs = Expr.make(rhs),
        } };
        return stmt;
    }

    pub fn expr(self: *Signal) *Expr {
        return Expr.make(self);
    }
};

const Stmt = union(enum) {
    const Eq = struct {
        lhs: *Signal,
        rhs: *Expr,
    };

    eq: Eq,

    pub fn dump(self: *const Stmt) void {
        switch (self.*) {
            .eq => |eq| {
                eq.lhs.dump(.lv);
                std.debug.print(" = ", .{});
                eq.rhs.dump();
                std.debug.print("\n", .{});
            },
        }
    }
};

const Expr = struct {
    value: union(enum) {
        const BinopKind = enum { add };
        const Bit = struct {
            expr: *Expr,
            ix: usize,
        };
        const Binop = struct {
            kind: BinopKind,
            lhs: *Expr,
            rhs: *Expr,
        };

        signal: *Signal,
        int: usize,
        bit: Bit,
        binop: Binop,
    },

    pub fn make(e: anytype) *Expr {
        if (@TypeOf(e) == *Expr)
            return e;

        const expr = arena.create(Expr) catch unreachable;
        switch (@TypeOf(e)) {
            *Signal => expr.* = .{ .value = .{ .signal = e } },
            comptime_int => expr.* = .{ .value = .{ .int = e } },
            else => @compileError("Expr.make with " ++ @typeName(@TypeOf(e))),
        }
        return expr;
    }

    pub fn size(self: *const Expr) usize {
        return switch (self.value) {
            .signal => |signal| signal.size,
            .int => std.debug.panic("trying to get size of literal", .{}),
            .bit => 1,
            .binop => |binop| @max(binop.lhs.size(), binop.rhs.size()), // XXX
        };
    }

    pub fn add(self: *Expr, rhs: anytype) *Expr {
        const expr = arena.create(Expr) catch unreachable;
        expr.* = .{ .value = .{ .binop = .{
            .kind = .add,
            .lhs = self,
            .rhs = Expr.make(rhs),
        } } };
        return expr;
    }

    pub fn bit(self: *Expr, ix: isize) *Expr {
        const expr = arena.create(Expr) catch unreachable;
        expr.* = .{ .value = .{ .bit = .{
            .expr = self,
            .ix = if (ix >= 0)
                @intCast(ix)
            else
                @intCast(@as(isize, @intCast(self.size())) + ix),
        } } };
        return expr;
    }

    pub fn dump(self: *const Expr) void {
        switch (self.value) {
            .signal => |signal| signal.dump(.rv),
            .int => |int| std.debug.print("{d}", .{int}),
            .bit => |b| {
                b.expr.dump();
                std.debug.print("[{d}]", .{b.ix});
            },
            .binop => |binop| {
                std.debug.print("(", .{});
                binop.lhs.dump();
                std.debug.print(" ", .{});
                switch (binop.kind) {
                    .add => std.debug.print("+", .{}),
                }
                std.debug.print(" ", .{});
                binop.rhs.dump();
                std.debug.print(")", .{});
            },
        }
    }
};

pub const Module = struct {
    name: []const u8,
    combs: std.ArrayListUnmanaged(*Stmt) = .{},
    syncs: std.ArrayListUnmanaged(*Stmt) = .{},

    pub fn make(name: []const u8) *Module {
        const self = arena.create(Module) catch unreachable;
        self.* = .{ .name = name };
        return self;
    }

    pub fn dump(self: *const Module) void {
        std.debug.print("=== module {s} ===\n", .{self.name});
        std.debug.print("{d} comb(s)\n", .{self.combs.items.len});
        for (self.combs.items) |i|
            i.dump();
        std.debug.print("{d} sync(s)\n", .{self.syncs.items.len});
        for (self.syncs.items) |i|
            i.dump();
    }

    pub fn comb(self: *Module, args: anytype) void {
        inline for (args) |arg| {
            std.debug.assert(@TypeOf(arg) == *Stmt);
            self.combs.append(arena, arg) catch unreachable;
        }
    }

    pub fn sync(self: *Module, args: anytype) void {
        inline for (args) |arg| {
            std.debug.assert(@TypeOf(arg) == *Stmt);
            self.syncs.append(arena, arg) catch unreachable;
        }
    }
};

pub const Resource = struct {
    name: []const u8,
    o: *Signal,

    pub fn find(name: []const u8) *Resource {
        const self = arena.create(Resource) catch unreachable;
        self.* = .{
            .name = name,
            .o = Signal.make(
                std.fmt.allocPrint(arena, "{s}.o", .{name}) catch unreachable,
                1,
            ),
        };
        return self;
    }
};
