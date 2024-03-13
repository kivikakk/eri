const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn deinit(allocator: Allocator, what: anytype) void {
    const T = @TypeOf(what);
    switch (@typeInfo(T)) {
        .Pointer => |pointer| {
            // assuming it's:
            // - []X where X has a deinit member function; or,
            // - std.ArrayListUnmanaged(X) where X has a deinit member function.

            if (pointer.size == .Slice) {
                for (what) |*el| el.deinit(allocator);
                allocator.free(what);
            } else {
                for (what.items) |*el| el.deinit(allocator);
                what.deinit(allocator);
            }
        },
        else => @panic("deinit unsupported type: " ++ @typeName(T)),
    }
}
