# Chimera_Server

## Purpose and Scope

`Chimera_Server` is the inbound/server core of the Chimera ecosystem. Its
configuration model intentionally follows Xray-style `inbounds`,
`streamSettings`, transport wrappers, and security settings, but compatibility
must be evaluated field by field and path by path rather than assumed from
configuration shape alone.

The server source is organized around this data path:

```text
JSON / JSON5 / YAML
        |
        v
config definitions
        |
        v
ServerConfig validation/conversion
        |
        v
beginning: listener / TCP / UDP / QUIC / XHTTP / gRPC
        |
        v
transport + security wrappers
        |
        v
protocol handler
        |
        v
outbound/session + traffic/runtime state
```

For the evidence terminology used below, see
[Implementation Status and Source Evidence](./implementation-status.md).

## Workspace Layout

| Crate | Role |
| --- | --- |
| `chimera_server_app` | Application entry point and integration-test surface. |
| `chimera_server_lib` | Config parsing, runtime construction, listener/transport entry points, protocol handlers, routing/outbound state, traffic and control-plane services. |
| `chimera_cli` | Administrative helper CLI, including X25519 key utilities. |
| `chimera_tcp_reality_server` | Focused TCP/REALITY server crate used for a narrower runtime path. |

Important source anchors are:

- `chimera_server_lib/src/config/mod.rs`,
- `chimera_server_lib/src/config/server_config/`,
- `chimera_server_lib/src/beginning/`,
- `chimera_server_lib/src/handler/`,
- `chimera_server_lib/src/reality/`,
- `chimera_server_app/tests/`.

## Build Features

The current server library exposes protocol/transport features including:

- `hysteria`,
- `http`,
- `mixed`,
- `httpupgrade`,
- `grpc_transport`,
- `trojan`,
- `ws`,
- `tls`,
- `reality`,
- `shadowsocks`,
- `vless`,
- `vmess`,
- `tuic`,
- `traffic`,
- `api`.

The current default is `full`, so the normal server build includes this feature
set. Smaller application feature sets such as `minimal-vless` and
`minimal-vless-tls` also exist and should be treated as different capability
artifacts.

## Current Protocol and Transport Surface

The typed protocol configuration currently includes:

- VLESS,
- VMess,
- Hysteria 2,
- Dokodemo-door,
- Trojan,
- TUIC v5,
- XHTTP,
- SOCKS,
- HTTP,
- Mixed,
- Shadowsocks.

Transport/security code also includes WebSocket, HTTPUpgrade, gRPC transport,
XHTTP, TLS, REALITY, TCP/UDP and QUIC entry paths.

This list means source/runtime paths exist. It is **not** a claim that every
Xray field or every transport/protocol combination has parity.

## Explicit Compatibility Boundaries

One of the most useful properties of the current server is that unsupported
compatibility fields are often rejected deliberately instead of silently
ignored. The Wiki should preserve these boundaries.

Current source includes explicit rejections or unimplemented paths such as:

| Area | Current boundary |
| --- | --- |
| SOCKS | `settings.ip` is not supported yet. |
| SOCKS | `settings.userLevel` is not supported yet. |
| Trojan fallback | Unsupported fallback types and Unix-socket destinations are rejected. |
| VLESS fallback | Unsupported fallback types and Unix-socket destinations are rejected. |
| XHTTP | `headers` and several additional Xray fields are rejected when unsupported. |
| XHTTP | `downloadSettings` is not supported yet. |
| gRPC transport | `grpcSettings.multiMode` is not supported yet. |
| HTTPUpgrade | `acceptProxyProtocol` and `ed` are not supported yet. |
| REALITY | `xver` values other than `0` are not supported yet. |
| Shadowsocks | `xchacha20-poly1305` is not supported yet. |
| VLESS Vision | Vision direct mode is not implemented yet. |
| UDP outbound proxying | Some outbound protocol selections, including VMess in the inspected path, are rejected as unsupported. |

These restrictions are more precise than saying “Xray compatible”. When a
field is added upstream, the Server builder and runtime must both be checked
before the Wiki marks it supported.

## Configuration Model

A typical VLESS + REALITY inbound retains the familiar Xray-style shape:

```json
{
  "inbounds": [
    {
      "tag": "vless-reality",
      "protocol": "vless",
      "listen": "0.0.0.0",
      "port": 443,
      "settings": {
        "clients": [
          { "id": "YOUR-UUID", "flow": "xtls-rprx-vision" }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "dest": "example.com:443",
          "serverNames": ["example.com"],
          "privateKey": "YOUR-PRIVATE-KEY",
          "shortIds": ["0123456789abcdef"]
        }
      }
    }
  ]
}
```

Configuration compatibility has three distinct outcomes:

1. accepted and applied,
2. accepted only where explicitly documented as compatibility parsing,
3. rejected early because the runtime path does not support the field.

Prefer early rejection over implying behavior that does not exist.

## Listener and Handler Separation

The server architecture keeps transport acceptance separate from proxy
semantics. For example:

```text
TCP listener
  +-- optional TLS / REALITY
  +-- optional WebSocket / HTTPUpgrade / XHTTP / gRPC transport
  +-- VLESS / VMess / Trojan / SOCKS / HTTP / ... handler
```

QUIC entry paths similarly dispatch Hysteria 2 or TUIC to protocol-specific
handlers.

This separation is important when debugging: a successful TLS/REALITY or HTTP
transport handshake does not prove that the inner protocol authentication or
request header succeeded.

## Interoperability and E2E Evidence

The server repository contains dedicated tests that are stronger evidence than
a capability list. Current examples include:

- `chimera_client_reality_vision_e2e.rs`,
- `chimera_client_reality_vision_negative_e2e.rs`,
- `reality_vision_matrix_e2e.rs`,
- `reality_vision_negative_e2e.rs`,
- `xhttp_matrix_e2e.rs`,
- `xhttp_protocol_matrix_e2e.rs`,
- `xhttp_security_matrix_e2e.rs`,
- `grpc_xray_compat_e2e.rs`,
- `grpc_external_integration.rs`,
- `socks_external_integration.rs`,
- `xray_client_proxy_e2e.rs`,
- TUIC E2E tests inside the handler module.

When describing a combination as interoperable, link the claim to one of these
concrete tests or add a new test first.

## Control Plane and Observability

The server data plane is intentionally separate from control-plane surfaces.
The codebase includes:

- runtime/service registry state,
- traffic accounting,
- gRPC API services when `api` is enabled,
- MCP-related control/data push code,
- tracing-based logs.

These should not be confused with the proxy gRPC **transport**. The API gRPC
service is a management plane; `grpc_transport` is a forwarding transport for an
inbound proxy protocol.

## Running

From the `Chimera_Server` workspace:

```bash
cargo run --package chimera_server_app -- --config path/to/config.json5
```

To generate X25519 key material:

```bash
cargo run -p chimera_cli -- x25519 --count 1 --format base64
```

## Development Checks

The repository guidance uses:

```bash
cargo build --all-features
cargo fmt --all
cargo clippy --all-targets --all-features -- -D warnings
cargo test
```

For documentation maintenance, protocol capability claims should be updated only
after the relevant configuration/runtime path and its tests have been inspected.
