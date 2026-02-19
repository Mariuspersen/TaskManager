const std = @import("std");
const Tasks = @import("tasks.zig");
const Config = @import("config");

const net = std.Io.net;
const Allocator = std.mem.Allocator;
const hash = std.hash.Crc32.hash;
const ERROR_FMT = "ERROR: {s}\n";

pub fn main(init: std.process.Init.Minimal) !void {
    const alloc = std.heap.smp_allocator;

    var threaded = std.Io.Threaded.init(alloc, .{ .environ = init.environ });
    defer threaded.deinit();
    const io = threaded.io();
    var group = std.Io.Group.init;
    defer group.cancel(io);

    var tasks = Tasks.initFromFile(io, alloc) catch try Tasks.init(alloc);
    defer tasks.deinit(alloc);

    const address = try net.IpAddress.resolve(io, Config.ip, Config.port);
    var server = try address.listen(io, .{ .reuse_address = true });
    defer server.deinit(io);
    while (server.accept(io)) |s| {
        try group.concurrent(
            io,
            handleConnectionWithTimeout,
            .{ io, alloc, s, &tasks },
        );
    } else |e| {
        var buffer: [64]u8 = undefined;
        const stderr = io.lockStderr(&buffer, null) catch return;
        stderr.file_writer.interface.print(
            ERROR_FMT,
            .{@errorName(e)},
        ) catch {};
    }
}

fn handleConnectionWithTimeout(
    io: std.Io,
    alloc: Allocator,
    s: net.Stream,
    tasks: *Tasks,
) void {
    var buffer: [64]u8 = undefined;
    var timeout = io.concurrent(
        std.Io.sleep,
        .{ io, .fromSeconds(Config.secs_timeout), .cpu_thread },
    ) catch {
        const stderr = io.lockStderr(&buffer, null) catch return;
        stderr.file_writer.interface.print(
            "ERROR: Unable to concurrently start std.Io.sleep\n",
            .{},
        ) catch {};
        return;
    };
    defer _ = timeout.cancel(io) catch {};
    var conn = io.concurrent(
        handleConnection,
        .{ io, alloc, &s, tasks },
    ) catch {
        const stderr = io.lockStderr(&buffer, null) catch return;
        stderr.file_writer.interface.print(
            "ERROR: Unable to concurrently start handleConnection\n",
            .{},
        ) catch {};
        return;
    };
    defer _ = conn.cancel(io) catch {};

    const result = std.Io.select(
        io,
        .{ &conn, &timeout },
    );
    if (result) |_| {} else |e| {
        const stderr = io.lockStderr(&buffer, null) catch return;
        stderr.file_writer.interface.print(
            "ERROR: Something happened during selection {any}\n",
            .{e},
        ) catch {};
        return;
    }
}

fn handleConnection(
    io: std.Io,
    alloc: Allocator,
    s: *const net.Stream,
    tasks: *Tasks,
) !void {
    errdefer |e| {
        var buffer: [64]u8 = undefined;
        if (io.lockStderr(&buffer, null)) |stderr| {
            stderr.file_writer.interface.print(
                ERROR_FMT,
                .{@errorName(e)},
            ) catch {};
        } else |_| {}
    }
    defer {
        s.shutdown(io, .both) catch {};
        s.close(io);
    }
    var s_read_buf: [4096]u8 = undefined;
    var s_write_buf: [4096]u8 = undefined;
    var s_reader = s.reader(io, &s_read_buf);
    var s_writer = s.writer(io, &s_write_buf);
    var http = std.http.Server.init(
        &s_reader.interface,
        &s_writer.interface,
    );

    var req = try http.receiveHead();
    const hashid = hash(req.head.target);

    switch (hashid) {
        hash("/"), hash("/index.html") => try req.respond(@embedFile("index.html"), .{}),
        hash("/style.css") => try req.respond(@embedFile("style.css"), .{}),
        hash("/script.js") => try req.respond(@embedFile("script.js"), .{}),
        hash("/favicon.ico") => try req.respond(@embedFile("favicon.ico"), .{}),
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
        hash("/removetask") => {
            var it = req.iterateHeaders();
            while (it.next()) |h| {
                switch (hash(h.name)) {
                    hash("task") => {
                        tasks.removeTask(alloc, h.value);
                        try tasks.saveToFile(io, alloc);
                    },
                    else => {},
                }
            }
            try req.respond("", .{});
        },
        hash("/addtask") => {
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
                try req.respond(ERROR_TEXT, .{ .status = .not_acceptable });
            };
            for (assignee) |char| if (!std.ascii.isAscii(char) or char == ';') {
                try req.respond(ERROR_TEXT, .{ .status = .not_acceptable });
            };
            try tasks.addTask(alloc, task, assignee);
            try tasks.saveToFile(io, alloc);
            try req.respond(task, .{});
        },
        hash("/listtasks") => {
            var allocating = std.Io.Writer.Allocating.init(alloc);
            defer allocating.deinit();
            const writer = &allocating.writer;
            try tasks.listTasks(writer);
            try req.respond(writer.buffered(), .{});
        },
        else => try req.respond("", .{ .status = .not_found }),
    }
}
