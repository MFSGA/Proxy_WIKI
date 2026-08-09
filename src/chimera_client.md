# Chimera_Client

## Current Protocol and Transport Coverage

The following items are documented as currently available in the client codebase.
Exact runtime availability can still depend on build features, configuration,
and platform privileges.

- Trojan + WebSocket
- Hysteria 2
- Reality + TCP
- SOCKS5
- HTTP
- XHTTP
- Mixed HTTP/SOCKS listener
- DNS listener and Fake-IP resolver path
- TUN mode, gated by build features and platform privileges

## Planned or Targeted Support

- gRPC
- VMess
- WireGuard
- SSH

## Role and Objectives

`chimera_client` is the Clash-compatible client runtime in the Chimera
ecosystem. Its design goal is practical compatibility with existing Clash/Mihomo
profiles, while using Rust’s type safety and async ecosystem to build a
maintainable codebase.

For operators, this means:

- Preserve familiar configuration and policy mental models.
- Improve implementation clarity through explicit schema and module boundaries.
- Enable incremental parity while keeping the implementation testable across
  DNS, TUN, REST API, inbound listeners, and outbound protocols.

## Relationship to Clash-rs and Mihomo

`chimera_client` documentation treats `clash-rs` and Mihomo as the two most
important references:

- **clash-rs**: Rust-native reference for parser/runtime behavior and config
  semantics.
- **Mihomo**: de-facto production reference for broad ecosystem compatibility
  and advanced operational features.

In this chapter, each module page clearly marks:

1. what works in `chimera_client` now,
2. what is Clash/Mihomo-compatible target behavior,
3. and what migration precautions to apply today.

## Architecture Overview

Internally, the client is organized into four layers:

1. **Configuration layer**
   - Parses Clash-style YAML into typed Rust structures.
   - Handles defaults, validation, and hot-reload boundaries.
2. **Inbound/controller layer**
   - Owns local listeners (SOCKS/HTTP/mixed/TUN/redir/TProxy depending on build
     features and platform support).
   - Exposes management APIs for status, switching, and diagnostics.
3. **Policy and DNS layer**
   - Evaluates rule chains with first-match semantics.
   - Provides system and enhanced DNS resolver paths, DNS listener support,
     Fake-IP mapping, and DNS rule-dispatch hooks.
4. **Outbound transport layer**
   - Executes protocol handshakes and stream forwarding.
   - Encapsulates protocol-specific knobs while sharing common TLS/socket
     utilities.

This split mirrors common Clash-family architecture and reduces coupling between
parser, runtime, and protocol engines.

## Module Guide

Each functional area is documented independently:

- **Ports and listeners**: key mapping and current inbound support. See
  [Ports and Listeners](./chimera_client/ports.md).
- **DNS module**: fake-IP vs real-IP models, resolver policy, and current
  implementation status. See [DNS Module](./chimera_client/dns.md).
- **TUN module**: route-all/split-route semantics and Linux policy-routing
  notes. See [Tun Module](./chimera_client/tun.md).
- **Rules module**: rule taxonomy, ordering strategy, and provider-based policy
  composition. See [Rule Types and Their Effects](./chimera_client/rules.md).

## Compatibility Snapshot (English Docs, Current)

| Area              | chimera_client (current)                                                                                                                     | clash-rs / Mihomo reference                     |
| ----------------- | -------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------- |
| Inbound listeners | SOCKS/HTTP/mixed plus redir/TProxy fields; actual availability depends on Cargo features such as `mixed_port`, `redir`, and `tproxy`         | Full Clash-family listener matrix               |
| DNS               | DNS block exists; supports disabled/system path, listener, enhanced resolver, Fake-IP, policy/fallback structures, and `respect-rules` hooks | Mature fake-IP/real-IP/split resolver workflows |
| TUN               | `tun` block exists in parser and internal config; runtime is feature/platform dependent                                                      | Mature cross-platform implementations           |
| Rules             | Core Clash rule language documented and aligned                                                                                              | Full rule/provider ecosystem                    |

Use this table as a reading index: module pages go deeper with examples and
caveats.

## Deployment Patterns

Recommended rollout pattern for production-like use:

- Start with SOCKS-based local proxying.
- Enable DNS listener and Fake-IP only after you have checked rule behavior and
  OS resolver routing.
- Use explicit rule ordering and small provider sets first, then scale.
- Add TUN only after verifying build features, privileges, route changes, and
  DNS hijack behavior on the target OS.

For CI/testing, keep one minimal profile and one Clash/Mihomo-parity profile to
detect parser/runtime divergence early.

## Performance and Operational Focus

The long-term performance strategy is aligned with Clash-family workloads:

- predictable low-overhead rule matching,
- bounded memory behavior in long-lived sessions,
- and high observability for policy debugging.

When introducing parity features (DNS/TUN/listeners), prioritize deterministic
behavior and debuggability over implicit "magic" defaults.

## Reference Repositories

- `chimera_client`: <https://github.com/MFSGA/Chimera_Client>
- `clash-rs`: <https://github.com/Watfaq/clash-rs>
- `mihomo`: <https://github.com/MetaCubeX/mihomo>
