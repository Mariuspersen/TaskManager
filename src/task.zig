const Self = @This();
const std = @import("std");

const Allocator = std.mem.Allocator;

text: []const u8,
assignee: []const u8,

pub fn init(alloc: Allocator, text: []const u8, assignee: []const u8) !Self {
    return .{
        .text = try alloc.dupe(u8, text),
        .assignee = try alloc.dupe(u8, assignee),
    };
}

pub fn deinit(self: Self, alloc: Allocator) void {
    alloc.free(self.text);
    alloc.free(self.assignee);
}

pub fn changeAssignee(self: *Self, alloc: Allocator, new_assignee: []const u8) !void {
    alloc.free(self.assignee);
    self.assignee = try alloc.dupe(u8, new_assignee);
}
