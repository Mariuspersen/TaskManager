const std = @import("std");
const zon = @import("build.zig.zon");

pub fn build(b: *std.Build) void {
    const name = @tagName(zon.name);
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const config = b.addModule("config", .{
        .root_source_file = b.path("build.zig.zon"),
    });

    const main = b.addModule(name, .{
        .optimize = optimize,
        .target = target,
        .root_source_file = b.path("src/main.zig"),
    });

    const exe = b.addExecutable(.{ .name = name, .root_module = main });
    exe.root_module.addImport("config", config);
    const install = b.addInstallArtifact(exe, .{});
    b.getInstallStep().dependOn(&install.step);

    const service = b.addModule(name, .{
        .optimize = optimize,
        .target = b.graph.host,
        .root_source_file = b.path("tools/makeService.zig"),
    });
    const serviceExe = b.addExecutable(.{
        .name = "service",
        .root_module = service,
    });
    serviceExe.root_module.addImport("config", config);
    const serviceRun = b.addRunArtifact(serviceExe);
    const filepath = serviceRun.addOutputFileArg(@tagName(zon.name) ++ ".service");
    const install_service = b.addInstallFileWithDir(filepath, .prefix, @tagName(zon.name) ++ ".service");
    b.getInstallStep().dependOn(&install_service.step);
}