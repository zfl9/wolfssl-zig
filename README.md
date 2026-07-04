# wolfssl-zig

wolfSSL 的 Zig 封装包，用于将 wolfSSL 集成到你的 C/C++/Zig 项目中。

## 环境要求

- Zig 0.15.2+
- make、autoconf、automake、libtool

## 使用方法

```bash
zig fetch --save=wolfssl https://github.com/zfl9/wolfssl-zig/archive/refs/tags/v5.9.2.tar.gz
```

在 `build.zig` 的 `build()` 函数中，添加如下代码：

```zig
const wolfssl = b.dependency("wolfssl", .{
    .target = target,
    .lto = lto,
    .single_threaded = single_threaded,
});
const include_dir = wolfssl.namedLazyPath("include");
const lib_file = wolfssl.namedLazyPath("libwolfssl.a");

// 在构建可执行文件时：
// const exe = b.addExecutable(.{ .name = "my-app", .root_source_file = .{ .path = "src/main.zig" } });
// exe.root_module.addIncludePath(include_dir);
// exe.root_module.addObjectFile(lib_file);
```

## 构建选项

| 选项 | 类型 | 默认值 | 描述 |
|---|---|---|---|
| `-Dlto` | `enum` | `none` | LTO 模式（`none` / `full` / `thin`） |
| `-Dsingle_threaded` | `bool` | `false` | 取消 wolfSSL 的线程安全支持，适用于单线程场景 |

## 本地构建

```bash
zig build
```

产物输出到 `zig-out/`：
- `zig-out/include/` — wolfSSL 头文件
- `zig-out/lib/libwolfssl.a` — 静态库
