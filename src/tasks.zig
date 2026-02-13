const std = @import("std");
const Task = @import("task.zig");
const Config = @import("config");

const Self = @This();
const Allocator = std.mem.Allocator;

const hash = std.hash.Crc32.hash;

hm: std.AutoHashMap(u32, Task),

pub fn init(alloc: Allocator) !Self {
    return .{
        .hm = .init(alloc),
    };
}

pub fn initFromFile(io: std.Io, alloc: Allocator) !Self {
    var tasks = try Self.init(alloc);
    var f = try std.Io.Dir.cwd().openFile(io, Config.filename, .{});
    defer f.close(io);

    const buffer = try alloc.alloc(u8, 1024);
    defer alloc.free(buffer);

    var fr = f.reader(io, buffer);
    const reader = &fr.interface;

    while (true) {
        const key = reader.takeInt(u32, Config.endianess) catch break;
        const assignee_len = reader.takeInt(usize, Config.endianess) catch break;
        const asignee_slice = reader.take(assignee_len) catch break;
        const task_len = reader.takeInt(usize, Config.endianess) catch break;
        const task_slice = reader.take(task_len) catch break;
        const task = Task.init(alloc, task_slice, asignee_slice) catch break;
        tasks.hm.put(key, task) catch break;
    }
    return tasks;
}

pub fn deinit(self: *Self, alloc: Allocator) void {
    var it = self.hm.valueIterator();
    while (it.next()) |task| {
        task.deinit(alloc);
    }
    self.hm.deinit();
}

pub fn addTask(self: *Self, alloc: Allocator, task: []const u8, assignee: []const u8) !void {
    if (self.hm.getPtr(hash(task))) |exists| {
        try exists.changeAssignee(alloc, assignee);
    } else {
        try self.hm.put(
            hash(task),
            try Task.init(alloc, task, assignee),
        );
    }
}

pub fn listTasks(self: *Self, writer: *std.Io.Writer) !void {
    var it = self.hm.iterator();
    while (it.next()) |entry| {
        try writer.print("{s}:{s};", .{
            entry.value_ptr.text,
            entry.value_ptr.assignee,
        });
    }
}

pub fn removeTask(self: *Self, alloc: Allocator, task: []const u8) void {
    if (self.hm.fetchRemove(hash(task))) |kv| {
        kv.value.deinit(alloc);
    }
}

pub fn saveToFile(self: *Self, io: std.Io, alloc: Allocator) !void {
    var it = self.hm.iterator();
    var f = try std.Io.Dir.cwd().createFile(io, Config.filename, .{});
    defer f.close(io);

    const buffer = try alloc.alloc(u8, 1024);
    defer alloc.free(buffer);

    var fw = f.writer(io, buffer);
    const writer = &fw.interface;
    defer writer.flush() catch {};

    while (it.next()) |entry| {
        try writer.writeInt(u32, entry.key_ptr.*, Config.endianess);
        try writer.writeInt(usize, entry.value_ptr.assignee.len, Config.endianess);
        try writer.writeAll(entry.value_ptr.assignee);
        try writer.writeInt(usize, entry.value_ptr.text.len, Config.endianess);
        try writer.writeAll(entry.value_ptr.text);
    }
}
