# Proxy Wiki

> **Chimera Proxy Ecosystem** — documentation for a Rust-native VLESS + REALITY client/server stack.

## Chimera Ecosystem

```text
Chimera Desktop
       ↕
Chimera Client (Rust client core)
       ↕ VLESS / REALITY
Chimera Proxy Server (Rust server core)
       ↕
AChimera · Proxy Wiki
```

- [Chimera](https://github.com/MFSGA/Chimera) — desktop application
- [Chimera Client](https://github.com/MFSGA/Chimera_Client) — Rust client core
- [Chimera Proxy Server](https://github.com/MFSGA/Chimera_Service) — Rust server core
- [AChimera](https://github.com/MFSGA/AChimera) — Android client (when available)

Proxy Wiki collects documentation and notes for the Chimera proxy stack, covering
`chimera_client`, `Chimera`, and `chimera_server` plus quick references and
comparisons for common proxy protocols. It is built with
[mdBook](https://github.com/rust-lang/mdBook) and can be previewed locally or
exported as a static site.

## At a glance
- Components: `chimera_client` (Clash-style client), `Chimera` (high-performance ingress), `chimera_server` (shared protocol/crypto/config library).
- Topology: typical client-to-ingress deployments, routing, and observability approaches.
- Protocol deep dives: wire formats, state machines, packet-capture views, and SOCKS5 comparisons for SOCKS5, HTTP CONNECT, Trojan, Hysteria 2, TUIC, VMess, VLESS, XHTTP, and REALITY.
- Internationalization: Gettext-based translation workflow; `po/zh-CN.po` is available.

## Repository layout
- `src/`: mdBook chapters and protocol notes.
- `po/`: Gettext translation files (initial `zh-CN` draft included).
- `theme/`: custom CSS/JS assets.
- `mdbook-course/`, `mdbook-exerciser/`: bundled mdBook preprocessors to keep builds consistent.
- `xtask/`: `cargo xtask` automation (install tools, build, serve, test).

## Prerequisites
- Rust toolchain (recommended via `rustup`; `cargo xtask install-tools` installs a pinned nightly and required mdBook plugins, including Mermaid support).
- Optional: Gettext and `dprint` for updating/formatting translation files.

## Quickstart
```shell
# Install tools needed to build the docs
cargo xtask install-tools

# Preview the English docs locally (default http://localhost:3000)
cargo xtask serve --port 3100 (opt)

# Preview or build a specific language, e.g., Simplified Chinese
cargo xtask serve -l zh-CN     # live preview
cargo xtask build -l zh-CN     # static output in book/zh-CN/
```

- For English only, you can also run `mdbook serve -d book/` or `mdbook build -d book/` after installing the mdBook plugins via `cargo xtask install-tools`.
- `cargo xtask rust-tests` runs `mdbook test` to validate code blocks (if present).
- For routine validation, use `cargo test`, `cargo clippy -- -D warnings`, and a successful mdBook build.

## Translation notes
- Translation entries live in `po/<lang>.po`; `mdbook build` emits `book/xgettext/messages.pot`.
- `scripts/update-zh.sh --stats` refreshes `po/zh-CN.po`, normalizes it, and reports untranslated/fuzzy counts.
- Preview translations with `MDBOOK_BOOK__LANGUAGE=zh-CN mdbook serve -d book/zh-CN` or `cargo xtask serve -l zh-CN`.
- See `TRANSLATIONS.md` and `STYLE.md` for details.

## License

Licensed under GPL-3.0-or-later; see `LICENSE`.
