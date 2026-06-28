const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // the source files (autotools build system)
    const source = b.dependency("wolfssl_source", .{
        .target = target,
        .optimize = optimize,
    });

    // copy the source files to the build directory
    const wf = b.addWriteFiles();
    const build_dir = wf.addCopyDirectory(source.path(""), "", .{});

    // zig cc -target <target> -mcpu <cpu>
    const zig_exe = b.graph.zig_exe;
    const zig_target = try target.result.linuxTriple(b.allocator); // TODO: check the triple description
    const zig_mcpu = try std.zig.serializeCpuAlloc(b.allocator, target.result.cpu); // NOTE: cannot be `native`
    const lto_mode = b.option(std.zig.LtoMode, "lto", "enable link time optimization") orelse .none;
    const single_threaded = b.option(bool, "single-threaded", "single threaded mode for wolfssl") orelse false;

    // run the build script in the build directory
    const build_script = b.addSystemCommand(&.{"./build.sh"});
    build_script.addDirectoryArg(build_dir); // the source directory
    const build_out = build_script.addOutputDirectoryArg("build_out"); // the install directory
    build_script.addArgs(&.{
        zig_exe,
        zig_target,
        zig_mcpu,
        @tagName(lto_mode),
        if (single_threaded) "1" else "0",
    });

    // install the header files
    b.installDirectory(.{
        .source_dir = build_out.path(b, "include"),
        .install_dir = .header,
        .install_subdir = "",
    });

    // install the library files
    const install_lib = b.addInstallLibFile(build_out.path(b, "lib/libwolfssl.a"), "libwolfssl.a");
    b.getInstallStep().dependOn(&install_lib.step);
}
