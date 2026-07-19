const std = @import("std");
const ZMake = @import("zmake").ZMake;

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    _ = b.standardOptimizeOption(.{}); // NOTE: always use release mode

    // optimize options
    const lto = b.option(std.zig.LtoMode, "lto", "enable link time optimization") orelse .none;
    const single_threaded = b.option(bool, "single_threaded", "single threaded mode for wolfssl") orelse false;

    // parallel make options
    const nproc = b.option(usize, "nproc", "make -j<nproc>, default: the number of cores");

    // IDE / workspace options
    const emit_cdb = b.option(bool, "emit_cdb", "emit compile_commands.json (clangd/LSP support)") orelse false;
    var workspace = b.option(bool, "workspace", "symlink to the workspace with clangd support") orelse false;
    const workspace_name = b.option([]const u8, "workspace_name", "name of the workspace symlink, default: wolfssl");
    if (workspace_name != null) workspace = true;

    const wolfssl = ZMake.create(b, "wolfssl", .{
        .build_system_type = .autotools,
        .source_dir = b.dependency("wolfssl_source", .{}).path(""),
        .target = target,
        .optimize = .ReleaseFast,
        .lto = lto,
        .run_autogen = true,
        .nproc = nproc,
        .build_dir_symlink = if (workspace) b.fmt("workspace_{s}", .{workspace_name orelse "wolfssl"}) else null,
    });

    wolfssl.add_configure_arg("--enable-jobserver=no"); // must be disabled (due to a bug in the wolfssl configure script)
    wolfssl.add_configure_arg("--enable-static");
    wolfssl.add_configure_arg("--disable-shared"); // we don't need shared library
    wolfssl.add_configure_arg("--disable-openssl-compatible-defaults");
    wolfssl.add_configure_arg("--disable-opensslextra");
    wolfssl.add_configure_arg("--disable-opensslall");
    wolfssl.add_configure_arg("--disable-errorqueue"); // this is the OpenSSL compatibility layer
    wolfssl.add_configure_arg("--disable-oldnames");
    wolfssl.add_configure_arg("--disable-examples");
    wolfssl.add_configure_arg("--disable-crypttests");
    wolfssl.add_configure_arg("--disable-asyncthreads");
    wolfssl.add_configure_arg("--disable-oldtls");
    wolfssl.add_configure_arg("--disable-dtls");
    wolfssl.add_configure_arg("--disable-pwdbased");
    wolfssl.add_configure_arg("--disable-aescbc");
    wolfssl.add_configure_arg("--disable-dh");
    wolfssl.add_configure_arg("--disable-sha3");
    wolfssl.add_configure_arg("--disable-sha224");
    wolfssl.add_configure_arg("--disable-sha"); // drop legacy SHA-1
    wolfssl.add_configure_arg("--disable-oaep"); // drop RSA-OAEP (not used by TLS)
    wolfssl.add_configure_arg("--disable-pkcs12"); // drop .p12/.pfx parsing support
    wolfssl.add_configure_arg("--disable-asn-print"); // drop human-readable ASN1 text dumps
    wolfssl.add_configure_arg("--enable-tlsv12");
    wolfssl.add_configure_arg("--enable-tls13");
    wolfssl.add_configure_arg("--enable-ecc");
    wolfssl.add_configure_arg("--enable-rsa");
    wolfssl.add_configure_arg("--enable-aesgcm");
    wolfssl.add_configure_arg("--enable-chacha");
    wolfssl.add_configure_arg("--enable-poly1305");
    wolfssl.add_configure_arg("--enable-curve25519");
    wolfssl.add_configure_arg("--enable-sni"); // server name indication
    wolfssl.add_configure_arg("--enable-alpn");
    wolfssl.add_configure_arg("--enable-session-ticket");
    wolfssl.add_configure_arg("--enable-sys-ca-certs");
    if (single_threaded)
        wolfssl.add_configure_arg("--enable-singlethreaded");
    if (target.result.cpu.arch == .x86_64)
        wolfssl.add_configure_arg("--enable-aesni");
    // TODO: add more configure options

    const build_out = wolfssl.build();
    const build_dir = wolfssl.get_build_dir();

    // export the artifact
    b.addNamedLazyPath("include", build_out.path(b, "include"));
    b.addNamedLazyPath("lib", build_out.path(b, "lib"));
    b.addNamedLazyPath("libwolfssl.a", build_out.path(b, "lib/libwolfssl.a"));
    b.addNamedLazyPath("compile_commands.json", build_dir.path(b, "compile_commands.json")); // available only when using `bear`

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
