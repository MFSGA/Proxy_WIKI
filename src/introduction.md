# Introduction

This documentation set introduces the Chimera proxy ecosystem, focusing on the
projects that are visible in the local workspace:

- `Chimera_Client`: a Rust client core based on the `clash-rs` architecture and
  aimed at Clash/Mihomo-compatible configuration behavior.
- `Chimera`: a Tauri + React desktop application that manages profiles, core
  binaries, runtime configuration, system proxy integration, service mode, and
  updates.
- `Chimera_Server`: a Rust server core that tracks `xray-core`-style inbound
  configuration and protocol behavior.
- `AChimera`: an adjacent Android-oriented project whose relationship to this
  documentation set still needs a dedicated page.

Each module targets a different layer of the overall stack, but they share a
common goal: making proxy configuration, operation, and development easier to
reason about under diverse network conditions.

## How to Use This Wiki

The documentation is organized around two reading paths:

- **Users and operators** should start with the component overview, then move to
  configuration-oriented pages such as ports, DNS, TUN, rules, runtime
  configuration, and service mode.
- **Developers and maintainers** should use the topology and protocol sections
  together with component-specific implementation notes to understand runtime
  boundaries, configuration flow, compatibility goals, and extension points.

The [System Topology](./system-topology.md) page is the best starting point when
trying to understand how the desktop application, client core, and server core
fit together. The [Protocol Reference](./protocol.md) collects protocol-specific
notes and comparisons.

## Documentation Status

This Wiki documents both current behavior and longer-term project direction.
Where the implementation boundary is not yet clear, the text should be treated
as a working reference rather than a compatibility guarantee. Known gaps,
missing matrices, and questions that still require verification are tracked in
[Open Questions](./open-questions.md).
