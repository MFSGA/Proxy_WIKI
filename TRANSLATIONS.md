# Proxy Wiki Translation Guide

Proxy Wiki uses Gettext-based translation files. English Markdown files under
`src/` are the source text, and translations live in `po/<lang>.po`.

The repository currently includes Simplified Chinese at `po/zh-CN.po`.

## Prerequisites

Install the mdBook tooling and Gettext utilities:

```shell
cargo xtask install-tools
```

On systems where Gettext is not provided by the Rust tooling, install
`msgmerge`, `msgfmt`, `msgcat`, and `msgattrib` through the system package
manager. The Nix shell in `flake.nix` includes these tools.

## Creating and Updating Translations

Generate the latest POT template:

```shell
mdbook build
```

The template is written to `book/xgettext/messages.pot`.

To update the Simplified Chinese translation:

```shell
scripts/update-zh.sh --stats
```

That script rebuilds the POT file, merges updated source strings into
`po/zh-CN.po`, normalizes obsolete entries by default, validates the result with
`msgfmt`, and optionally prints untranslated/fuzzy counts.

## Editing Rules

- Edit `msgstr` values only.
- Do not edit `msgid` values in `.po` files; fix the English Markdown source
  instead.
- Keep code, command names, file paths, protocol names, YAML keys, and JSON keys
  exact unless the surrounding prose requires translation.
- After editing a `.po` file, run
  `msgfmt --check -o /tmp/translation.mo
  po/<lang>.po`.

## Previewing

Preview the Chinese build:

```shell
cargo xtask serve -l zh-CN
```

Build it without serving:

```shell
cargo xtask build -l zh-CN
```
