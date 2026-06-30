const std = @import("std");

pub fn build(b: *std.Build) !void {
    const allocator = b.allocator;
    const target = b.standardTargetOptions(.{});
    // const optimize = b.standardOptimizeOption(.{});

    // script options
    const zig_exe = b.graph.zig_exe;
    const zig_target = try target.result.zigTriple(allocator); // arch-os-abi (with os.version and abi.version)
    const linux_target = try target.result.linuxTriple(allocator); // arch-os-abi
    const zig_mcpu = try std.zig.serializeCpuAlloc(allocator, target.result.cpu); // cpu_model+features-features
    const lto_mode = b.option(std.zig.LtoMode, "lto", "enable link time optimization") orelse .none;
    const single_threaded = b.option(bool, "single_threaded", "single threaded mode for wolfssl") orelse false;

    var cc_optimize_buf: std.ArrayList(u8) = .empty;
    try cc_optimize_buf.appendSlice(allocator, "-g0 -O3 -Xclang -O3"); // -g0 and `-Xclang -O3` is required
    switch (lto_mode) {
        .none => {},
        .full => try cc_optimize_buf.appendSlice(allocator, " -flto=full"),
        .thin => try cc_optimize_buf.appendSlice(allocator, " -flto=thin"),
    }
    const cc_optimize = try cc_optimize_buf.toOwnedSlice(allocator);

    // script dependencies (rebuild is triggered when changes are made)
    var build_dep_buf = std.ArrayList(u8).empty;
    defer build_dep_buf.deinit(allocator);
    try build_dep_buf.print(allocator, "zig_exe={s}\n", .{zig_exe});
    try build_dep_buf.print(allocator, "zig_target={s}\n", .{zig_target});
    try build_dep_buf.print(allocator, "linux_target={s}\n", .{linux_target});
    try build_dep_buf.print(allocator, "zig_mcpu={s}\n", .{zig_mcpu});
    try build_dep_buf.print(allocator, "lto_mode={any}\n", .{lto_mode});
    try build_dep_buf.print(allocator, "single_threaded={any}\n", .{single_threaded});
    try build_dep_buf.print(allocator, "cc_optimize={s}\n", .{cc_optimize});
    const build_dep = try build_dep_buf.toOwnedSlice(allocator);

    // the source directory (readonly, from the original upstream)
    const source_dir = b.dependency("wolfssl_source", .{}).path("");

    // copy the source dir to the build directory
    const wf = b.addWriteFiles();
    wf.step.name = "copy wolfssl source";
    const build_dir = wf.addCopyDirectory(source_dir, "", .{});
    _ = wf.add(".wolfssl-zig@build.dep", build_dep); // trigger a rebuild if necessary

    // autogen.sh
    const autogen_sh = b.addSystemCommand(&.{"./autogen.sh"});
    autogen_sh.setCwd(build_dir);
    _ = autogen_sh.captureStdOut(); // tell zig that it has no side effects

    // configure
    const configure = b.addSystemCommand(&.{"./configure"});
    configure.step.dependOn(&autogen_sh.step);
    _ = configure.captureStdOut(); // tell zig that it has no side effects
    configure.setCwd(build_dir);
    configure.addArg(b.fmt("CC={s} cc -target {s} -mcpu={s}", .{ zig_exe, zig_target, zig_mcpu }));
    configure.addArg(b.fmt("CXX={s} c++ -target {s} -mcpu={s}", .{ zig_exe, zig_target, zig_mcpu }));
    configure.addArg(b.fmt("AR={s} ar", .{zig_exe}));
    configure.addArg(b.fmt("RANLIB={s} ranlib", .{zig_exe}));
    configure.addArg(b.fmt("CFLAGS={s} -ffunction-sections -fdata-sections", .{cc_optimize}));
    configure.addArg(b.fmt("CXXFLAGS={s} -ffunction-sections -fdata-sections", .{cc_optimize}));
    configure.addArg(b.fmt("LDFLAGS={s} -Wl,--gc-sections -Wl,-s", .{cc_optimize}));
    configure.addArg(b.fmt("--host={s}", .{linux_target})); // must use the linux target
    configure.addArg("--prefix=/usr"); // the logic install directory
    configure.addArg("--enable-jobserver=no"); // must be disabled (due to a bug in the wolfssl configure script)
    configure.addArg("--enable-static");
    configure.addArg("--disable-shared"); // we don't need shared library
    configure.addArg("--disable-openssl-compatible-defaults");
    configure.addArg("--disable-opensslextra");
    configure.addArg("--disable-oldnames");
    configure.addArg("--enable-alpn");
    configure.addArg("--enable-session-ticket");
    if (single_threaded)
        configure.addArg("--enable-singlethreaded");
    if (target.result.cpu.arch == .x86_64)
        configure.addArg("--enable-aesni");
    // TODO: add more configure options

    // make -j$(nproc)
    const make = b.addSystemCommand(&.{"make"});
    make.step.dependOn(&configure.step);
    _ = make.captureStdOut(); // tell zig that it has no side effects
    make.setCwd(build_dir);
    make.addArg(b.fmt("-j{d}", .{try std.Thread.getCpuCount()}));

    // make install DESTDIR=build_out
    const make_install = b.addSystemCommand(&.{ "make", "install" });
    make_install.step.dependOn(&make.step);
    make_install.setName("run make install");
    make_install.setCwd(build_dir);
    _ = make_install.captureStdOut(); // tell zig that it has no side effects
    const build_out = make_install.addPrefixedOutputDirectoryArg("DESTDIR=", "build_out").path(b, "usr");

    // export the artifact
    b.addNamedLazyPath("include", build_out.path(b, "include"));
    b.addNamedLazyPath("lib", build_out.path(b, "lib"));
    b.addNamedLazyPath("libwolfssl.a", build_out.path(b, "lib/libwolfssl.a"));

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
