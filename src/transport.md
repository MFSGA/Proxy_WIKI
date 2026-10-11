# Transport Reference

A **transport** carries the byte stream of a supported inner proxy protocol
between peers. It defines connection setup, HTTP or stream framing, session
lifetime, ordering, and backpressure. It does **not** authenticate proxy users,
choose the proxied destination, or interpret the inner protocol's command.

For those responsibilities see [Proxy Protocol Reference](./protocol.md). For
TLS/REALITY and other channel-protection questions, see
[Transport Security Reference](./transport-security.md).

## Transport Methods

| Transport                                  | Transport-owned behavior                                           | What it passes to the inner protocol |
| ------------------------------------------ | ------------------------------------------------------------------ | ------------------------------------ |
| [XHTTP](./transports/xhttp.md)             | HTTP request/response modes, split sessions, ordering, and padding | Reassembled ordered bytes            |
| [gRPC](./transports/grpc-transport.md)     | HTTP/2 gRPC stream and Hunk message envelope                       | Decapsulated stream bytes            |
| [HTTPUpgrade](./transports/httpupgrade.md) | HTTP/1.1 upgrade preface and 101 response                          | Raw stream bytes after the upgrade   |

Other transport paths such as **RAW/TCP** and **WebSocket** also exist in the
broader Chimera/Xray ecosystem. The
[implementation matrix](./implementation-status.md) distinguishes the specific
Client and Server paths currently documented. This page does not claim that
every protocol or direction supports every transport.

QUIC is different: protocols such as [Hysteria 2](./protocols/hysteria2.md) and
[TUIC](./protocols/tuic.md) define protocol-specific semantics over QUIC. Their
QUIC framing and session rules belong to those protocol chapters rather than a
hypothetical interchangeable Xray transport wrapper.

## Ownership Boundary

```text
Inner proxy bytes (e.g. a VLESS request)
    ↓
Transport encoder (e.g. XHTTP, gRPC, HTTPUpgrade)
    ↓
Optional transport security (e.g. TLS or REALITY)
    ↓
TCP / underlying network
```

The receiving peer reverses that path. An HTTP `200`, gRPC status, or HTTP `101`
can confirm **transport-layer** progress; it never, by itself, confirms that the
inner proxy authentication or requested destination succeeded.

For a transport document, put `path`, `host`, `serviceName`, stream envelopes,
timeout handling, and HTTP behavior here. Put UUIDs, passwords, proxy commands,
and destination address encoding in the protocol reference. Keep certificate
validation and REALITY authentication in the security reference.

## Compatibility and Failure Isolation

Before deploying a composition, verify the actual **client direction, server
direction, inner proxy protocol, transport method, security layer, and feature
gates** together. See [Implementation Status](./implementation-status.md) and
[Test Evidence](./test-evidence.md); a working transport listener alone is not
an end-to-end proxy compatibility test.

Diagnose transport problems after network/security connectivity and before inner
proxy parsing: inspect HTTP route and headers, ALPN or HTTP version where
relevant, transport-specific session/framing errors, and then the handoff of
decoded bytes to the proxy handler. See
[End-to-End Troubleshooting](./troubleshooting.md).
