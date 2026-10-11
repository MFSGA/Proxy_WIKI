# Transport Security Reference

**Transport security** protects and/or authenticates the outer connection. It
does not contain the inner proxy protocol's destination request, UUID, or
password, and it must not be treated as a substitute for that protocol.

The distinct responsibilities are documented under
[Proxy Protocol Reference](./protocol.md) (inner proxy semantics) and
[Transport Reference](./transport.md) (carrying proxy bytes).

## Security Mechanisms

| Mechanism | Security-layer responsibility                                                   | Documentation                                                       |
| --------- | ------------------------------------------------------------------------------- | ------------------------------------------------------------------- |
| TLS       | Encrypted channel and certificate-based peer authentication                     | [Deployment Security and Threat Model](./security-model.md)         |
| REALITY   | TLS-like outer handshake, key/short-ID validation, and target/fallback behavior | [REALITY](./transport-security/reality.md)                          |
| QUIC TLS  | Handshake and channel security integrated with QUIC                             | [Hysteria 2](./protocols/hysteria2.md), [TUIC](./protocols/tuic.md) |

Protocol-owned cryptography is separate: Shadowsocks and VMess define encrypted
proxy records, and VLESS can use VLESS Encryption. Consult their
[protocol chapters](./protocol.md) for those semantics. Security mechanisms and
transport wrappers are not freely interchangeable; the actual peer/core
determines allowed combinations.

## Layer Boundaries

In an independently layered TCP-based configuration, the security handshake
occurs before the protected transport can deliver the inner proxy stream:

```text
TCP connection
    → TLS / REALITY authentication (if configured)
    → transport session / framing (RAW, XHTTP, gRPC, ...)
    → proxy-protocol authentication and target request
```

This sequence is conceptual: individual transports and QUIC-based protocols have
different negotiation requirements. Success at the security layer does **not**
mean the HTTP transport route or the proxy user was accepted.

Security-page configuration owns certificates, SNI and verification, REALITY key
material, short IDs, fingerprints and fallback behavior. Transport-page
configuration owns HTTP/stream framing, while protocol-page configuration owns
proxy identity and destination handling.

## Verification and Diagnostics

Verify the selected core and both endpoint directions in
[Implementation Status](./implementation-status.md) and the
[interoperability tests](./test-evidence.md). For failed connections,
distinguish TCP/UDP reachability, security-handshake rejection, transport setup
failure, and inner protocol authentication or dispatch errors. See
[End-to-End Troubleshooting](./troubleshooting.md).
