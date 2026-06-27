const std = @import("std");

pub fn build(b: *std.Build) void {
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

    // run the build script in the build directory
    // TODO: inject `target` and `optimize` to the build script
    const build_script = b.addSystemCommand(&.{"./build.sh"});
    build_script.addDirectoryArg(build_dir); // the source directory
    const build_out = build_script.addOutputDirectoryArg("build_out"); // the install directory

    // FIXME: symbolic link files (.so, .so.X) were ignored during installation.
    // // install the build_out directory
    // b.installDirectory(.{
    //     .source_dir = build_out.path(b, ""),
    //     .install_dir = .prefix,
    //     .install_subdir = "",
    // });

    // install the header files
    b.installDirectory(.{
        .source_dir = build_out.path(b, "include"),
        .install_dir = .header,
        .install_subdir = "",
    });

    // install the library files
    const install_lib1 = b.addInstallLibFile(build_out.path(b, "lib/libwolfssl.a"), "libwolfssl.a");
    const install_lib2 = b.addInstallLibFile(build_out.path(b, "lib/libwolfssl.so"), "libwolfssl.so");
    const install_lib3 = b.addInstallLibFile(build_out.path(b, "lib/libwolfssl.so.45"), "libwolfssl.so.45");
    b.getInstallStep().dependOn(&install_lib1.step);
    b.getInstallStep().dependOn(&install_lib2.step);
    b.getInstallStep().dependOn(&install_lib3.step);
}
