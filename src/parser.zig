const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn parse(alloc: Allocator, input: []const u8) !Doc {
    _ = alloc;
    _ = input;

    unreachable;
}

pub const Doc = struct {
    const Self = @This();

    forms: []Form,

    pub fn fromForms(forms: []Form) Self {
        return Self{
            .forms = forms,
        };
    }

    pub fn deinit(self: *const Self, alloc: Allocator) void {
        for (self.forms) |*form| {
            form.deinit(alloc);
        }
        alloc.free(self.forms);
        alloc.destroy(self);
    }
};

pub const Form = union(enum) {
    const Self = @This();

    number: u64,
    label: []const u8,
    list: []Form,

    pub fn deinit(self: *const Self, alloc: Allocator) void {
        switch (self.*) {
            .number => |_| {},
            .label => |l| alloc.free(l),
            .list => |fs| {
                for (fs) |f| {
                    f.deinit(alloc);
                }
                alloc.free(fs);
            },
        }
        alloc.destroy(self);
    }
};
