# Proxy Wiki

Proxy Wiki collects documentation and notes for the Chimera proxy stack, covering
`chimera_client`, `Chimera`, and `chimera_server` plus quick references and
comparisons for common proxy protocols. It is built with
[mdBook](https://github.com/rust-lang/mdBook) and can be previewed locally or
exported as a static site.

## At a glance
- Components: `chimera_client` (Clash-style client), `Chimera` (high-performance ingress), `chimera_server` (shared protocol/crypto/config library).
- Topology: typical client-to-ingress deployments, routing, and observability approaches.
- Protocol cheat sheets: handshakes, pros/cons, and fit for SOCKS5, HTTP(S) CONNECT, Trojan, Hysteria 2, and VLESS.
- Internationalization: Gettext-based translation workflow; `po/zh-CN.po` is available.

## Repository layout
- `src/`: mdBook chapters and protocol notes.
- `po/`: Gettext translation files (initial `zh-CN` draft included).
- `theme/`: custom CSS/JS assets.
- `mdbook-course/`, `mdbook-exerciser/`: bundled mdBook preprocessors to keep builds consistent.
- `xtask/`: `cargo xtask` automation (install tools, build, serve, test).
- `tests/`: WebdriverIO-based frontend regression tests (optional when touching theme JS; requires Node.js).

## Prerequisites
- Rust toolchain (recommended via `rustup`; `cargo xtask install-tools` installs a pinned nightly and required mdBook plugins).
- Optional: Node.js 18+ (needed for `cargo xtask web-tests`).
- Optional: Gettext and `dprint` for updating/formatting translation files.

## Quickstart
```shell
# Install tools needed to build the docs
cargo xtask install-tools

# Preview the English docs locally (default http://localhost:3000)
cargo xtask serve

# Preview or build a specific language, e.g., Simplified Chinese
cargo xtask serve -l zh-CN     # live preview
cargo xtask build -l zh-CN     # static output in book/zh-CN/
```

- For English only, you can also run `mdbook serve -d book/` or `mdbook build -d book/`.
- `cargo xtask rust-tests` runs `mdbook test` to validate code blocks (if present).
- `cargo xtask web-tests` runs the WebdriverIO suite; install Node dependencies first (see `tests/package.json`).

## Translation notes
- Translation entries live in `po/<lang>.po`; `mdbook build` emits `book/xgettext/messages.pot`.
- Preview translations with `MDBOOK_BOOK__LANGUAGE=zh-CN mdbook serve -d book/zh-CN` or `cargo xtask serve -l zh-CN`.
- See `TRANSLATIONS.md` and `STYLE.md` for details.

## License

Licensed under GPL-3.0-or-later; see `LICENSE`.
