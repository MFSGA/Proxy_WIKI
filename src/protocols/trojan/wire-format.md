# Trojan Wire Format

## Scope

This page documents the baseline Trojan protocol framing after the TLS session
has been established. Transport wrappers added by individual implementations
can add another layer around this baseline and should be documented separately.

## 1. TLS Handshake

Trojan starts with a normal TLS handshake. Only after TLS succeeds does the
client send Trojan authentication and destination information.

If the TLS handshake fails, there is no valid Trojan application session. A
server may also provide ordinary HTTPS behavior for non-Trojan traffic as part
of its fallback design.

## 2. Initial Application Request

The first Trojan application data has this logical form:

```text
+-----------------------+---------+----------------+---------+----------+
| hex(SHA224(password)) |  CRLF   | Trojan Request |  CRLF   | Payload  |
+-----------------------+---------+----------------+---------+----------+
|          56           | 0D 0A   |    Variable    | 0D 0A   | Variable |
+-----------------------+---------+----------------+---------+----------+
```

The 56-byte authentication field is the lowercase/uppercase-insensitive hex
representation of the 28-byte SHA-224 digest, as expected by the implementation.
The exact credential handling should follow the endpoint implementation rather
than relying on manual hashing in normal user configuration.

The optional initial payload allows the client to send application data in the
same logical request instead of waiting for an additional round trip.

## 3. Trojan Request

The request reuses a SOCKS5-like destination format:

```text
+-----+------+----------+----------+
| CMD | ATYP | DST.ADDR | DST.PORT |
+-----+------+----------+----------+
|  1  |  1   | Variable |    2     |
+-----+------+----------+----------+
```

### `CMD`

| Value | Meaning |
| --- | --- |
| `0x01` | TCP `CONNECT` |
| `0x03` | UDP association |

### `ATYP`

| Value | Address form |
| --- | --- |
| `0x01` | IPv4 |
| `0x03` | Domain name |
| `0x04` | IPv6 |

`DST.PORT` is encoded in network byte order.

For address-field semantics, SOCKS5 RFC 1928 is a useful reference because the
Trojan request intentionally follows the same general address model.

## 4. TCP Payload

For a valid TCP request, bytes following the second CRLF can immediately become
payload for the requested destination. After the request has been accepted,
subsequent application data is relayed through the TLS connection.

Conceptually:

```text
TLS
└── Trojan authentication + destination
    └── TCP application byte stream
```

## 5. UDP Datagram Framing

For UDP association, each UDP datagram is framed separately inside the TLS
stream:

```text
+------+----------+----------+--------+---------+----------+
| ATYP | DST.ADDR | DST.PORT | Length |  CRLF   | Payload  |
+------+----------+----------+--------+---------+----------+
|  1   | Variable |    2     |   2    | 0D 0A   | Variable |
+------+----------+----------+--------+---------+----------+
```

- `ATYP`, `DST.ADDR`, and `DST.PORT` identify the UDP destination.
- `Length` is the UDP payload length in network byte order.
- `Payload` is one UDP datagram.

Because UDP datagrams are carried inside a TLS stream, packet boundaries are
represented by this framing rather than by the underlying transport.

## 6. Parser Considerations

An implementation should treat the request as structured binary data rather
than assuming a single socket read contains the entire header. TLS and TCP can
split application data across reads.

Important parser checks include:

- complete 56-byte authentication field,
- exact CRLF delimiters,
- valid `CMD`,
- supported `ATYP`,
- bounded domain-name and payload lengths,
- complete destination port,
- and complete UDP payload before dispatch.

Malformed input should not panic the server or expose protocol-specific debug
information to an unauthenticated peer.

## 7. Relationship to Chimera

This wire format is the baseline Trojan reference. `Chimera_Client` currently
documents Trojan together with WebSocket support, so a deployed connection may
contain an additional transport layer around the Trojan payload. Likewise,
`Chimera_Server` compatibility should be tested against the exact transport and
framing combination being used.

## References

- Trojan protocol: <https://trojan-gfw.github.io/trojan/protocol.html>
- SOCKS5 address model: <https://www.rfc-editor.org/rfc/rfc1928>
