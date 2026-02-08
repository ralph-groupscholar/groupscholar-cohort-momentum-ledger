const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const libpq_include = b.option([]const u8, "libpq-include", "Path to libpq include dir") orelse "/opt/homebrew/opt/libpq/include";
    const libpq_lib = b.option([]const u8, "libpq-lib", "Path to libpq lib dir") orelse "/opt/homebrew/opt/libpq/lib";

    const exe = b.addExecutable(.{
        .name = "cohort-momentum-ledger",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.addIncludePath(.{ .path = libpq_include });
    exe.addLibraryPath(.{ .path = libpq_lib });
    exe.linkSystemLibrary("pq");

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the CLI");
    run_step.dependOn(&run_cmd.step);
}
