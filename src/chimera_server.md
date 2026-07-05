# Chimera_Server

## Purpose and Scope

`Chimera_Server` is a Rust server core that aims to stay compatible with
`xray-core` configuration shape and inbound protocol behavior. The current local
README describes the project as focused on inbound parsing, inbound dispatch,
and protocol semantics first; outbound, routing, and policy modules are still
being expanded.

The workspace is split into:

| Crate                | Role                                                                                                         |
| -------------------- | ------------------------------------------------------------------------------------------------------------ |
| `chimera_server_app` | Application entrypoint; reads config and starts the runtime.                                                 |
| `chimera_server_lib` | Core library for config parsing, protocol handlers, runtime state, gRPC/API services, and transport helpers. |
| `chimera_cli`        | Utility CLI; currently includes an `x25519` helper compatible with `xray x25519` usage.                      |

## Configuration Model

The server follows the xray-core-style JSON/JSON5 configuration model. Existing
examples and tests focus on `inbounds` and related `streamSettings`:

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

Prefer `json5` for local development because the repository examples and command
line instructions use it.

## Current Capability Map

Local code and README evidence show active work around:

- VMess, VLESS, Trojan, SOCKS, Hysteria2, TUIC, and XHTTP-related inbound
  parsing/handling, gated by Cargo features where appropriate.
- TLS, Reality, WebSocket, QUIC, HTTP/3, and XHTTP transport layers.
- gRPC API services for runtime inspection/control when the `api` feature is
  enabled.
- traffic statistics and routing state scaffolding.

Treat this as an implementation map, not a blanket compatibility guarantee. The
project README explicitly says outbound, routing, and policy behavior are still
under construction.

## Running

From the `Chimera_Server` workspace:

```bash
cargo run --package chimera_server_app -- --config path/to/config.json5
```

To generate Reality key material in an xray-compatible style:

```bash
cargo run -p chimera_cli -- x25519 --count 1 --format base64
```

## Examples

The local server repository currently lists these example configs:

- `examples/01-api.json5`
- `examples/02_trojan_ws_tls_30919.json5`
- `examples/03_vless_ws_tls_36050.json5`
- `examples/04_vless_tcp_50584.json5`
- `examples/05_vless_ws_56321.json5`
- `examples/06-hysteria-43210.json5`

## Development Checks

```bash
cargo build --all-features
cargo fmt --all
cargo clippy --all-targets --all-features -- -D warnings
cargo test
```
