const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "zm",
        .root_module = exe_mod,
    });

    b.installArtifact(exe);

    const zglfw = b.dependency("zglfw", .{
        .target = target,
    });
    exe.root_module.addImport("zglfw", zglfw.module("root"));
    exe.linkLibrary(zglfw.artifact("glfw"));

    const zgpu = b.dependency("zgpu", .{
        .target = target,
    });
    exe.root_module.addImport("zgpu", zgpu.module("root"));
    exe.linkLibrary(zgpu.artifact("zdawn"));

    if (target.result.os.tag == .linux and target.result.cpu.arch.isX86()) {
        const dawn_prebuilt = zgpu.builder.dependency("dawn_x86_64_linux_gnu", .{});
        exe.addLibraryPath(dawn_prebuilt.path(""));
    } else if (target.result.os.tag == .windows) {
        const dawn_prebuilt = zgpu.builder.dependency("dawn_x86_64_windows_gnu", .{});
        exe.addLibraryPath(dawn_prebuilt.path(""));
    }

    const zstbi = b.dependency("zstbi", .{});
    exe.root_module.addImport("zstbi", zstbi.module("root"));

    const zmath = b.dependency("zmath", .{});
    exe.root_module.addImport("zmath", zmath.module("root"));

    const znoise = b.dependency("znoise", .{});
    exe.root_module.addImport("znoise", znoise.module("root"));
    exe.linkLibrary(znoise.artifact("FastNoiseLite"));

    const box2d = b.dependency("box2d", .{
        .target = target,
        .optimize = optimize,
    });
    exe.linkLibrary(box2d.artifact("box2d"));

    // ---
    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.setCwd(.{ .cwd_relative = "." });

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_module = exe_mod,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
