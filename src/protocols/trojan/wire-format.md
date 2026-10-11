# Trojan Wire Format

This page describes the base Trojan request and relay framing after any
configured outer transport has been established. TLS, WebSocket, and other
transport wrappers are separate layers; their order and availability depend on
the implementation.

## TLS and Stream Boundaries

In the common TLS deployment, the client establishes TLS before sending
Trojan application data. TLS records are not Trojan message boundaries: a
request can span multiple TLS records, and a record can contain both the end of
a request and following payload. Parsers must read the decrypted connection as
an ordered byte stream rather than assume one socket read or TLS record
contains one complete message.

TLS protects Trojan fields and relayed data when it is enabled. The client
should validate the server certificate and hostname unless an explicitly
configured trust model says otherwise.

## Initial Request

After the outer transport is ready, the client sends this request:

```text
+-----------------------+---------+----------------+---------+-----------------+
| hex(SHA224(password)) |  CRLF   | Trojan Request |  CRLF   | Payload / frame |
+-----------------------+---------+----------------+---------+-----------------+
|          56           |   2     |    Variable    |    2    |    Optional     |
+-----------------------+---------+----------------+---------+-----------------+
```

The authentication field is 56 ASCII hexadecimal characters representing the
28-byte SHA-224 digest of the configured password. The current Chimera client
emits lowercase hexadecimal. The current Chimera server matches the encoded
digest exactly, so this client/server combination requires the lowercase form
it emits. This describes the accepted encoding; it does not imply constant-time
authentication comparison. There is no separate authentication negotiation
or success packet.

The request header is terminated by the second `CRLF`. After it, `CONNECT`
carries raw bytes for the destination TCP stream; `UDP ASSOCIATE` begins the
UDP frame stream described below. There is no additional Trojan success frame
before relaying begins.

With no initial payload, request sizes are:

| Destination type | Trojan Request | Full initial header |
| --- | ---: | ---: |
| IPv4 | 8 bytes | 68 bytes |
| IPv6 | 20 bytes | 80 bytes |
| Domain of `N` bytes | `N + 5` bytes | `N + 65` bytes |

The full header includes the 56-byte digest text and both 2-byte `CRLF` delimiters.

## Trojan Request Fields

Trojan reuses the SOCKS5 command and address encodings, but omits the SOCKS5
version and reserved fields:

```text
+-----+------+----------+----------+
| CMD | ATYP | DST.ADDR | DST.PORT |
+-----+------+----------+----------+
|  1  |  1   | Variable |    2     |
+-----+------+----------+----------+
```

`CMD` is one byte:

| Value | Meaning |
| --- | --- |
| `0x01` | `CONNECT`: open a TCP connection to the destination |
| `0x03` | `UDP ASSOCIATE`: carry UDP datagrams as frames in this stream |

`ATYP` and `DST.ADDR` use these encodings:

| ATYP | Address | Encoded `DST.ADDR` |
| --- | --- | --- |
| `0x01` | IPv4 | exactly 4 address bytes |
| `0x03` | domain name | 1-byte length `N`, followed by `N` domain bytes |
| `0x04` | IPv6 | exactly 16 address bytes |

`DST.PORT` is an unsigned 16-bit integer in network byte order (big-endian). The
one-byte domain length allows at most 255 bytes on the wire. The current
Chimera server rejects empty domain names and domain bytes that are not valid
UTF-8.

## TCP Relay and Responses

Once a `CONNECT` request is accepted, Trojan adds no further framing to the TCP data:

```text
client application bytes
        -> Trojan client -> outer transport -> Trojan server -> destination TCP socket
        <-                  raw bidirectional bytes                         <-
```

Trojan defines no method-selection response, authentication-status response,
SOCKS5-style `REP` reply, or portable error frame. A client observes success
when the tunnel becomes usable; failures before or during relay are represented
by TLS/I/O failure, connection closure, fallback handling, or
implementation-specific behavior.

A plain Trojan connection carries one `CONNECT` tunnel or one UDP association.
Multiplexing or additional framing supplied by a product is outside the base
Trojan request format.

## UDP Associate Framing

For `UDP ASSOCIATE`, each datagram is encoded in the same stream as:

```text
+------+----------+----------+--------+---------+---------+
| ATYP | DST.ADDR | DST.PORT | Length |  CRLF   | Payload |
+------+----------+----------+--------+---------+---------+
|  1   | Variable |    2     |   2    |    2    | Variable|
+------+----------+----------+--------+---------+---------+
```

- Address fields use the same encoding as the initial request.
- `Length` is an unsigned 16-bit payload length in network byte order.
- `Payload` contains exactly `Length` bytes.
- Frames are bidirectional: client-to-server frames identify the destination;
  server-to-client frames identify the datagram source.
- Trojan UDP frames have no SOCKS5 `RSV` or `FRAG` field and define no native
  fragmentation or reassembly.

The frame header before the payload is 11 bytes for IPv4, 23 bytes for IPv6,
and `N + 8` bytes for a domain name of length `N`. Although the wire length can
represent up to 65535 bytes, the current Chimera server limits Trojan UDP
payloads to 8192 bytes in both directions. This is an implementation limit,
not a Trojan wire-format limit.

UDP datagrams carried over a TCP/TLS stream inherit TCP head-of-line blocking:
loss or retransmission on the stream can delay later datagrams.

## Parsing and Failure Behavior

Implementations should read complete fields from the stream and validate the
command, address type, address length, port, `CRLF` delimiters, and declared
UDP payload length before dispatch. A malformed or truncated UDP frame loses
framing synchronization; the association should fail rather than guess where
the next frame begins.

The base protocol has no close command. The TLS/TCP connection lifetime bounds
the relay, and an I/O or parse failure ends the affected connection. In
Chimera Server, configured fallback handling can receive traffic that fails
before a valid password line is accepted; after a valid digest line, malformed
commands or addresses are rejected rather than sent to fallback.

## Security Notes

- `hex(SHA224(password))` is a deterministic wire credential, not a
  password-hardening KDF. Use unique, high-entropy passwords.
- When TLS is enabled, passive observers without session keys cannot read the
  digest, command, destination, UDP lengths, or payload. Endpoint addresses,
  timing, sizes, and some handshake metadata may remain visible.
- Fallback destinations should be controlled carefully; routing unauthenticated
  traffic to sensitive internal services can expose them to probes.
- Parsers should bound input before allocating buffers and reject malformed
  lengths and addresses. Authentication comparisons should avoid data-dependent
  early exits.

## Implementation References

The current Chimera implementations used to cross-check this page are:

- Client request construction: `Chimera_Client/clash-lib/src/proxy/trojan/mod.rs`.
- Client UDP framing: `Chimera_Client/clash-lib/src/proxy/trojan/datagram.rs`.
- Server authentication and request parsing:
  `Chimera_Server/chimera_server_lib/src/handler/trojan.rs`.
- Server UDP framing:
  `Chimera_Server/chimera_server_lib/src/handler/trojan_udp.rs`.

These implementation notes describe current project behavior and are not
additional protocol requirements.

## References

- Trojan protocol: <https://trojan-gfw.github.io/trojan/protocol.html>
- SOCKS Protocol Version 5 (RFC 1928): <https://datatracker.ietf.org/doc/html/rfc1928>
- Username/Password Authentication for SOCKS V5 (RFC 1929):
  <https://datatracker.ietf.org/doc/html/rfc1929>
