# Protocol Reference

This section compares the proxy protocols, transport methods, and transport
security mechanisms used around the Chimera ecosystem.

It is implementation-oriented documentation, not a replacement for upstream
specifications. When a wire-format or compatibility detail matters, follow the
primary references linked from each protocol page.

## Read the Stack in Layers

Not every item in this chapter belongs to the same network layer.

A useful model is:

```text
Application
    │
    ▼
Local inbound
SOCKS5 / HTTP
    │
    ▼
Remote proxy protocol
Trojan / Hysteria 2 / TUIC / VLESS
    │
    ▼
Transport method
RAW / WebSocket / XHTTP / QUIC-based protocol transport
    │
    ▼
Transport security
TLS / REALITY / QUIC TLS
    │
    ▼
Internet
```

Some protocols bundle several of these responsibilities together. Hysteria 2
and TUIC, for example, are designed around QUIC and its TLS security. VMess
carries its own authenticated/encrypted proxy records, while VLESS is a lighter
proxy-protocol layer that can use current VLESS Encryption and/or a separate
transport-security mechanism.

## Layer Comparison

| Item | Primary role | Typical underlying transport | Security model | Main use |
| --- | --- | --- | --- | --- |
| SOCKS5 | Local/application proxy | TCP control + optional UDP relay | None by default | General local application ingress |
| HTTP Proxy / CONNECT | Local/application proxy | TCP | None by default; HTTPS remains end-to-end inside CONNECT | Browser/system HTTP proxy ingress |
| Trojan | Remote proxy protocol | TLS over TCP in the baseline design | TLS + shared-secret authentication | TLS-oriented remote proxying |
| Hysteria 2 | Remote proxy protocol + transport design | QUIC over UDP | QUIC TLS + Hysteria authentication | TCP/UDP proxying on lossy/high-latency paths |
| TUIC | Remote proxy protocol | Multiplexed secure transport, commonly QUIC | TLS session + connection-bound auth | Low-latency TCP/UDP relay |
| VMess | Remote proxy protocol | Ordered Xray transport stream | VMess AEAD user authentication + encrypted body records | Xray/V2Ray-compatible encrypted TCP/UDP proxying |
| VLESS | Remote proxy protocol | RAW, XHTTP, gRPC, and other supported transports | Optional VLESS Encryption and/or separate TLS/REALITY layer | Xray-compatible identity and proxy dispatch |
| XHTTP | Transport method | HTTP-oriented request/response flows | Usually TLS or REALITY | Xray transport through HTTP-aware infrastructure |
| REALITY | Transport-security mechanism | Supported Xray transports such as RAW/XHTTP/gRPC | REALITY key/short-ID + TLS-like handshake behavior | Xray transport security and camouflage |

## Current Chimera Reading Guide

The table below describes how these topics currently appear in this Wiki. It is
not a substitute for checking the implementation repository before deployment.

| Item | Chimera_Client documentation | Chimera_Server documentation |
| --- | --- | --- |
| SOCKS5 | Current local inbound | SOCKS-related inbound work listed |
| HTTP proxy | Current local inbound | Not the main remote-server protocol focus |
| Trojan | Current capability, currently documented with WebSocket | Trojan inbound work listed |
| Hysteria 2 | Current capability | Hysteria 2 inbound/example listed |
| TUIC | Planned client capability | TUIC inbound work listed |
| VMess | Planned/targeted client capability | VMess inbound work listed |
| VLESS | Not yet listed as a standalone current client capability | VLESS inbound and examples listed |
| XHTTP | Current capability | XHTTP-related transport work listed |
| REALITY | Current `Reality + TCP` capability | REALITY transport and VLESS + REALITY example listed |

The important distinction is **capability presence versus compatibility
parity**. A parser or transport implementation existing in the codebase does
not automatically mean every upstream option, version, flow mode, or client is
supported.

## Choosing a Starting Point

### Local application proxying

Start with [SOCKS5](./protocols/socks5.md) or
[HTTP Proxy](./protocols/http.md). These are the easiest ways to validate the
client core before adding TUN, transparent routing, or DNS interception.

### Simple TLS-based remote proxy

Use [Trojan](./protocols/trojan.md) as the reference for the baseline
TLS + password protocol model. If an implementation adds WebSocket or another
transport, treat that as an additional layer.

### UDP/QUIC-oriented remote proxying

Compare [Hysteria 2](./protocols/hysteria2.md) and
[TUIC](./protocols/tuic.md). Both rely heavily on a healthy UDP path, but their
authentication, task model, and UDP-relay framing differ.

### Xray-style layered deployments

For the current VMess AEAD model, start with
[VMess](./protocols/vmess.md). For VLESS-based stacks, read these together:

1. [VLESS](./protocols/vless.md) — proxy protocol, user identity, and optional
   VLESS Encryption.
2. [XHTTP](./protocols/xhttp.md) — optional HTTP-oriented transport.
3. [REALITY](./protocols/reality.md) — optional transport-security layer.

Keeping proxy protocol, protocol-layer encryption, transport, and
transport-security responsibilities separate makes configuration and
troubleshooting much easier.

## Security Rules of Thumb

- SOCKS5 and a local HTTP proxy do not provide encryption by themselves.
- Do not expose unauthenticated local proxy listeners to the public internet.
- Keep certificate verification enabled for TLS-based remote protocols.
- Treat REALITY private keys, VMess IDs, Trojan passwords, Hysteria credentials,
  and TUIC passwords as secrets.
- For QUIC-based protocols, verify UDP reachability before changing protocol
  tuning.
- Validate the exact proxy + transport + security combination supported by the
  selected core rather than assuming configuration portability.

## Troubleshooting by Layer

When a remote profile fails, debug from the bottom upward:

1. **Network reachability** — DNS, IP route, TCP/UDP port, firewall.
2. **Transport security** — TLS certificate/SNI or REALITY key/short ID.
3. **Transport method** — RAW/WebSocket/XHTTP/QUIC settings.
4. **Proxy authentication** — password, UUID/user ID, Hysteria/TUIC auth.
5. **Destination routing** — rules, DNS mode, outbound group.
6. **Advanced tuning** — multiplexing, congestion control, padding, custom
   headers, flow modes.

Do not start by changing all six layers at once.

## Deep Dives

- [SOCKS5](./protocols/socks5.md) — standardized general-purpose TCP/UDP local proxy.
- [HTTP Proxy](./protocols/http.md) — application HTTP proxy and `CONNECT` tunneling.
- [Trojan](./protocols/trojan.md) — TLS-based password proxy with fallback behavior.
  - [Wire Format](./protocols/trojan/wire-format.md)
  - [Traffic Handling](./protocols/trojan/traffic-handling.md)
- [Hysteria 2](./protocols/hysteria2.md) — QUIC-based TCP/UDP proxy with HTTP/3 authentication behavior.
- [TUIC](./protocols/tuic.md) — multiplexed low-latency TCP/UDP proxy protocol, commonly over QUIC.
- [VMess](./protocols/vmess.md) — current VMess AEAD authentication, encrypted records, TCP/UDP, and Mux layering.
- [VLESS](./protocols/vless.md) — lightweight Xray proxy protocol, identity layer, and optional VLESS Encryption.
- [XHTTP Transport](./protocols/xhttp.md) — HTTP-oriented Xray transport method.
- [REALITY](./protocols/reality.md) — Xray transport-security mechanism.
