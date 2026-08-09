# Implementation Status and Source Evidence

This page is the implementation-facing index for the Chimera ecosystem. It is
intentionally different from the protocol reference: protocol pages describe
what a protocol means on the wire, while this page records what the local
Chimera source trees actually parse, construct, execute, and test.

## Evidence Levels

Use the following terms consistently across this Wiki:

| Level | Meaning |
| --- | --- |
| **Parsed** | A typed configuration path accepts the option or protocol. This alone does not prove runtime support. |
| **Constructed** | Runtime code can build/register the relevant handler, listener, transport, or outbound. |
| **Implemented** | A real forwarding/data path exists for the advertised direction. |
| **Integration-tested** | The repository contains a network/integration test exercising the implementation. |
| **Interop-tested** | A test exercises Chimera against another implementation, or exercises two Chimera components together. |
| **Parsed-only** | Configuration is accepted for compatibility, but the runtime explicitly does not apply the option. |
| **Rejected** | The parser/builder deliberately rejects the option because the runtime does not support it yet. |

A protocol must not be described simply as “supported” when the available
evidence only reaches **Parsed** or **Constructed**.

## Audited Source Snapshot

The table below records the repository heads inspected while maintaining this
page. A dirty working tree means local, uncommitted changes can exist beyond the
listed commit.

| Repository | Audited HEAD | Working tree at audit | Primary role |
| --- | --- | --- | --- |
| `Chimera_Client` | `e25ace1` | Dirty | Clash-family client core and local proxy runtime |
| `Chimera_Server` | `0e2d3c1` | Clean | Xray-oriented inbound/server core |
| `Chimera` | `5119241` | Dirty | Desktop control plane and core lifecycle manager |
| `Chimera_Service` | `1b7d3ec` | Clean | Privileged local service and core process manager |
| `AChimera` | `3cd85e8` | Clean | Android application embedding the Chimera client core through UniFFI |

This is a documentation audit marker, not a release compatibility promise.
Re-check the source before relying on this table after protocol or runtime
changes.

## Client and Server Protocol Matrix

The matrix is deliberately directional. `Chimera_Client` is primarily a client
core, while `Chimera_Server` is primarily an inbound/server core.

| Protocol / layer | `Chimera_Client` evidence | `Chimera_Server` evidence | Important boundary |
| --- | --- | --- | --- |
| SOCKS5 | Local inbound and outbound code exist | Inbound code exists | Client SOCKS inbound UDP currently returns unsupported; do not infer complete UDP ASSOCIATE parity from outbound support. |
| HTTP proxy | Local HTTP inbound exists | HTTP inbound exists | Treat HTTP proxying separately from HTTP-based transports such as XHTTP. |
| Mixed HTTP/SOCKS | Local mixed listener exists | Mixed inbound exists | Client mixed UDP is explicitly unsupported. |
| [Shadowsocks](./protocols/shadowsocks.md) | Inbound/outbound modules; TCP and UDP integration work exists behind `shadowsocks` feature | Inbound TCP/UDP implementation behind `shadowsocks` feature | Server currently rejects/does not implement some cipher/config variants, including `xchacha20-poly1305`; the protocol page separates classic AEAD and AEAD-2022. |
| [AnyTLS](./protocols/anytls.md) | Inbound/outbound implementation behind `anytls`; TCP/UDP integration tests exist | No AnyTLS server protocol in the current server protocol enum | Several Client options are Parsed-only; current Chimera uses one logical stream ID per underlying connection and UoT v2 for UDP. |
| VLESS | Outbound implementation with stream, datagram, Vision, REALITY and XHTTP paths | Inbound implementation behind `vless` | Server Vision direct mode is explicitly not implemented yet. |
| Trojan | Outbound implementation behind `trojan` | Inbound and UDP handling behind `trojan` | Server fallback support has explicit restrictions; unsupported fallback types are rejected. |
| Hysteria 2 | Outbound implementation behind `hysteria` | QUIC inbound implementation behind `hysteria` | Server behavior has dedicated recent compatibility work; verify exact transport/version assumptions in tests. |
| VMess | No VMess outbound variant in the current Client outbound enum | AEAD VMess inbound implementation behind `vmess` | Server outbound routing does not imply a VMess outbound client implementation. |
| TUIC v5 | No TUIC outbound variant in the current Client outbound enum | QUIC inbound implementation behind `tuic` with E2E tests | Keep TUIC version-specific behavior tied to the current server implementation. |
| XHTTP | Client transport implementation used by VLESS | Server XHTTP transport with protocol/security matrix tests | Server deliberately rejects several Xray XHTTP fields that are not implemented yet, including `downloadSettings`. |
| WebSocket | Transport module behind `ws` | Transport module behind `ws` | A transport is not a proxy protocol by itself. |
| [gRPC transport](./protocols/grpc-transport.md) | Not present as a current Client outbound transport module | Server transport behind `grpc_transport`; Xray compatibility E2E exists | Single-stream Hunk mode is implemented; `multiMode` is explicitly rejected and several parsed gRPC tuning fields are not currently applied. |
| [HTTPUpgrade](./protocols/httpupgrade.md) | No current Client outbound transport module | Server transport behind `httpupgrade`; handler unit tests exist | HTTP/1.1 `GET`/`101` preface then raw stream, not WebSocket framing; `acceptProxyProtocol` and `ed` are explicitly rejected. |
| TLS | Shared client transport/security support | Server security wrapper behind `tls` | TLS is a security/transport layer, not an identity-bearing proxy protocol. |
| REALITY | Client implementation under `proxy/transport/reality` | Server implementation under `reality` plus inbound wrappers | Cross-project REALITY/Vision E2E and negative tests exist in the Server repository. |

