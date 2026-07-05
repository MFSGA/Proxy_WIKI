# Open Questions

This page tracks documentation and implementation gaps that need explicit
follow-up before the wiki can be treated as a complete project reference.

## Project Scope

- Add a dedicated `AChimera` page or remove it from the introduction until its
  role is defined.
- Clarify which repository is the source of truth for each component:
  `Chimera_Client`, `Chimera`, `Chimera_Server`, and Android-related work.
- Add a compatibility matrix for supported operating systems, core binaries, and
  protocol combinations.

## Chimera GUI

- Document the exact differences between child-process mode and service mode.
- Record which runtime settings require a core restart and which can be
  hot-reloaded.
- Document failure handling for core download, core startup, profile update, and
  runtime configuration validation.
- Confirm whether `patch_clash_config` is still unused or should be implemented.

## Runtime Configuration

- Define the intended behavior of profile chain scripts. The current notes show
  the chain-processing hook as a placeholder.
- Decide how multiple profiles should be merged beyond appending `proxies`.
- Document how generated Clash-compatible YAML differs across `mihomo`,
  `clash-rs`, and `chimera-client`.

## Chimera_Client

- Add a feature matrix for inbound listeners, DNS modes, TUN behavior, rule
  types, and platform-specific limitations.
- Document migration differences from Clash/Mihomo behavior where compatibility
  is intentionally incomplete.

## Chimera_Server

- Split the current capability map into implemented, partial, and planned
  sections.
- Add tested configuration examples for each advertised inbound protocol.
- Document how closely each inbound follows xray-core behavior, including known
  deviations.

## Protocol Reference

- Add source references for protocol wire-format claims.
- Add interoperability notes for common client/server combinations.
- Add security notes for deployment-sensitive protocols such as Reality,
  Hysteria 2, TUIC, and XHTTP.
