const std = @import("std");
const builtin = @import("builtin");

/// Must match the `minimum_zig_version` in `build.zig.zon`.
const minimum_zig_version = "0.13.0";
/// Must match the `version` in `build.zig.zon`.
const version = std.SemanticVersion{ .major = 0, .minor = 1, .patch = 0 };

const Build = blk: {
    const current_zig = builtin.zig_version;
    const min_zig = std.SemanticVersion.parse(minimum_zig_version) catch unreachable;
    if (current_zig.order(min_zig) == .lt) {
        @compileError(std.fmt.comptimePrint("Your Zig version v{} does not meet the minimum build requirement of v{}", .{ current_zig, min_zig }));
    }
    break :blk std.Build;
};

pub fn build(b: *std.Build) !void {
    // Building targets for release.
    const build_options = b.addOptions();
    build_options.step.name = "build options";
    const build_options_module = build_options.createModule();
    build_options.addOption([]const u8, "minimum_zig_string", minimum_zig_version);
    build_options.addOption(std.SemanticVersion, "version", version);
    const build_all = b.option(bool, "build-all-targets", "Build all targets in ReleaseSafe mode.") orelse false;
    if (build_all) {
        try build_targets(b, build_options_module);
        return;
    }

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const libvaxis = b.dependency("vaxis", .{ .target = target }).module("vaxis");
    const fuzzig = b.dependency("fuzzig", .{ .target = target }).module("fuzzig");
    const exe = b.addExecutable(.{
        .name = "sftm",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("fuzzig", fuzzig);
    exe.root_module.addImport("vaxis", libvaxis);
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}

fn build_targets(b: *std.Build, build_options_module: *std.Build.Module) !void {
    const targets: []const std.Target.Query = &.{
        .{ .cpu_arch = .aarch64, .os_tag = .linux },
        .{ .cpu_arch = .x86_64, .os_tag = .linux },
    };

    for (targets) |t| {
        const target = b.resolveTargetQuery(t);
        const libvaxis = b.dependency("vaxis", .{ .target = target }).module("vaxis");
        const fuzzig = b.dependency("fuzzig", .{ .target = target }).module("fuzzig");

        const exe = b.addExecutable(.{
            .name = "sftm",
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = .ReleaseSafe,
        });
        exe.root_module.addImport("fuzzig", fuzzig);
        exe.root_module.addImport("vaxis", libvaxis);
        exe.root_module.addImport("options", build_options_module);
        b.installArtifact(exe);

        const target_output = b.addInstallArtifact(exe, .{
            .dest_dir = .{
                .override = .{
                    .custom = try t.zigTriple(b.allocator),
                },
            },
        });

        b.getInstallStep().dependOn(&target_output.step);
    }
}
