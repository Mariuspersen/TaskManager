const std = @import("std");
const zon = @import("build.zig.zon");

pub fn build(b: *std.Build) void {
    const name = @tagName(zon.name);
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const main = b.addModule(name, .{
        .optimize = optimize,
        .target = target,
        .root_source_file = b.path("src/main.zig"),
    });

    const exe = b.addExecutable(.{
        .name = name,
        .root_module = main
    });
    const install = b.addInstallArtifact(exe, .{});
    b.getInstallStep().dependOn(&install.step);
}
