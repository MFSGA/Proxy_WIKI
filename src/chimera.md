# Chimera GUI

## Design Goals

`Chimera` is the desktop control surface for the Chimera client ecosystem. It is
built with Tauri, Rust, and React, and its job is to make daily proxy operation
clearer: import profiles, switch nodes, select the proxy core, inspect runtime
state, manage system integration, and keep the core/app updated.

The core design priorities of Chimera are:

- stable cross-platform desktop behavior,
- clear profile and subscription management,
- first-class support for `chimera-client` while retaining compatibility with
  `clash-rs` and `mihomo`,
- reliable core lifecycle management through child-process and service-mode
  paths,
- practical diagnostics through logs, connection views, core status, and
  configuration-directory access.

## Runtime Boundary

`Chimera` is a control application, not a proxy protocol engine. Protocol
availability, transport behavior, and packet forwarding are provided by the
selected core. This distinction is important when comparing features: a feature
visible in the GUI is not necessarily implemented by every supported core, and
a core capability may require additional UI integration before it is exposed in
Chimera.

## Runtime Responsibilities

Chimera manages local state and delegates packet/protocol handling to a selected
core. The main responsibilities visible in the companion codebase are:

- profile import, update, deletion, viewing, editing, and runtime patching,
- Clash-style runtime YAML generation from app settings plus active profile,
- core selection among sidecars such as `mihomo`, `clash-rs`, and
  `chimera-client`,
- core start, stop, restart, recovery, version query, and update,
- system proxy, deep link, notification, dialog, tray, and single-instance
  integration,
- service-mode install, uninstall, start, stop, restart, and status workflows.

## Currently Supported Platforms

### First Tier

- Windows
- macOS
- Linux

### Second Tier

- NixOS

## Currently Supported Protocols

Chimera's protocol support is determined by the selected core. The README and
sidecar manifest scripts currently focus on these common combinations:

- `trojan + ws + tls`
- `reality + tcp`
- `hysteria2`
- `xhttp`

For the runtime behavior of `chimera-client` itself, see
[`Chimera_Client`](./chimera_client.md).

---
