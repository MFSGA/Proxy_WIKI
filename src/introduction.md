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

In addition, the documentation for each project is generally divided into two
major parts: one is a configuration guide for general users, intended for quick
onboarding and day-to-day usage; the other is an advanced reference for
developers, intended to help them understand implementation details, extension
capabilities, and support further development.
