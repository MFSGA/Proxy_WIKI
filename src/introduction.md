# Introduction

This documentation set covers the Chimera proxy ecosystem as implemented across
the local source repositories:

- `Chimera_Client`: the Rust Clash-family client core.
- `Chimera`: the Tauri + React desktop control application.
- `Chimera_Service`: the privileged local service used for service-mode core
  lifecycle and selected privileged operations.
- `AChimera`: the Android application that owns the Android VPN/TUN lifecycle and
  embeds the Chimera client core through UniFFI.
- `Chimera_Server`: the Rust server core focused on Xray-style inbound
  configuration, transports, security wrappers, and protocol handlers.

These projects target different layers of the system. A configuration or
protocol feature should therefore be attributed to the component that actually
parses and executes it rather than to the GUI that exposes the setting.

## How to Use This Wiki

There are three complementary reading paths:

- **Architecture and operators**: start with [System Topology](./system-topology.md),
  then read the component pages for desktop, Android, service mode, client, and
  server behavior.
- **Implementation and compatibility**: use
  [Implementation Status and Source Evidence](./implementation-status.md) to see
  which capabilities are parsed, implemented, feature-gated, tested, or
  explicitly rejected in the current source.
- **Wire protocols**: use [Protocol Reference](./protocol.md) for low-level wire
  formats, state machines, security properties, packet-capture views, and
  comparisons with SOCKS5.

Protocol specification and implementation status are deliberately separate. An
upstream protocol can define a field that Chimera does not yet implement, while
Chimera can also parse compatibility fields that are not applied by its runtime.

## Documentation Source Policy

For current implementation claims, this Wiki uses the following evidence order:

1. executable/runtime path,
2. integration or interoperability tests,
3. typed configuration and validation,
4. repository README or planning text.

This prevents a broad README statement such as “Xray compatible” or “Clash
compatible” from hiding an explicit runtime rejection or a parsed-only field.

For public protocol wire behavior, protocol specifications, RFCs, and current
upstream implementations remain the preferred sources.

## Documentation Status

The low-level protocol reference is mature for the currently documented core
protocols, but the wider project documentation is maintained continuously
against source changes. The implementation-status page records the audited
source snapshot so readers can tell when a capability table may need to be
rechecked.

Remaining source-verified documentation and implementation gaps are tracked in
[Open Questions](./open-questions.md). That page should contain real unresolved
work, not items that have already been answered by the source tree.
