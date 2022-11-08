const std = @import("std");
const Builder = std.build.Builder;
const builtin = @import("builtin");

pub fn build(b: *Builder) void {
    const build_mode = b.standardReleaseOptions();

    // use a different cache folder for macos arm builds
    b.cache_root = if (builtin.os.tag == .macos and builtin.target.cpu.arch == .aarch64) "zig-arm-cache" else "zig-cache";

    const examples = [_][2][]const u8{
        [_][]const u8{ "view_vs_group", "examples/view_vs_group.zig" },
        [_][]const u8{ "group_sort", "examples/group_sort.zig" },
        [_][]const u8{ "simple", "examples/simple.zig" },
    };

    for (examples) |example, i| {
        const name = if (i == 0) "ecs" else example[0];
        const source = example[1];

        var exe = b.addExecutable(name, source);
        exe.setBuildMode(b.standardReleaseOptions());
        exe.setOutputDir(std.fs.path.join(b.allocator, &[_][]const u8{ b.cache_root, "bin" }) catch unreachable);
        exe.addPackagePath("ecs", "src/ecs.zig");
        exe.linkSystemLibrary("c");

        const docs = exe;
        docs.emit_docs = .emit;

        const doc = b.step("docs", "Generate documentation");
        doc.dependOn(&docs.step);

        const run_cmd = exe.run();
        const exe_step = b.step(name, b.fmt("run {s}.zig", .{name}));
        exe_step.dependOn(&run_cmd.step);

        // first element in the list is added as "run" so "zig build run" works
        if (i == 0) {
            const run_exe_step = b.step("run", b.fmt("run {s}.zig", .{name}));
            run_exe_step.dependOn(&run_cmd.step);
        }
    }

    // internal tests
    const internal_test_step = b.addTest("src/tests.zig");
    internal_test_step.setBuildMode(build_mode);

    // public api tests
    const test_step = b.addTest("tests/tests.zig");
    test_step.addPackagePath("ecs", "src/ecs.zig");
    test_step.setBuildMode(build_mode);

    const test_cmd = b.step("test", "Run the tests");
    test_cmd.dependOn(&internal_test_step.step);
    test_cmd.dependOn(&test_step.step);
}

pub const LibType = enum(i32) {
    static,
    dynamic, // requires DYLD_LIBRARY_PATH to point to the dylib path
    exe_compiled,
};

pub const pkg = std.build.Pkg{
    .name = "ecs",
    .source = .{ .path = libPath("/src/ecs.zig") },
};

fn libPath(comptime suffix: []const u8) []const u8 {
    if (suffix[0] != '/') @compileError("suffix must be an absolute path");
    return comptime blk: {
        const root_dir = std.fs.path.dirname(@src().file) orelse ".";
        break :blk root_dir ++ suffix;
    };
}

pub fn link(b: *Builder, step: *std.build.LibExeObjStep, lib_type: LibType) void {
    const build_mode = b.standardReleaseOptions();
    switch (lib_type) {
        .static => {
            const lib = b.addStaticLibrary("ecs", libPath("/src/ecs.zig"));
            lib.setBuildMode(build_mode);
            lib.install();

            step.linkLibrary(lib);
        },
        .dynamic => {
            const lib = b.addSharedLibrary("ecs", libPath("/src/ecs.zig"), .unversioned);
            lib.setBuildMode(build_mode);
            lib.install();

            step.linkLibrary(lib);
        },
        else => {},
    }
}
