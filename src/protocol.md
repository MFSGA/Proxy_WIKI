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
Shadowsocks / AnyTLS / Trojan / Hysteria 2 / TUIC / VMess / VLESS
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
| Shadowsocks | Remote proxy protocol | TCP or UDP | Built-in AEAD/AEAD-2022 encryption and authentication | Encrypted TCP/UDP proxying |
| AnyTLS | Remote proxy protocol | TLS over TCP | TLS + SHA-256 password token + framed logical stream | TLS-carried TCP/UDP-over-TCP proxying |
| Trojan | Remote proxy protocol | TLS over TCP in the baseline design | TLS + shared-secret authentication | TLS-oriented remote proxying |
| Hysteria 2 | Remote proxy protocol + transport design | QUIC over UDP | QUIC TLS + Hysteria authentication | TCP/UDP proxying on lossy/high-latency paths |
| TUIC | Remote proxy protocol | Multiplexed secure transport, commonly QUIC | TLS session + connection-bound auth | Low-latency TCP/UDP relay |
| VMess | Remote proxy protocol | Ordered Xray transport stream | VMess AEAD user authentication + encrypted body records | Xray/V2Ray-compatible encrypted TCP/UDP proxying |
| VLESS | Remote proxy protocol | RAW, XHTTP, gRPC, and other supported transports | Optional VLESS Encryption and/or separate TLS/REALITY layer | Xray-compatible identity and proxy dispatch |
| XHTTP | Transport method | HTTP-oriented request/response flows | Usually TLS or REALITY | Xray transport through HTTP-aware infrastructure |
| gRPC Transport | Transport method | HTTP/2-compatible gRPC stream | Plain, TLS, or REALITY on current Server | Xray-compatible Hunk byte-stream transport |
| HTTPUpgrade | Transport method | HTTP/1.1 upgrade preface, then raw TCP stream | Depends on outer security/inner protocol | HTTP-looking preface for an inner proxy stream |
| Dokodemo-door | Server forwarding inbound | Raw TCP or UDP; optional transport wrappers on TCP | No built-in user authentication or encryption | Fixed-target forwarding or Linux original-destination interception |
| REALITY | Transport-security mechanism | Supported Xray transports such as RAW/XHTTP/gRPC | REALITY key/short-ID + TLS-like handshake behavior | Xray transport security and camouflage |

## Current Chimera Reading Guide

The table below describes how these topics currently appear in this Wiki. It is
not a substitute for checking the implementation repository before deployment.

| Item | Chimera_Client documentation | Chimera_Server documentation |
| --- | --- | --- |
| SOCKS5 | Current local inbound | SOCKS-related inbound work listed |
| HTTP proxy | Current local inbound | HTTP inbound exists |
| Shadowsocks | Current inbound/outbound behind `shadowsocks`; TCP/UDP integration tests exist | Current inbound TCP/UDP behind `shadowsocks`, with explicit cipher/mode limits |
| AnyTLS | Current inbound/outbound behind `anytls`; TCP/UDP integration tests exist | No current AnyTLS inbound protocol |
| Trojan | Current outbound behind `trojan` | Trojan inbound work listed |
| Hysteria 2 | Current capability | Hysteria 2 inbound/example listed |
| TUIC | No current outbound enum variant | TUIC v5 inbound implementation listed |
| VMess | No current outbound enum variant | VMess AEAD inbound implementation listed |
| VLESS | Current outbound capability | VLESS inbound and examples listed |
| XHTTP | Current capability | XHTTP-related transport work listed |
| gRPC transport | No current outbound transport module | Current transport behind `grpc_transport`; Xray compatibility E2E exists; `multiMode` rejected |
| HTTPUpgrade | No current outbound transport module | Current transport behind `httpupgrade`; raw stream after `101`; `acceptProxyProtocol`/`ed` rejected |
| Dokodemo-door | Not a Client remote outbound protocol | Current TCP/UDP forwarding inbound; Linux-only `followRedirect` uses original destination |
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

### Encrypted remote proxying

Use [Shadowsocks](./protocols/shadowsocks.md) when you need the classic AEAD / AEAD-2022 encrypted record model. Use [AnyTLS](./protocols/anytls.md) for the TLS-carried framed model implemented by Chimera Client. Use [Trojan](./protocols/trojan.md) as the reference for the baseline TLS + password protocol model. If an implementation adds WebSocket, SIP003 plugins, or another transport, treat that as an additional layer.

### UDP/QUIC-oriented remote proxying

Compare [Hysteria 2](./protocols/hysteria2.md) and
[TUIC](./protocols/tuic.md). Both rely heavily on a healthy UDP path, but their
authentication, task model, and UDP-relay framing differ.

### Xray-style layered deployments

For the current VMess AEAD model, start with
[VMess](./protocols/vmess.md). For VLESS-based stacks, read these together:

1. [VLESS](./protocols/vless.md) — proxy protocol, user identity, and optional
   VLESS Encryption.
2. Choose a transport when required: [XHTTP](./protocols/xhttp.md),
   [gRPC](./protocols/grpc-transport.md), or
   [HTTPUpgrade](./protocols/httpupgrade.md), according to the actual peer/core
   support.
3. [REALITY](./protocols/reality.md) — optional transport-security layer.

Keeping proxy protocol, protocol-layer encryption, transport, and
transport-security responsibilities separate makes configuration and
troubleshooting much easier.

## Security Rules of Thumb

- SOCKS5 and a local HTTP proxy do not provide encryption by themselves.
- Do not expose unauthenticated local proxy listeners to the public internet.
- Keep certificate verification enabled for TLS-based remote protocols.
- Treat Shadowsocks keys/passwords, AnyTLS passwords, REALITY private keys, VMess IDs, Trojan passwords, Hysteria credentials, and TUIC passwords as secrets.
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
- [Shadowsocks](./protocols/shadowsocks.md) — classic AEAD and AEAD-2022 TCP/UDP encrypted proxying.
- [AnyTLS](./protocols/anytls.md) — TLS-carried password authentication, framed streams, and UDP-over-TCP v2.
- [Trojan](./protocols/trojan.md) — TLS-based password proxy with fallback behavior.
  - [Wire Format](./protocols/trojan/wire-format.md)
  - [Traffic Handling](./protocols/trojan/traffic-handling.md)
- [Hysteria 2](./protocols/hysteria2.md) — QUIC-based TCP/UDP proxy with HTTP/3 authentication behavior.
- [TUIC](./protocols/tuic.md) — multiplexed low-latency TCP/UDP proxy protocol, commonly over QUIC.
- [VMess](./protocols/vmess.md) — current VMess AEAD authentication, encrypted records, TCP/UDP, and Mux layering.
- [VLESS](./protocols/vless.md) — lightweight Xray proxy protocol, identity layer, and optional VLESS Encryption.
- [XHTTP Transport](./protocols/xhttp.md) — HTTP-oriented Xray transport method.
- [gRPC Transport](./protocols/grpc-transport.md) — HTTP/2/gRPC Hunk wrapper around an inner proxy byte stream.
- [HTTPUpgrade Transport](./protocols/httpupgrade.md) — HTTP/1.1 upgrade preface followed by raw inner-protocol bytes.
- [Dokodemo-door](./protocols/dokodemo-door.md) — fixed-target and Linux original-destination TCP/UDP forwarding inbound.
- [REALITY](./protocols/reality.md) — Xray transport-security mechanism.
