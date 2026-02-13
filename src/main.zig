const std = @import("std");
const net = std.Io.net;

const Config = @import("config");

const Allocator = std.mem.Allocator;
const Cancelable = std.Io.Cancelable;

const hash = std.hash.Crc32.hash;

const ERROR_FMT = "ERROR: {s}\n";

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

    pub fn initFromFile(io: std.Io, alloc: Allocator) !Tasks {
        var tasks: Tasks = try .init(alloc);
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
};

const address = net.IpAddress.parse(Config.ip, Config.port) catch |err| @compileError(err);
pub fn main(init: std.process.Init.Minimal) !void {
    const alloc = std.heap.smp_allocator;

    var threaded = std.Io.Threaded.init(alloc, .{ .environ = init.environ });
    defer threaded.deinit();
    const io = threaded.io();
    var group = std.Io.Group.init;
    defer group.cancel(io);

    const stderr_buf = try alloc.alloc(u8, 1024);
    defer alloc.free(stderr_buf);
    var stderr_writer = std.Io.File.stderr().writer(io, stderr_buf);
    const stderr = &stderr_writer.interface;

    var tasks = Tasks.initFromFile(io, alloc) catch try Tasks.init(alloc);
    defer tasks.deinit(alloc);

    var server = try address.listen(io, .{ .reuse_address = true });
    defer server.deinit(io);
    while (true) {
        var accept = io.async(net.Server.accept, .{ &server, io });
        defer _ = accept.cancel(io) catch |e| {
            stderr.print(ERROR_FMT, .{@errorName(e)}) catch {};
            stderr.flush() catch {};
        };
        const stream = accept.await(io) catch |e| {
            stderr.print(ERROR_FMT, .{@errorName(e)}) catch {};
            stderr.flush() catch {};
            continue;
        };
        group.async(io, handleConnection, .{ io, alloc, stream, &tasks, stderr });
    }
}

fn handleConnection(
    io: std.Io,
    alloc: Allocator,
    s: net.Stream,
    tasks: *Tasks,
    w: *std.Io.Writer,
) void {
    defer s.close(io);

    var read_buf: [4096]u8 = undefined;
    var write_buf: [4096]u8 = undefined;
    var reader = s.reader(io, &read_buf);
    var writer = s.writer(io, &write_buf);
    var http = std.http.Server.init(
        &reader.interface,
        &writer.interface,
    );

    var req = http.receiveHead() catch |e| {
        w.print(ERROR_FMT, .{@errorName(e)}) catch {};
        w.flush() catch {};
        return;
    };
    const hashid = hash(req.head.target);

    const result = switch (hashid) {
        hash("/"), hash("/index.html") => req.respond(@embedFile("index.html"), .{}),
        hash("/style.css") => req.respond(@embedFile("style.css"), .{}),
        hash("/script.js") => req.respond(@embedFile("script.js"), .{}),
        hash("/favicon.ico") => req.respond(@embedFile("favicon.ico"), .{}),
        hash("/addtask.svg") => req.respond(@embedFile("addtask.svg"), .{
            .extra_headers = &.{
                .{ .name = "Content-Type", .value = "image/svg+xml" },
            },
        }),
        hash("/changename.svg") => req.respond(@embedFile("changename.svg"), .{
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
            tasks.saveToFile(io, alloc) catch |e| break :block e;
            break :block req.respond("", .{});
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
                break :block req.respond(ERROR_TEXT, .{ .status = .not_acceptable });
            };
            for (assignee) |char| if (!std.ascii.isAscii(char) or char == ';') {
                break :block req.respond(ERROR_TEXT, .{ .status = .not_acceptable });
            };
            if (tasks.hm.get(hash(task))) |exists| exists.deinit(alloc);
            tasks.hm.put(
                hash(task),
                Task.init(alloc, task, assignee) catch |e| break :block e,
            ) catch |e| break :block e;
            tasks.saveToFile(io, alloc) catch |e| break :block e;
            break :block req.respond(task, .{});
        },
        hash("/listtasks") => block: {
            var it = tasks.hm.iterator();
            var list_buf: [4096]u8 = undefined;
            var list = std.Io.Writer.fixed(&list_buf);
            while (it.next()) |entry| {
                list.print("{s}:{s};", .{
                    entry.value_ptr.text,
                    entry.value_ptr.assignee,
                }) catch |e| break :block e;
            }
            break :block req.respond(list.buffered(), .{});
        },
        else => req.respond("", .{ .status = .not_found }),
    };
    result catch |e| {
        w.print(ERROR_FMT, .{@errorName(e)}) catch {};
        w.flush() catch {};
        return;
    };
}
