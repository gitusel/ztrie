const std = @import("std");
const Build = if (@hasDecl(std, "Build")) std.Build else std.build.Builder;
const OptimizeMode = if (@hasDecl(Build, "standardOptimizeOption")) std.builtin.OptimizeMode else std.builtin.Mode;
const CompileStep = if (@hasDecl(Build, "standardOptimizeOption")) std.build.CompileStep else std.build.LibExeObjStep;

pub fn build(b: *Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimize options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const optimize = if (@hasDecl(Build, "standardOptimizeOption")) b.standardOptimizeOption(.{}) else b.standardReleaseOptions();

    var exe: *CompileStep = undefined;
    if (@hasDecl(Build, "standardOptimizeOption")) {
        exe = b.addExecutable(.{
            .name = "ztrie",
            .root_source_file = .{ .path = "src/main.zig" },
            .optimize = optimize,
            .target = target,
        });
    } else {
        exe = b.addExecutable("ztrie", "src/main.zig");
        exe.setBuildMode(b.standardReleaseOptions());
        exe.setTarget(target);
    }
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    var exe_tests: *CompileStep = undefined;
    if (@hasDecl(Build, "standardOptimizeOption")) {
        exe_tests = b.addTest(.{
            .root_source_file = .{ .path = "src/main.zig" },
            .target = target,
            .optimize = optimize,
        });
    } else {
        exe_tests = b.addTest("src/main.zig");
        exe_tests.setBuildMode(optimize);
        exe_tests.setTarget(target);
    }

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&exe_tests.step);
}
