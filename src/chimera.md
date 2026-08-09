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

## Core-Dependent Protocol Surface

Chimera does not have one fixed protocol matrix of its own. The selected core is
an explicit runtime choice, and the desktop source maps several Clash-family
core types into the shared core-management layer, including Mihomo, clash-rs,
and Chimera Client variants.

A generated profile can therefore contain a field that one selected core
supports and another rejects or interprets differently. Protocol claims in this
Wiki should be attached to the core implementation rather than to the desktop
GUI.

For the current Chimera Client matrix, see
[Chimera_Client](./chimera_client.md). For a source-audited cross-project view,
see [Implementation Status and Source Evidence](./implementation-status.md).

## Foreground and Service Runtime Paths

The desktop currently has two distinct core ownership paths:

```text
foreground: Chimera -> child core
service:    Chimera -> local IPC -> Chimera_Service -> child core
```

Both paths use the desktop-generated runtime configuration. Service mode moves
process ownership and privileged control into `Chimera_Service`; it does not
move profile merge/rule semantics into the service.

See [Service Mode Configuration](./chimera/service-mode.md) for the actual IPC
boundary and lifecycle.

---
