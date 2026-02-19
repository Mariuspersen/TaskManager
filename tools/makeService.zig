const std = @import("std");
const Config = @import("config");

const Dir = std.Io.Dir;
const Path = std.fs.path;

pub fn main(init: std.process.Init) !void {
    defer std.process.cleanExit(init.io);
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    const alloc = arena.allocator();
    defer _ = arena.reset(.free_all);
    const io = init.io;

    var args = try init.minimal.args.iterateAllocator(alloc);

    _ = args.skip();
    const path = args.next() orelse return error.NoArgumentsGiven;
    var f = try Dir.cwd().createFile(io, path, .{});
    defer f.close(io);

    const pathBuf = try alloc.alloc(u8, 1024);
    const len = try Dir.cwd().realPath(io, pathBuf);
    const abs_path = pathBuf[0..len];

    const binPath = try Path.join(alloc, &.{
        abs_path,
        "zig-out",
        "bin",
        @tagName(Config.name),
    });

    var fwriter = f.writer(io, try alloc.alloc(u8, 1024));
    const writer = &fwriter.interface;

    try writer.print(
        \\[Unit]
        \\Description=Web Server for a Kanban-like task board
        \\After=network.target
        \\[Service]
        \\ExecStart={s}
        \\WorkingDirectory={s}
        \\Restart=always
        \\[Install]
        \\WantedBy=multi-user.target
    , .{
        binPath,
        Path.dirname(binPath) orelse return error.CantResolveDirname,
    });

    try writer.flush();
}
