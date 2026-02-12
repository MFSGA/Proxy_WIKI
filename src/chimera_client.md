# Chimera_Client

## Role and Objectives
`chimera_client` is the Clash-compatible client runtime in the Chimera ecosystem.
Its design goal is practical compatibility with existing Clash/Mihomo profiles, while using Rust’s type safety and async ecosystem to build a maintainable codebase.

For operators, this means:
- Preserve familiar configuration and policy mental models.
- Improve implementation clarity through explicit schema and module boundaries.
- Enable incremental parity: start from stable basics (e.g., SOCKS inbound + rules), then close feature gaps against `clash-rs` and Mihomo.

## Relationship to Clash-rs and Mihomo
`chimera_client` documentation treats `clash-rs` and Mihomo as the two most important references:

- **clash-rs**: Rust-native reference for parser/runtime behavior and config semantics.
- **Mihomo**: de-facto production reference for broad ecosystem compatibility and advanced operational features.

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
   - Owns local listeners (SOCKS/HTTP/mixed/TUN as parity evolves).
   - Exposes management APIs for status, switching, and diagnostics.
3. **Policy and DNS layer**
   - Evaluates rule chains with first-match semantics.
   - Provides DNS strategy primitives (system resolver today; Clash-style DNS target).
4. **Outbound transport layer**
   - Executes protocol handshakes and stream forwarding.
   - Encapsulates protocol-specific knobs while sharing common TLS/socket utilities.

This split mirrors common Clash-family architecture and reduces coupling between parser, runtime, and protocol engines.

## Module Guide
Each functional area is documented independently:

- **Ports and listeners**: key mapping and current inbound support.
  See [Ports and Listeners](./chimera_client/ports.md).
- **DNS module**: fake-IP vs real-IP models, resolver policy, and current implementation status.
  See [DNS Module](./chimera_client/dns.md).
- **TUN module**: route-all/split-route semantics and Linux policy-routing notes.
  See [Tun Module](./chimera_client/tun.md).
- **Rules module**: rule taxonomy, ordering strategy, and provider-based policy composition.
  See [Rule Types and Their Effects](./chimera_client/rules.md).

## Compatibility Snapshot (English Docs, Current)
| Area | chimera_client (current) | clash-rs / Mihomo reference |
| --- | --- | --- |
| Inbound listeners | `socks_port` available; others partial/in progress | Full Clash-family listener matrix |
| DNS | Primarily system resolver path; Clash-style block documented as target | Mature fake-IP/real-IP/split resolver workflows |
| TUN | Documented target model; not fully active on mainline | Mature cross-platform implementations |
| Rules | Core Clash rule language documented and aligned | Full rule/provider ecosystem |

Use this table as a reading index: module pages go deeper with examples and caveats.

## Deployment Patterns
Current recommended pattern for production-like use:

- Start with SOCKS-based local proxying.
- Keep DNS conservative unless you are validating an in-progress DNS branch.
- Use explicit rule ordering and small provider sets first, then scale.
- Add TUN only when parity branch and environment prerequisites are verified.

For CI/testing, keep one minimal profile and one Clash/Mihomo-parity profile to detect parser/runtime divergence early.

## Performance and Operational Focus
The long-term performance strategy is aligned with Clash-family workloads:
- predictable low-overhead rule matching,
- bounded memory behavior in long-lived sessions,
- and high observability for policy debugging.

When introducing parity features (DNS/TUN/listeners), prioritize deterministic behavior and debuggability over implicit "magic" defaults.

## Reference Repositories
- `chimera_client`: <https://github.com/MFSGA/Chimera_Client>
- `clash-rs`: <https://github.com/Watfaq/clash-rs>
- `mihomo`: <https://github.com/MetaCubeX/mihomo>
