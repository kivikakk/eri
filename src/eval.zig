const std = @import("std");
const Allocator = std.mem.Allocator;
const Doc = @import("parser.zig").Doc;
const rtlil = @import("rtlil.zig");

pub fn eval(alloc: Allocator, doc: Doc) ![]rtlil.Module {
    _ = alloc;
    _ = doc;

    unreachable;
}
