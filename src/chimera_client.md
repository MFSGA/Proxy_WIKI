# Chimera_Client

## Role and Source of Truth

`Chimera_Client` is the Clash-compatible client runtime in the Chimera
ecosystem. It parses Clash-style configuration, exposes local proxy listeners,
performs DNS/rule dispatch, and creates remote outbound connections.

For implementation status, the source tree is authoritative. In particular:

- `clash-lib/src/config/internal/proxy.rs` defines the current outbound protocol
  configuration enum.
- `clash-lib/src/app/outbound/manager.rs` registers concrete outbound handlers.
- `clash-lib/src/proxy/` contains protocol, inbound, outbound, and transport
  implementations.
- `clash-lib/Cargo.toml` determines which optional implementations are present
  in a given binary.

See [Implementation Status and Source Evidence](./implementation-status.md) for
the evidence terminology used by this Wiki.

## Current Outbound Protocols

The current outbound configuration/runtime path contains:

| Outbound | Build condition | Notes |
| --- | --- | --- |
| `direct` | Always | Direct routing action, not a remote proxy protocol. |
| `reject` | Always | Reject routing action, not a remote proxy protocol. |
| `socks5` | Always | SOCKS5 client/outbound implementation. |
| `vless` | Always | Includes stream/datagram paths and transport/security integration such as XHTTP, Vision, and REALITY where configured. |
| `ss` / Shadowsocks | `shadowsocks` feature | TCP and UDP implementation exists; integration tests are present. |
| `anytls` | `anytls` feature | AnyTLS outbound implementation; the same feature also exposes AnyTLS inbound code. |
| `trojan` | `trojan` feature | Trojan outbound implementation. WebSocket wrapping additionally depends on `ws`. |
| `hysteria2` | `hysteria` feature | QUIC/Hysteria 2 outbound implementation. |

VMess, TUIC, WireGuard, and SSH are not variants of the current outbound enum.
They must not be documented as current `Chimera_Client` outbound capabilities
until a runtime path actually exists.

## Current Local Inbound Surface

The client also contains local inbound implementations, which are a different
capability from remote outbounds:

- HTTP proxy inbound,
- SOCKS inbound,
- mixed HTTP/SOCKS listener,
- Shadowsocks inbound behind `shadowsocks`,
- AnyTLS inbound behind `anytls`,
- TUN, redir, and TProxy paths according to Cargo features and platform
  support.

Known boundaries should be stated explicitly:

- the current SOCKS inbound path reports UDP as unsupported,
- the mixed inbound path reports UDP as unsupported,
- a protocol being implemented behind a Cargo feature does not mean it is
  present in the default binary.

## Default Build vs Optional Features

The current default feature set enables:

- `zero_copy`,
- `tls`,
- `aws-lc-rs`,
- `tun`,
- `port`,
- `reality`,
- `extended-health-check`.

The following protocol/transport implementations are separate features:

- `ws`,
- `anytls`,
- `shadowsocks`,
- `trojan`,
- `hysteria`.

This distinction matters operationally. A profile can be syntactically valid
for the project while a particular binary was built without the feature needed
to instantiate its handler.

## Parsed Compatibility Is Not Runtime Support

Some configuration fields intentionally exist only to accept ecosystem
configuration shapes. The AnyTLS configuration is a concrete example: several
fields are annotated in source as parsed for compatibility but currently not
applied by the runtime.

Documentation should therefore distinguish:

1. **Parsed** — serde accepts the field,
2. **Constructed** — a handler can be built,
3. **Implemented** — a forwarding path uses it,
4. **Tested** — integration or interoperability tests exercise it.

Do not infer level 3 or 4 from level 1.

## Architecture Overview

Internally, the client is organized into four broad layers:

1. **Configuration layer**
   - Parses Clash-style YAML into typed Rust structures.
   - Applies defaults and validation.
   - Converts external configuration into runtime-specific forms.
2. **Inbound/controller layer**
   - Owns local proxy listeners and TUN/transparent-entry paths.
   - Exposes management APIs for status, switching, traffic, and diagnostics.
3. **Policy and DNS layer**
   - Evaluates rules with first-match semantics.
   - Provides system/enhanced DNS paths, Fake-IP behavior, resolver policy, and
     DNS-rule dispatch hooks.
4. **Outbound/transport layer**
   - Selects the outbound handler.
   - Applies transport/security wrappers such as WebSocket, XHTTP, TLS, and
     REALITY where the selected protocol supports them.
   - Executes protocol handshakes and forwarding.

A useful mental model is:

```text
local listener / TUN
        |
        v
metadata + DNS + rules
        |
        v
outbound manager
        |
        v
proxy protocol
        |
        v
optional transport/security wrapper
        |
        v
remote server
```

## VLESS as a Current Client Capability

VLESS is a current outbound, not merely a planned target. The source contains
configuration fields for `network`, XHTTP options, REALITY options, `flow`,
client fingerprint, TLS settings, and UDP behavior, together with concrete
VLESS stream/datagram and Vision modules.

When documenting a VLESS combination, keep the layers separate. For example:

```text
VLESS identity / command
        |
     Vision flow      (optional protocol optimization)
        |
     XHTTP            (optional transport)
        |
     REALITY/TLS      (optional security layer)
        |
     TCP/HTTP stack
```

The presence of one layer does not automatically prove every combination of the
others is tested.

## Integration Evidence

The repository currently contains dedicated integration coverage including:

- `clash-lib/tests/anytls_integration_tests.rs`,
- `clash-lib/tests/shadowsocks_integration_tests.rs`,
- direct UDP, DNS, TUN/Fake-IP, controller/API, connection-chain, and socket
  protection tests.

Use these tests as stronger evidence than README capability lists when updating
this Wiki.

## Module Guide

- **Ports and listeners**: key mapping and local inbound support. See
  [Ports and Listeners](./chimera_client/ports.md).
- **DNS module**: Fake-IP vs real-IP models, resolver policy, and implementation
  status. See [DNS Module](./chimera_client/dns.md).
- **TUN module**: route-all/split-route semantics and platform considerations.
  See [Tun Module](./chimera_client/tun.md).
- **Rules module**: rule taxonomy, ordering, and provider-based policy. See
  [Rule Types and Their Effects](./chimera_client/rules.md).

## Relationship to Clash-rs and Mihomo

`clash-rs` and Mihomo remain important compatibility references, but they are
not proof that an option is implemented in `Chimera_Client`.

- **clash-rs** is a useful Rust architectural/configuration reference.
- **Mihomo** is a broad ecosystem compatibility reference.
- **Chimera_Client source and tests** determine what the current Chimera binary
  can actually do.

Migration documentation should explicitly call out fields that are parsed-only,
feature-gated, rejected, or behaviorally different.

## Deployment Guidance

For a new deployment:

1. confirm the binary was built with the required Cargo features,
2. validate the profile,
3. start with a local HTTP/SOCKS listener before adding TUN,
4. verify DNS/rule behavior,
5. add the remote protocol and transport/security layers one at a time,
6. use integration/interop-tested combinations where possible.

For CI, keep both a minimal profile and profiles that exercise the optional
features enabled by the produced artifact.

## Reference Repositories

- `Chimera_Client`: <https://github.com/MFSGA/Chimera_Client>
- `clash-rs`: <https://github.com/Watfaq/clash-rs>
- `mihomo`: <https://github.com/MetaCubeX/mihomo>
