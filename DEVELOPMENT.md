# Windows 文档开发

项目支持在原生 Windows 环境中使用 PowerShell 完成文档预览、构建和翻译迭代；现有
Linux、macOS 与 Nix 工作流保持不变。

## 环境准备

安装 Git、Rust（通过 rustup）和 Python 3，并确保
`git`、`cargo`、`rustup`、`python` 已加入 `PATH`。在仓库根目录运行：

```powershell
.\scripts\dev.ps1 setup
```

该命令安装项目锁定版本的 Rust 文档工具和 mdBook 插件。Windows 下会跳过
`mdbook-pandoc`，因为 PDF 输出在 `book.toml` 中默认关闭。

若 PowerShell 阻止执行本地脚本，可仅为当前窗口临时放宽策略：

```powershell
Set-ExecutionPolicy -Scope Process Bypass
```

## 日常迭代

```powershell
# 英文文档预览，默认 http://localhost:3000
.\scripts\dev.ps1 serve

# 中文文档预览
.\scripts\dev.ps1 serve-zh

# 构建英文或中文文档
.\scripts\dev.ps1 build
.\scripts\dev.ps1 build-zh

# 将构建输出放到指定目录
.\scripts\dev.ps1 build-zh -Output target\book\zh-CN

# 更新并校验中文翻译目录，输出未翻译/模糊条目统计
.\scripts\dev.ps1 update-zh

# 运行 Rust 测试及 mdBook 代码块测试
.\scripts\dev.ps1 test
.\scripts\dev.ps1 rust-test
```

`update-zh` 需要 GNU gettext 的 `msgmerge`、`msgattrib`、`msgfmt` 可从 `PATH`
调用。PowerShell 脚本的 `setup` 会检查这些程序并在缺失时给出提示；安装 gettext
后重新打开终端即可。

使用 MSYS2 UCRT64 时，可在 UCRT64 终端安装 gettext 工具：

```bash
pacman -S --needed mingw-w64-ucrt-x86_64-gettext-tools
```

确保 MSYS2 的 `ucrt64\bin` 目录（默认是 `C:\msys64\ucrt64\bin`）加入 Windows
`PATH`。对应的
[MSYS2 gettext-tools 包](https://packages.msys2.org/packages/mingw-w64-ucrt-x86_64-gettext-tools)
包含 Windows 可执行文件。

## 格式化

格式化仓库文件还需要 `dprint` 和 YAPF。安装 dprint 后，可用 Python 安装 YAPF：

```powershell
cargo install dprint --locked
python -m pip install --user yapf
dprint fmt
cargo fmt --all
```

格式检查：

```powershell
dprint check
cargo fmt --all -- --check
```

Windows CI 会验证原生 Rust 测试、英文/中文 mdBook
构建以及代码块测试。翻译更新依赖系统级 gettext，因此 Windows CI 不会改写仓库中的
`.po` 文件。
