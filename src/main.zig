const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    const bytes = try std.io.getStdIn().readToEndAlloc(alloc, 1048576);

    try stdout.print("evaluating: {s}\n", .{bytes});
    try bw.flush();
}

comptime {
    std.testing.refAllDecls(@import("test.zig"));
}
