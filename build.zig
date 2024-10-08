const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const neocities = b.addModule("neocities", .{
        .root_source_file = b.path("lib/Neocities.zig"),
    });

    const exe = b.addExecutable(.{
        .name = "neocities",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("Neocities", neocities);
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const lib_tests = b.addTest(.{
        .root_source_file = b.path("lib/Neocities.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_tests = b.addRunArtifact(lib_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);

    const release = b.step("release", "Make an upstream binary release");
    const release_targets: []const std.Target.Query = &.{
        .{ .cpu_arch = .aarch64, .os_tag = .macos },
        .{ .cpu_arch = .aarch64, .os_tag = .linux },
        .{ .cpu_arch = .x86_64, .os_tag = .linux },
        .{ .cpu_arch = .x86_64, .os_tag = .windows },
    };
    for (release_targets) |target_query| {
        const rel_exe = b.addExecutable(.{
            .name = "neocities",
            .root_source_file = b.path("src/main.zig"),
            .target = b.resolveTargetQuery(target_query),
            .optimize = .ReleaseSafe,
            .strip = true,
        });

        rel_exe.root_module.addImport("Neocities", neocities);
        const install = b.addInstallArtifact(rel_exe, .{});
        install.dest_dir = .prefix;
        install.dest_sub_path = b.fmt("{s}-{s}", .{
            target_query.zigTriple(b.allocator) catch unreachable,
            rel_exe.name,
        });

        release.dependOn(&install.step);
    }

    const fmt_step = b.step("fmt", "Format all source files");
    fmt_step.dependOn(&b.addFmt(.{ .paths = &.{ "build.zig", "src", "lib" } }).step);

    const clean_step = b.step("clean", "Remove build artifacts");
    clean_step.dependOn(&b.addRemoveDirTree(".zig-cache").step);
    clean_step.dependOn(&b.addRemoveDirTree("zig-out").step);
}
