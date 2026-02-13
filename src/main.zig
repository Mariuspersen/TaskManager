const std = @import("std");
const net = std.Io.net;

const Config = @import("config");

const Allocator = std.mem.Allocator;
const Cancelable = std.Io.Cancelable;

const hash = std.hash.Crc32.hash;

const ERROR_FMT = "ERROR: {s}\n";

const Tasks = @import("tasks.zig");

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

    var s_read_buf: [4096]u8 = undefined;
    var s_write_buf: [4096]u8 = undefined;
    var s_reader = s.reader(io, &s_read_buf);
    var s_writer = s.writer(io, &s_write_buf);
    var http = std.http.Server.init(
        &s_reader.interface,
        &s_writer.interface,
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
                    hash("task") => tasks.removeTask(alloc, h.value),
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
            tasks.addTask(alloc, task, assignee) catch |e| break :block e;
            tasks.saveToFile(io, alloc) catch |e| break :block e;
            break :block req.respond(task, .{});
        },
        hash("/listtasks") => block: {
            var allocating = std.Io.Writer.Allocating.init(alloc);
            defer allocating.deinit();
            const writer = &allocating.writer;
            tasks.listTasks(writer) catch |e| break :block e;
            break :block req.respond(writer.buffered(), .{});
        },
        else => req.respond("", .{ .status = .not_found }),
    };
    result catch |e| {
        w.print(ERROR_FMT, .{@errorName(e)}) catch {};
        w.flush() catch {};
        return;
    };
}
