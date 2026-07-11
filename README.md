# wolfssl-zig

[wolfSSL](https://github.com/wolfSSL/wolfssl) 的 Zig 包，用于将 wolfSSL 库集成至你的 C/C++/Zig 项目。

## 环境要求

- Zig 0.15.2+
- make、autoconf、automake、libtool
- bear（可选，使用 `-Dworkspace` 时需要）

## 使用方法

> 具体版本见 [Tags](https://github.com/zfl9/wolfssl-zig/tags) 页面。

```bash
zig fetch --save=wolfssl https://github.com/zfl9/wolfssl-zig/archive/refs/tags/v5.9.2.tar.gz
```

在 `build.zig` 的 `build()` 函数中，添加如下代码：

```zig
const wolfssl = b.dependency("wolfssl", .{
    .target = target,
    // always ReleaseFast, see build.zig:24
    // .optimize = optimize,
    .lto = lto,
    .single_threaded = single_threaded,
    .nproc = nproc,
});
const include_dir = wolfssl.namedLazyPath("include");
const lib_file = wolfssl.namedLazyPath("libwolfssl.a");

// 在构建可执行文件时：
// const exe = b.addExecutable(.{ .name = "my-app", .root_source_file = .{ .path = "src/main.zig" } });
// exe.root_module.addIncludePath(include_dir);
// exe.root_module.addObjectFile(lib_file);
```

## 构建选项

支持 Zig 标准的 target、optimize 选项，此外还有：

| 选项 | 类型 | 默认值 | 描述 |
|---|---|---|---|
| `-Dlto` | `enum` | `none` | LTO 模式（`none` / `full` / `thin`） |
| `-Dsingle_threaded` | `bool` | `false` | 取消 wolfSSL 的线程安全支持，适用于单线程程序 |
| `-Dnproc=<n>` | `usize` | CPU 核心数 | make 并行任务数 |
| `-Dworkspace` | `bool` | `false` | 生成 IDE workspace symlink（需安装 bear） |
| `-Dworkspace_name=<name>` | `string` | `"wolfssl"` | workspace symlink 名称，指定后自动启用 workspace |

## 本地构建

```bash
zig build
```

产物输出到 `zig-out/`：
- `zig-out/include/` — wolfSSL 头文件
- `zig-out/lib/libwolfssl.a` — 静态库

## 版本约定

`.zon` 中的 `version` 与 wolfSSL 上游版本号保持一致，便于直观对照。\
本包自身的更新（构建逻辑调整、内部依赖升级等）通过 Git tag 后缀区分：

- `v5.9.2` — 初始版本
- `v5.9.2-rev<N>` — 后续修订

使用者通过 `zig fetch --save=wolfssl <tag URL>` 选择具体版本。
