const std = @import("std");
const net = std.Io.net;

const Allocator = std.mem.Allocator;

const hash = std.hash.Crc32.hash;

const Task = struct {
    text: []const u8,
    assignee: []const u8,

    pub fn init(alloc: Allocator, text: []const u8, assignee: []const u8) !Task {
        return .{
            .text = try alloc.dupe(u8, text),
            .assignee = try alloc.dupe(u8, assignee),
        };
    }

    pub fn deinit(self: Task, alloc: Allocator) void {
        alloc.free(self.text);
        alloc.free(self.assignee);
    }
};

const Tasks = struct {
    hm: std.AutoHashMap(u32, Task),
    const ENDIANESS: std.builtin.Endian = .little;
    const FILENAME = "tasks";

    pub fn init(alloc: Allocator) !Tasks {
        return .{
            .hm = .init(alloc),
        };
    }

    pub fn deinit(self: *Tasks, alloc: Allocator) void {
        var it = self.hm.valueIterator();
        while (it.next()) |task| {
            task.deinit(alloc);
        }
        self.hm.deinit();
    }

    pub fn saveToFile(self: *Tasks, io: std.Io, alloc: Allocator) !void {
        var it = self.hm.iterator();
        var f = try std.Io.Dir.cwd().createFile(io, FILENAME, .{});
        defer f.close(io);

        const buffer = try alloc.alloc(u8, 1024);
        defer alloc.free(buffer);

        var fw = f.writer(io, buffer);
        const writer = &fw.interface;
        defer writer.flush() catch {};

        while (it.next()) |entry| {
            try writer.writeInt(u32, entry.key_ptr.*, ENDIANESS);
            try writer.writeInt(usize, entry.value_ptr.assignee.len, ENDIANESS);
            try writer.writeAll(entry.value_ptr.assignee);
            try writer.writeInt(usize, entry.value_ptr.text.len, ENDIANESS);
            try writer.writeAll(entry.value_ptr.text);
        }
    }

    pub fn initFromFile(io: std.Io, alloc: Allocator) !Tasks {
        var tasks: Tasks = try .init(alloc);
        var f = try std.Io.Dir.cwd().openFile(io, FILENAME, .{});
        defer f.close(io);

        const buffer = try alloc.alloc(u8, 1024);
        defer alloc.free(buffer);

        var fr = f.reader(io, buffer);
        const reader = &fr.interface;

        while (true) {
            const key = reader.takeInt(u32, ENDIANESS) catch break;
            const assignee_len = reader.takeInt(usize, ENDIANESS) catch break;
            const asignee_slice = reader.take(assignee_len) catch break;
            const task_len = reader.takeInt(usize, ENDIANESS) catch break;
            const task_slice = reader.take(task_len) catch break;
            const task = Task.init(alloc, task_slice, asignee_slice) catch break;
            tasks.hm.put(key, task) catch break;
        }
        return tasks;
    }
};

const address = net.IpAddress.parse("0.0.0.0", 430) catch |err| @compileError(err);
pub fn main(init: std.process.Init) !void {
    const stderr_buf = try init.gpa.alloc(u8, 1024);
    defer init.gpa.free(stderr_buf);
    var stderr_writer = std.Io.File.stderr().writer(init.io, stderr_buf);
    const stderr = &stderr_writer.interface;

    var tasks = Tasks.initFromFile(init.io, init.gpa) catch try Tasks.init(init.gpa);
    defer tasks.deinit(init.gpa);

    var server = try address.listen(init.io, .{ .reuse_address = true });
    while (server.accept(init.io)) |s| {
        defer s.close(init.io);
        handleConnection(
            init.io,
            init.gpa,
            s,
            &tasks,
        ) catch |e| {
            stderr.print("ERROR: {s}\n", .{@errorName(e)}) catch {};
            stderr.flush() catch {};
            continue;
        };
    } else |e| {
        try stderr.print("ERROR: {s}\n", .{@errorName(e)});
        try stderr.flush();
    }
}

fn handleConnection(
    io: std.Io,
    alloc: Allocator,
    s: net.Stream,
    tasks: *Tasks,
) !void {
    var read_buf: [4096]u8 = undefined;
    var write_buf: [4096]u8 = undefined;
    var reader = s.reader(io, &read_buf);
    var writer = s.writer(io, &write_buf);
    var http = std.http.Server.init(
        &reader.interface,
        &writer.interface,
    );

    var req = try http.receiveHead();
    const hashid = hash(req.head.target);

    switch (hashid) {
        hash("/") => try req.respond(@embedFile("index.html"), .{}),
        hash("/style.css") => try req.respond(@embedFile("style.css"), .{}),
        hash("/script.js") => try req.respond(@embedFile("script.js"), .{}),
        hash("/addtask.svg") => try req.respond(@embedFile("addtask.svg"), .{
            .extra_headers = &.{
                .{ .name = "Content-Type", .value = "image/svg+xml" },
            },
        }),
        hash("/changename.svg") => try req.respond(@embedFile("changename.svg"), .{
            .extra_headers = &.{
                .{ .name = "Content-Type", .value = "image/svg+xml" },
            },
        }),
        hash("/removetask") => block: {
            var it = req.iterateHeaders();
            while (it.next()) |h| {
                switch (hash(h.name)) {
                    hash("task") => {
                        const id = hash(h.value);
                        if (tasks.hm.get(id)) |entry| {
                            entry.deinit(alloc);
                            _ = tasks.hm.remove(id);
                        }
                    },
                    else => {},
                }
            }
            try tasks.saveToFile(io, alloc);
            break :block try req.respond("", .{});
        },
        hash("/addtask") => block: {
            var it = req.iterateHeaders();
            var task: []const u8 = undefined;
            var assignee: []const u8 = undefined;
            while (it.next()) |h| {
                switch (hash(h.name)) {
                    hash("task") => task = h.value,
                    hash("assignee") => assignee = h.value,
                    else => {},
                }
            }
            const ERROR_TEXT = "ERROR: Special characters not allowed!";
            for (task) |char| if (!std.ascii.isAscii(char) or char == ';') {
                break :block try req.respond(ERROR_TEXT, .{ .status = .not_acceptable });
            };
            for (assignee) |char| if (!std.ascii.isAscii(char) or char == ';') {
                break :block try req.respond(ERROR_TEXT, .{ .status = .not_acceptable });
            };
            if (tasks.hm.get(hash(task))) |exists| exists.deinit(alloc);
            try tasks.hm.put(hash(task), try .init(alloc, task, assignee));
            try tasks.saveToFile(io, alloc);
            break :block try req.respond(task, .{});
        },
        hash("/listtasks") => block: {
            var it = tasks.hm.iterator();
            var list_buf: [4096]u8 = undefined;
            var list = std.Io.Writer.fixed(&list_buf);
            while (it.next()) |entry| {
                try list.print("{s}:{s};", .{ entry.value_ptr.text, entry.value_ptr.assignee });
            }
            break :block try req.respond(list.buffered(), .{});
        },
        else => try req.respond("", .{ .status = .not_found }),
    }
}
