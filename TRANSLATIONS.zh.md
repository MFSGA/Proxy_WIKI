# Proxy Wiki 翻译指南

Proxy Wiki 使用 Gettext 管理翻译。`src/` 下的英文 Markdown 是源文本，
翻译文件位于 `po/<lang>.po`。

当前仓库包含简体中文翻译：`po/zh-CN.po`。

## 前置依赖

安装 mdBook 工具链和 Gettext 工具：

```shell
cargo xtask install-tools
```

如果系统没有提供 Gettext，请通过系统包管理器安装 `msgmerge`、`msgfmt`、 `msgcat`
和 `msgattrib`。`flake.nix` 中的 Nix 开发环境已经包含这些工具。

## 更新翻译

生成最新 POT 模板：

```shell
mdbook build
```

模板会写入 `book/xgettext/messages.pot`。

更新简体中文翻译：

```shell
scripts/update-zh.sh --stats
```

该脚本会重新构建 POT 文件，将源文本变更合并到 `po/zh-CN.po`，默认移除过时条目，
用 `msgfmt` 校验结果，并可输出未翻译和 fuzzy 条目数量。

## 编辑规则

- 只编辑 `msgstr`。
- 不要在 `.po` 文件中修改 `msgid`；如英文原文有误，应修改 Markdown 源文件。
- 代码、命令名、文件路径、协议名、YAML 键和 JSON 键应保持精确。
- 编辑后运行 `msgfmt --check -o /tmp/translation.mo po/<lang>.po`。

## 预览

预览中文版本：

```shell
cargo xtask serve -l zh-CN
```

只构建不预览：

```shell
cargo xtask build -l zh-CN
```
