const std = @import("std");

const CommandGroup = struct {
    b: *std.Build,
    cwd: std.Build.LazyPath,
    last_command: ?*std.Build.Step.Run,

    pub fn init(b: *std.Build, cwd: std.Build.LazyPath) CommandGroup {
        return .{
            .b = b,
            .cwd = cwd,
            .last_command = null,
        };
    }

    pub const Options = struct {
        name: ?[]const u8 = null,
    };

    /// the stdout is captured and ignored
    pub fn add(self: *CommandGroup, program: []const u8, options: Options) *std.Build.Step.Run {
        const b = self.b;

        const command = b.addSystemCommand(&.{program});
        command.setCwd(self.cwd);
        _ = command.captureStdOut(); // tell zig that it has no side effects

        if (options.name) |name|
            command.setName(b.fmt("run {s}", .{name}));

        if (self.last_command) |last_command|
            command.step.dependOn(&last_command.step);
        self.last_command = command;

        return command;
    }
};

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
    const cc_optimize = switch (lto_mode) {
        .none => "-g0 -O3 -Xclang -O3",
        .full => "-g0 -O3 -Xclang -O3 -flto=full",
        .thin => "-g0 -O3 -Xclang -O3 -flto=thin",
    };

    // script dependencies (rebuild is triggered when changes are made)
    const build_dep = b.fmt(
        \\zig_exe={s}
        \\zig_target={s}
        \\linux_target={s}
        \\zig_mcpu={s}
        \\lto_mode={any}
        \\single_threaded={any}
        \\cc_optimize={s}
    , .{
        zig_exe,
        zig_target,
        linux_target,
        zig_mcpu,
        lto_mode,
        single_threaded,
        cc_optimize,
    });

    // the source directory (readonly, from the original upstream)
    const source_dir = b.dependency("wolfssl_source", .{}).path("");

    // copy the source dir to the build directory
    const wf = b.addWriteFiles();
    wf.step.name = "copy wolfssl source";
    const build_dir = wf.addCopyDirectory(source_dir, "", .{});
    _ = wf.add(".wolfssl-zig@build.dep", build_dep); // trigger a rebuild if necessary

    var cmd_group = CommandGroup.init(b, build_dir);

    // autogen.sh
    _ = cmd_group.add("./autogen.sh", .{});

    // configure
    const configure = cmd_group.add("./configure", .{});
    configure.addArg(b.fmt("CC={s} cc -target {s} -mcpu={s}", .{ zig_exe, linux_target, zig_mcpu }));
    configure.addArg(b.fmt("CXX={s} c++ -target {s} -mcpu={s}", .{ zig_exe, linux_target, zig_mcpu }));
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
    const make = cmd_group.add("make", .{});
    make.addArg(b.fmt("-j{d}", .{std.Thread.getCpuCount() catch 2}));

    // make install DESTDIR=build_out
    const make_install = cmd_group.add("make", .{ .name = "make install" });
    make_install.addArg("install");
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
