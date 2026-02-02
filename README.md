# Proxy Wiki

Proxy Wiki 收集并整理了 Chimera 代理栈的文档与笔记，覆盖
`chimera_client`、`Chimera` 与 `chimera_server`，并提供常见代理协议的速查
与对比。项目基于 [mdBook](https://github.com/rust-lang/mdBook)，支持本地预览
或导出为静态站点。

## 一览
- 组件：`chimera_client`（Clash 风格客户端）、`Chimera`（高性能入口）、`chimera_server`（共享协议/加密/配置库）。
- 拓扑：典型的客户端到入口部署、路由与可观测性方案。
- 协议速查：SOCKS5、HTTP(S) CONNECT、Trojan、Hysteria 2、VLESS 的握手、优缺点与适用场景。
- 国际化：基于 Gettext 的翻译流程；已提供 `po/zh-CN.po`。

## 仓库结构
- `src/`: mdBook 章节与协议笔记。
- `po/`: Gettext 翻译文件（含 `zh-CN` 初稿）。
- `theme/`: 自定义 CSS/JS 资源。
- `mdbook-course/`, `mdbook-exerciser/`: 内置 mdBook 预处理器，用于保持构建一致性。
- `xtask/`: `cargo xtask` 自动化（安装工具、构建、预览、测试）。
- `tests/`: 基于 WebdriverIO 的前端回归测试（仅在改动主题 JS 时需要；依赖 Node.js）。

## 前置条件
- Rust 工具链（推荐使用 `rustup`；`cargo xtask install-tools` 会安装固定版本的 nightly 与所需的 mdBook 插件）。
- 可选：Node.js 18+（运行 `cargo xtask web-tests` 需要）。
- 可选：Gettext 与 `dprint`（更新/格式化翻译文件需要）。

## 快速开始
```shell
# 安装构建文档所需工具
cargo xtask install-tools

# 本地预览英文文档（默认 http://localhost:3000）
cargo xtask serve --port 3100 # 可选

# 预览或构建指定语言，例如简体中文
cargo xtask serve -l zh-CN     # 实时预览
cargo xtask build -l zh-CN     # 输出到 book/zh-CN/
```

- 若只需英文，也可运行 `mdbook serve -d book/` 或 `mdbook build -d book/`。
- `cargo xtask rust-tests` 会运行 `mdbook test` 验证代码块（如有）。
- `cargo xtask web-tests` 会运行 WebdriverIO 套件；需先安装 Node 依赖（见 `tests/package.json`）。

## 翻译说明
- 翻译条目位于 `po/<lang>.po`；`mdbook build` 会生成 `book/xgettext/messages.pot`。
- 可使用 `MDBOOK_BOOK__LANGUAGE=zh-CN mdbook serve -d book/zh-CN` 或 `cargo xtask serve -l zh-CN` 预览翻译。
- 详见 `TRANSLATIONS.md` 与 `STYLE.md`。

## 许可

项目采用 GPL-3.0-or-later 许可证；详见 `LICENSE`。
