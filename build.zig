const std = @import("std");
const assert = std.debug.assert;

const CommandSequence = struct {
    b: *std.Build,
    cwd: std.Build.LazyPath,
    last_command: ?*std.Build.Step.Run,

    pub fn init(b: *std.Build, cwd: std.Build.LazyPath) CommandSequence {
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
    pub fn add(self: *CommandSequence, program: []const u8, options: Options) *std.Build.Step.Run {
        const b = self.b;

        const command = b.addSystemCommand(&.{program});
        command.setCwd(self.cwd);
        _ = command.captureStdOut(); // tell zig that it has no side effects

        if (options.name) |name|
            command.setName(name);

        if (self.last_command) |last_command|
            command.step.dependOn(&last_command.step);
        self.last_command = command;

        return command;
    }
};

const ZMake = struct {
    b: *std.Build,
    name: []const u8,
    build_system_type: BuildSystemType,
    source_dir: std.Build.LazyPath,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    lto: std.zig.LtoMode,
    separate_sections: bool,
    gc_sections: bool,
    strip: bool,
    run_autogen: bool,
    configure_args: std.ArrayList([]const u8),

    pub const BuildSystemType = enum {
        /// ./configure && make && make install
        autotools,
        /// TODO: to be implemented
        cmake,
        /// TODO: to be implemented
        makefile,
    };

    pub const CreateOption = struct {
        build_system_type: BuildSystemType,
        source_dir: std.Build.LazyPath,
        target: ?std.Build.ResolvedTarget = null,
        optimize: std.builtin.OptimizeMode = .ReleaseFast,
        lto: std.zig.LtoMode = .none,
        /// -ffunction-sections -fdata-sections
        separate_sections: bool = true,
        /// -Wl,--gc-sections
        gc_sections: bool = true,
        /// null: based on the `optimize`
        strip: ?bool = null,
        /// run ./autogen.sh before ./configure ?
        run_autogen: bool = false,
    };

    fn check_build_system_type(build_system_type: BuildSystemType) void {
        switch (build_system_type) {
            .autotools => {},
            .cmake => @panic("TODO: to be implemented"),
            .makefile => @panic("TODO: to be implemented"),
        }
    }

    pub fn create(b: *std.Build, name: []const u8, opt: CreateOption) *ZMake {
        check_build_system_type(opt.build_system_type);
        const self = b.allocator.create(ZMake) catch unreachable;
        self.* = .{
            .b = b,
            .name = b.dupe(name),
            .build_system_type = opt.build_system_type,
            .source_dir = opt.source_dir,
            .target = opt.target orelse b.graph.host,
            .optimize = opt.optimize,
            .lto = opt.lto,
            .separate_sections = opt.separate_sections,
            .gc_sections = opt.gc_sections,
            .strip = switch (opt.optimize) {
                .Debug => false,
                .ReleaseSafe => false,
                .ReleaseSmall => true,
                .ReleaseFast => true,
            },
            .run_autogen = opt.run_autogen,
            .configure_args = .empty,
        };
        return self;
    }

    pub fn add_configure_arg(self: *ZMake, arg: []const u8) void {
        const b = self.b;
        self.configure_args.append(b.allocator, b.dupe(arg)) catch unreachable;
    }

    /// return the path to the `build_out` directory
    pub fn build(self: *ZMake) std.Build.LazyPath {
        check_build_system_type(self.build_system_type);

        const b = self.b;
        const allocator = b.allocator;

        // build options
        const zig_exe = b.graph.zig_exe;
        const zig_target = self.target.result.zigTriple(allocator) catch unreachable; // arch-os-abi (with os.version and abi.version)
        const linux_target = self.target.result.linuxTriple(allocator) catch unreachable; // arch-os-abi
        const zig_mcpu = std.zig.serializeCpuAlloc(allocator, self.target.result.cpu) catch unreachable; // cpu_model+features-features
        const f_raw_optimize = switch (self.optimize) {
            .Debug => "-g3 -O0",
            .ReleaseSafe => "-g1 -O2",
            .ReleaseSmall => "-g0 -Os",
            .ReleaseFast => "-g0 -O3 -Xclang -O3",
        };
        const f_optimize = switch (self.lto) {
            .none => f_raw_optimize,
            .full => b.fmt("{s} -flto=full", .{f_raw_optimize}),
            .thin => b.fmt("{s} -flto=thin", .{f_raw_optimize}),
        };
        const f_separate_sections = if (self.separate_sections) "-ffunction-sections -fdata-sections" else "";
        const f_gc_sections = if (self.gc_sections) "-Wl,--gc-sections" else "";
        const f_strip = if (self.strip) "-Wl,-s" else "";

        var description_buf: std.ArrayList(u8) = .empty;
        defer description_buf.deinit(allocator);

        // description of the build (rebuild when changes occur)
        const base_description = b.fmt(
            \\# Generated by zmake
            \\magic: {d}
            \\zig_exe: {s}
            \\zig_target: {s}
            \\linux_target: {s}
            \\zig_mcpu: {s}
            \\optimize: {s}
            \\lto: {s}
            \\f_optimize: {s}
            \\f_separate_sections: {s}
            \\f_gc_sections: {s}
            \\f_strip: {s}
            \\build_system_type: {s}
            \\run_autogen: {any}
            \\
        , .{
            1, // change this when the build logic changes
            zig_exe,
            zig_target,
            linux_target,
            zig_mcpu,
            @tagName(self.optimize),
            @tagName(self.lto),
            f_optimize,
            f_separate_sections,
            f_gc_sections,
            f_strip,
            @tagName(self.build_system_type),
            self.run_autogen,
        });
        description_buf.appendSlice(allocator, base_description) catch unreachable;

        // the configure arguments also need to be included in the description
        for (self.configure_args.items, 0..) |arg, i| {
            const arg_description = b.fmt("configure_arg[{d}]: {s}\n", .{ i, arg });
            description_buf.appendSlice(allocator, arg_description) catch unreachable;
        }

        const description = description_buf.toOwnedSlice(allocator) catch unreachable;

        // copy the source dir to the build directory
        const wf = b.addWriteFiles();
        wf.step.name = self.get_step_name("copy source");
        const build_dir = wf.addCopyDirectory(self.source_dir, "", .{});
        _ = wf.add(".zmake_build.desc", description); // trigger rebuild if necessary

        var cmd_seq = CommandSequence.init(b, build_dir);

        // autogen.sh
        if (self.run_autogen)
            _ = cmd_seq.add("./autogen.sh", .{ .name = self.get_step_name("./autogen.sh") });

        // configure
        const configure = cmd_seq.add("./configure", .{ .name = self.get_step_name("./configure") });
        configure.addArg(b.fmt("CC={s} cc -target {s} -mcpu={s}", .{ zig_exe, linux_target, zig_mcpu }));
        configure.addArg(b.fmt("CXX={s} c++ -target {s} -mcpu={s}", .{ zig_exe, linux_target, zig_mcpu }));
        configure.addArg(b.fmt("LD={s} cc -target {s} -mcpu={s}", .{ zig_exe, linux_target, zig_mcpu }));
        configure.addArg(b.fmt("AR={s} ar", .{zig_exe}));
        configure.addArg(b.fmt("RANLIB={s} ranlib", .{zig_exe}));
        configure.addArg(b.fmt("OBJCOPY={s} objcopy", .{zig_exe}));
        configure.addArg(b.fmt("CFLAGS={s} {s}", .{ f_optimize, f_separate_sections }));
        configure.addArg(b.fmt("CXXFLAGS={s} {s}", .{ f_optimize, f_separate_sections }));
        configure.addArg(b.fmt("LDFLAGS={s} {s} {s}", .{ f_optimize, f_gc_sections, f_strip }));
        configure.addArg(b.fmt("--host={s}", .{linux_target})); // must use the linux target
        configure.addArg("--prefix=/usr"); // the logic install directory
        for (self.configure_args.items) |arg|
            configure.addArg(arg); // configure arguments passed by the user

        // make -j$(nproc)
        const make = cmd_seq.add("make", .{ .name = self.get_step_name("make") });
        make.addArg(b.fmt("-j{d}", .{std.Thread.getCpuCount() catch 2}));

        // make install DESTDIR=build_out
        const make_install = cmd_seq.add("make", .{ .name = self.get_step_name("make install") });
        make_install.addArg("install");
        const build_out = make_install.addPrefixedOutputDirectoryArg("DESTDIR=", "build_out").path(b, "usr");
        return build_out;
    }

    fn get_step_name(self: *ZMake, step_name: []const u8) []const u8 {
        const b = self.b;
        return b.fmt("zmake:{s} {s}", .{ self.name, step_name });
    }
};

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    // const optimize = b.standardOptimizeOption(.{});

    // build options
    const lto = b.option(std.zig.LtoMode, "lto", "enable link time optimization") orelse .none;
    const single_threaded = b.option(bool, "single_threaded", "single threaded mode for wolfssl") orelse false;

    const zmake = ZMake.create(b, "wolfssl", .{
        .build_system_type = .autotools,
        .source_dir = b.dependency("wolfssl_source", .{}).path(""),
        .target = target,
        .optimize = .ReleaseFast,
        .lto = lto,
        .run_autogen = true,
    });

    zmake.add_configure_arg("--enable-jobserver=no"); // must be disabled (due to a bug in the wolfssl configure script)
    zmake.add_configure_arg("--enable-static");
    zmake.add_configure_arg("--disable-shared"); // we don't need shared library
    zmake.add_configure_arg("--disable-openssl-compatible-defaults");
    zmake.add_configure_arg("--disable-opensslextra");
    zmake.add_configure_arg("--disable-opensslall");
    zmake.add_configure_arg("--disable-errorqueue"); // this is the OpenSSL compatibility layer
    zmake.add_configure_arg("--disable-oldnames");
    zmake.add_configure_arg("--disable-examples");
    zmake.add_configure_arg("--disable-crypttests");
    zmake.add_configure_arg("--disable-asyncthreads");
    zmake.add_configure_arg("--disable-oldtls");
    zmake.add_configure_arg("--disable-dtls");
    zmake.add_configure_arg("--disable-pwdbased");
    zmake.add_configure_arg("--disable-aescbc");
    zmake.add_configure_arg("--disable-dh");
    zmake.add_configure_arg("--disable-sha3");
    zmake.add_configure_arg("--disable-sha224");
    zmake.add_configure_arg("--disable-sha"); // drop legacy SHA-1
    zmake.add_configure_arg("--disable-oaep"); // drop RSA-OAEP (not used by TLS)
    zmake.add_configure_arg("--disable-pkcs12"); // drop .p12/.pfx parsing support
    zmake.add_configure_arg("--disable-asn-print"); // drop human-readable ASN1 text dumps
    zmake.add_configure_arg("--enable-tls13");
    zmake.add_configure_arg("--enable-ecc");
    zmake.add_configure_arg("--enable-rsa");
    zmake.add_configure_arg("--enable-sni"); // server name indication
    zmake.add_configure_arg("--enable-alpn");
    zmake.add_configure_arg("--enable-session-ticket");
    if (single_threaded)
        zmake.add_configure_arg("--enable-singlethreaded");
    if (target.result.cpu.arch == .x86_64)
        zmake.add_configure_arg("--enable-aesni");
    // TODO: add more configure options

    const build_out = zmake.build();

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