## Source Anchors

### `Chimera_Client`

The most important capability anchors are:

- `clash-lib/src/config/internal/proxy.rs`: outbound protocol enum and protocol
  configuration structures.
- `clash-lib/src/app/outbound/manager.rs`: runtime outbound registration.
- `clash-lib/src/proxy/`: concrete inbound, outbound, and transport modules.
- `clash-lib/Cargo.toml`: build-feature gates.
- `clash-lib/tests/anytls_integration_tests.rs` and
  `clash-lib/tests/shadowsocks_integration_tests.rs`: integration evidence.

The current default build enables core/TLS/TUN/port/REALITY functionality, while
`anytls`, `shadowsocks`, `trojan`, `hysteria`, and `ws` are separate Cargo
features. Documentation must distinguish “implemented in source” from “present
in this binary build”.

### `Chimera_Server`

The most important capability anchors are:

- `chimera_server_lib/src/config/mod.rs`: protocol and stream-setting schema.
- `chimera_server_lib/src/config/server_config/`: validation and conversion into
  runtime configuration.
- `chimera_server_lib/src/beginning/`: socket/QUIC/XHTTP/gRPC transport entry
  points.
- `chimera_server_lib/src/handler/`: protocol handlers.
- `chimera_server_lib/Cargo.toml`: feature matrix; the current default is
  `full`.
- `chimera_server_app/tests/`: cross-implementation and matrix E2E coverage.

Important explicit rejection points currently include unsupported SOCKS fields,
parts of Trojan/VLESS fallback behavior, XHTTP fields, gRPC `multiMode`,
HTTPUpgrade compatibility options, non-zero REALITY `xver`, and selected
Shadowsocks/Vision modes. These should remain visible in user-facing docs rather
than being hidden behind a blanket “Xray compatible” statement.

## Application and Control-Plane Matrix

| Component | Source-backed responsibility | What it does not own |
| --- | --- | --- |
| `Chimera` | Profile/runtime generation, core selection/update, foreground core lifecycle, service-mode IPC, desktop system integration | Remote proxy wire protocols themselves |
| `Chimera_Service` | Privileged service lifecycle, local IPC, start/stop/restart/status of the selected core, selected privileged network operations | Proxy protocol parsing/forwarding |
| `AChimera` | Android `VpnService`, profile lifecycle, config verification/download, TUN ownership, UniFFI bridge, controller-backed traffic/memory/connection views | A separate proxy protocol engine; forwarding is delegated to the embedded Rust core |

## Maintenance Rule

When implementation and documentation disagree, update the Wiki from this
order of evidence:

1. executable/runtime path,
2. integration or interoperability tests,
3. typed configuration and validation,
4. repository README or planning text.

A README claim must not override code that explicitly rejects a field or leaves
it parsed-only.
