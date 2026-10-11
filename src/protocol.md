# Proxy Protocol Reference

A **proxy protocol** defines how a client identifies itself, requests a target,
and exchanges proxied TCP or UDP traffic with an endpoint. This chapter covers
those messages, authentication rules, framing, and failure behavior.

Transport wrappers and transport security have their own references:
[Transport Reference](./transport.md) and
[Transport Security Reference](./transport-security.md). They are **not**
additional proxy protocols.

## What Belongs to a Proxy Protocol?

A protocol reference owns:

- identity and proxy authentication (if the protocol defines them);
- destination address, command, and response semantics;
- TCP relay and UDP packet framing or association lifetime;
- protocol-level encryption, replay checks, and error handling;
- implementation evidence and compatibility limits for that protocol.

It does **not** define the HTTP path, gRPC service name, XHTTP session, TLS
certificate, or REALITY short ID used by an outer layer. Refer to the relevant
layer's documentation instead of copying its configuration into every protocol
page.

## Protocols

| Protocol                                      | Role                      | Protocol-specific characteristics                                                               |
| --------------------------------------------- | ------------------------- | ----------------------------------------------------------------------------------------------- |
| [SOCKS5](./protocols/socks5.md)               | Local/application proxy   | Method negotiation, destination commands, and UDP ASSOCIATE                                     |
| [HTTP Proxy](./protocols/http.md)             | Local/application proxy   | HTTP forwarding and CONNECT tunneling                                                           |
| [Shadowsocks](./protocols/shadowsocks.md)     | Remote proxy              | AEAD/AEAD-2022 encrypted TCP and UDP records                                                    |
| [AnyTLS](./protocols/anytls.md)               | Remote proxy              | Password authentication, framed logical streams, and UDP-over-TCP                               |
| [Trojan](./protocols/trojan.md)               | Remote proxy              | Shared-secret authentication and destination requests                                           |
| [Hysteria 2](./protocols/hysteria2.md)        | Remote proxy              | QUIC-based sessions with its own TCP/UDP framing                                                |
| [TUIC](./protocols/tuic.md)                   | Remote proxy              | QUIC-based connection authentication and TCP/UDP relay                                          |
| [VMess](./protocols/vmess.md)                 | Remote proxy              | AEAD request authentication and encrypted body records                                          |
| [VLESS](./protocols/vless.md)                 | Remote proxy              | Identity and destination dispatch; optional VLESS Encryption                                    |
| [Dokodemo-door](./protocols/dokodemo-door.md) | Server forwarding inbound | Fixed-target or original-destination forwarding, without its own proxy authentication handshake |

[Trojan wire format](./protocols/trojan/wire-format.md) and
[Trojan traffic handling](./protocols/trojan/traffic-handling.md) expand the
Trojan protocol description without defining outer transport behavior.

## Where the Layers Meet

For a stack that supports independently configurable layers, read it from the
inner proxy messages outward:

```text
Proxy protocol:    identity + destination + proxied bytes
Transport method:  delivery of those bytes (RAW / XHTTP / gRPC / ...)
Security layer:    outer channel protection (TLS / REALITY / ...)
Network:           TCP or UDP
```

This is a **responsibility map**, not a guarantee that any arbitrary combination
works. See the [Transport Reference](./transport.md) for framing and HTTP
wrappers, and the [Transport Security Reference](./transport-security.md) for
outer-handshake responsibilities.

Some protocols intentionally bind these layers together:

- Hysteria 2 and TUIC build their sessions on QUIC, including QUIC TLS.
  QUIC-specific details remain in the respective protocol chapters.
- AnyTLS and baseline Trojan explicitly depend on TLS. Their protocol chapters
  describe that requirement without treating TLS configuration as a proxy
  command.
- Shadowsocks and VMess include protocol-owned cryptographic framing; VLESS may
  use VLESS Encryption. None of those automatically implies a particular outer
  transport.

## Choosing a Protocol

For a local application entrypoint, start with [SOCKS5](./protocols/socks5.md)
or [HTTP Proxy](./protocols/http.md). For remote encrypted proxy semantics,
compare [Shadowsocks](./protocols/shadowsocks.md),
[AnyTLS](./protocols/anytls.md), [Trojan](./protocols/trojan.md), and
[VMess](./protocols/vmess.md). For QUIC-based remote sessions, compare
[Hysteria 2](./protocols/hysteria2.md) and [TUIC](./protocols/tuic.md).

For Xray-style layered configurations, begin with [VLESS](./protocols/vless.md)
or [VMess](./protocols/vmess.md), then select a supported transport and security
mechanism from their separate chapters. Never infer support for a combination
merely because its constituent parts appear in the source.

## Implementation and Troubleshooting

Read [Implementation Status and Source Evidence](./implementation-status.md) and
[Test Evidence and Interoperability Matrix](./test-evidence.md) for
component-specific availability and verification. Configuration parsing alone is
not proof of runtime or cross-project compatibility.

When debugging, check network reachability, then any outer security handshake,
then transport framing/session setup, and only then proxy authentication,
destination dispatch, and TCP/UDP relay behavior. See
[End-to-End Troubleshooting](./troubleshooting.md) for the full procedure.
