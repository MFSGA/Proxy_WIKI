# Trojan Wire Format

This chapter describes the byte stream seen by a Trojan implementation after the outer transport is established. The normative protocol shape comes from the Trojan specification; implementation-specific limits are called out separately.

### TLS Handshake
- The client first opens a TCP connection to the Trojan server and performs a normal TLS handshake.
- The client is responsible for validating the server certificate and hostname unless certificate verification has been deliberately disabled.
- If the TLS handshake fails, the connection terminates before any Trojan request is exchanged.
- TLS records are **transport framing, not Trojan message framing**. A Trojan header may be split across several TLS records, and a TLS record may contain the end of the header plus application payload. Parsers must therefore consume the decrypted TLS connection as an ordered byte stream rather than assume one `read()` equals one protocol message.

### Initial Request
After TLS is established, the client sends:

```text
+-----------------------+---------+----------------+---------+----------+
| hex(SHA224(password)) |  CRLF   | Trojan Request |  CRLF   | Payload  |
+-----------------------+---------+----------------+---------+----------+
|          56           | 0x0D0A  |    Variable    | 0x0D0A  | Variable |
+-----------------------+---------+----------------+---------+----------+
```

The authentication field is 56 ASCII hexadecimal characters representing the 28-byte SHA-224 digest of the configured password. The current Chimera client emits lowercase hexadecimal. It is immediately followed by `CRLF`; there is no separate authentication negotiation or success packet.

The optional `Payload` is only meaningful after the request header has been accepted. For `CONNECT`, it is the first bytes for the destination TCP stream. Sending it together with the header is an optimization, not a different protocol state.

For a request with no initial payload, the encoded header sizes are:

| Destination type | Trojan Request size | Full initial header size |
| --- | ---: | ---: |
| IPv4 | 8 bytes | 68 bytes |
| IPv6 | 20 bytes | 80 bytes |
| Domain of `N` bytes | `N + 5` bytes | `N + 65` bytes |

The full size includes the 56-byte password digest text and both `CRLF` delimiters.

### Trojan Request
Trojan Request deliberately keeps the SOCKS5 command and address vocabulary while removing the SOCKS5 version and reserved fields:

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
| `0x01` | `CONNECT`: establish a TCP connection to the destination |
| `0x03` | `UDP ASSOCIATE`: carry UDP datagrams as frames inside this Trojan stream |

`ATYP` and `DST.ADDR` use the SOCKS5 address encoding:

| ATYP | Address | Encoded `DST.ADDR` |
| --- | --- | --- |
| `0x01` | IPv4 | exactly 4 address bytes |
| `0x03` | domain name | 1-byte length `N`, followed by `N` domain bytes |
| `0x04` | IPv6 | exactly 16 address bytes |

`DST.PORT` is an unsigned 16-bit port in network byte order (big-endian). A domain length is therefore limited by the one-byte length field to at most 255 bytes on the wire.

The request is terminated by another `CRLF`. A receiver must not treat bytes after this delimiter as more request fields: they are either TCP payload (`CONNECT`) or the start of the UDP frame stream (`UDP ASSOCIATE`).

### Full Client/Server Exchange
A normal connection can be modeled as the following sequence:

1. **TCP connect.** The client creates a TCP connection to the Trojan endpoint.
2. **TLS handshake.** Client and server negotiate TLS; the client normally verifies the server identity.
3. **Authentication and command.** The client writes the 56-byte digest text, `CRLF`, `CMD`, encoded destination, and the terminating `CRLF`. For `CONNECT`, first application bytes may follow immediately.
4. **Authentication check.** The server reads the digest line and compares it with configured users. In the current Chimera server this comparison is constant-time.
5. **Command/address parse.** The server validates `CMD`, `ATYP`, address bytes, port, and the terminating `CRLF`.
6. **Branch by command.** `CONNECT` causes an outbound TCP connect; `UDP ASSOCIATE` enters the UDP frame loop.
7. **Relay.** TCP bytes are copied bidirectionally, or UDP frames are decoded/encoded repeatedly on the same TLS stream.
8. **Close.** EOF, TLS/TCP failure, an unrecoverable parse error, or policy failure terminates the relay. Invalid initial traffic may instead enter a configured fallback path.

A notable property is the absence of a Trojan-level success response. Once a `CONNECT` request succeeds, the first bytes received from the server side are destination application bytes, not a `REP` packet. This differs materially from SOCKS5.

### Server Responses: What Is Not on the Wire
Trojan does **not** define equivalents of several SOCKS5 server messages:

- no method-selection response;
- no RFC 1929 authentication-status response;
- no `VER | REP | RSV | BND.ADDR | BND.PORT` command reply;
- no structured Trojan error code corresponding to SOCKS5 `REP` values such as network unreachable or connection refused.

Consequently, a client generally observes success by the tunnel becoming usable. A failure before relay is represented by connection termination, TLS failure, implementation-specific behavior, or fallback handling rather than a portable Trojan error frame.

The current Chimera server follows this model: its Trojan `CONNECT` path returns no protocol-level connection-success bytes before forwarding destination data.

### TCP Relay
After a successful `CONNECT`, the Trojan layer adds no further framing:

```text
client application bytes
        ↓
Trojan client → TLS/TCP → Trojan server → destination TCP socket
        ↑                                      ↓
        └──────────── raw bidirectional bytes ─┘
```

There is no Trojan-native stream identifier, sequence number, fragment header, multiplexing frame, window-update command, or per-message acknowledgement. Ordering, retransmission, congestion control, and transport backpressure are supplied by the underlying TCP connection; confidentiality and integrity are supplied by TLS.

A plain Trojan connection therefore represents one `CONNECT` tunnel or one UDP association. Multiplexing, WebSocket wrapping, or another transport layer may be added by particular products, but those are additional layers rather than fields in the base Trojan protocol.

### UDP Associate Framing
When `CMD` is `UDP ASSOCIATE`, each UDP datagram is serialized in the TLS stream as:

```text
+------+----------+----------+--------+---------+----------+
| ATYP | DST.ADDR | DST.PORT | Length |  CRLF   | Payload  |
+------+----------+----------+--------+---------+----------+
|  1   | Variable |    2     |   2    | 0x0D0A  | Variable |
+------+----------+----------+--------+---------+----------+
```

- The address encoding is identical to the request address encoding above.
- `Length` is the UDP payload length as an unsigned 16-bit value in network byte order.
- `Payload` is exactly `Length` bytes of UDP payload.
- Frames are bidirectional. Client-to-server frames name the destination endpoint; server-to-client frames carry the endpoint associated with the received UDP datagram.
- There is no SOCKS5 `RSV` or `FRAG` field and no Trojan-native fragmentation/reassembly mechanism.

Header overhead before each UDP payload is 11 bytes for IPv4, 23 bytes for IPv6, and `N + 8` bytes for an `N`-byte domain name.

Although `Length` can represent values through 65535, implementation limits may be smaller. The current Chimera server rejects Trojan UDP payloads larger than 8192 bytes in either direction. This is a **Chimera implementation limit**, not a new field in the Trojan protocol.

Because these UDP frames are serialized over a reliable TCP/TLS byte stream, packet loss at the TCP layer can delay later UDP frames behind retransmission. This head-of-line behavior is fundamentally different from SOCKS5 UDP relay, where application datagrams normally travel over UDP after the association is established.

### State Machines
A useful client-side state machine is:

```text
TCP_CONNECT
    │ success
    ▼
TLS_HANDSHAKE
    │ success
    ▼
SEND_AUTH_AND_REQUEST
    ├── CMD=0x01 ──► TCP_RELAY ──────┐
    └── CMD=0x03 ──► UDP_FRAME_RELAY ─┤
                                      ▼
                                   CLOSING
                                      │
                                      ▼
                                    CLOSED
```

A server-side state machine is:

```text
ACCEPT_TCP
    ▼
TLS_HANDSHAKE
    ▼
READ_PASSWORD_LINE
    ▼
AUTH_CHECK
    ├── invalid ──► FALLBACK (if configured) / CLOSE
    ▼ valid
READ_CMD_ADDRESS_AND_CRLF
    ├── malformed/unsupported ──► ERROR / CLOSE
    ├── CONNECT ────────────────► CONNECT_UPSTREAM ─► TCP_RELAY
    └── UDP ASSOCIATE ─────────► UDP_FRAME_RELAY
                                              │
                       EOF / I/O error / parse error
                                              ▼
                                            CLOSED
```

The exact fallback transition is implementation-dependent. The official Trojan design treats invalid initial Trojan traffic as another protocol so it can be forwarded to a normal service; an implementation may impose stricter parsing or close on errors that occur after it has already committed to Trojan processing.

### SOCKS5 Stage-by-Stage Mapping
The closest comparison is standard SOCKS5 from RFC 1928, with RFC 1929 as the common username/password authentication method:

| Stage | SOCKS5 (RFC 1928/1929) | Trojan | Relationship |
| --- | --- | --- | --- |
| Transport connection | TCP connection to the SOCKS server | TCP connection followed by TLS | **Extra layer:** Trojan adds TLS before proxy protocol bytes |
| Method negotiation | `VER, NMETHODS, METHODS` → `VER, METHOD` | none | **Removed:** Trojan has no method-selection phase |
| Authentication | Optional method-specific subnegotiation; RFC 1929 sends username/password and receives `STATUS` | fixed 56-byte `hex(SHA224(password))` prefix + `CRLF`; no auth reply | **Replaced** |
| Proxy request | `VER, CMD, RSV, ATYP, DST.ADDR, DST.PORT` | `CMD, ATYP, DST.ADDR, DST.PORT` | **Same concepts, reduced header:** `VER` and `RSV` disappear |
| Address types | IPv4, domain with one-byte length, IPv6 | same encodings and ATYP values | **Same concept and wire encoding** |
| Command success/failure | Server sends `REP` and `BND.ADDR/BND.PORT` | no standardized command reply | **Removed/replaced by tunnel outcome** |
| TCP forwarding | raw application stream after successful reply | raw application stream after accepted request, protected by TLS | **Same relay concept + TLS outer layer** |
| UDP association setup | TCP control request returns a UDP relay address | same TLS/TCP connection becomes a UDP frame stream | **Replaced transport model** |
| UDP packet header | `RSV(2), FRAG, ATYP, DST.ADDR, DST.PORT, DATA` | `ATYP, DST.ADDR, DST.PORT, Length, CRLF, Payload` | **Replaced framing:** no `RSV`/`FRAG`; adds explicit length + delimiter |
| Fragmentation | RFC 1928 defines `FRAG` semantics | no Trojan-native fragmentation field | **Removed** |
| Multiplexing / flow control | not provided by base SOCKS5 | not provided by base Trojan | **Same absence at proxy layer;** Trojan inherits TCP flow/congestion behavior |
| Error reporting | structured `REP` values | close, TLS/I/O failure, fallback, or implementation-specific behavior | **Replaced** |

The important implementation lesson is that “SOCKS5-like” applies to Trojan's **command and address encoding**, not to the complete SOCKS5 session state machine.

### Packet-Capture View
Without TLS session keys, a packet capture normally exposes only the outer layers:

1. TCP three-way handshake to the Trojan server.
2. TLS `ClientHello` and the rest of the TLS handshake. Depending on TLS version and configuration, metadata such as SNI or ALPN may be observable.
3. Encrypted TLS application-data records in both directions.
4. TCP FIN/RST or TLS close behavior when the connection ends.

The Trojan password digest, command, destination address, UDP lengths, and proxied payload are inside TLS and are not visible as plaintext to a passive capture that cannot decrypt the session.

With TLS keys, a debugging TLS terminator, or instrumentation immediately above TLS, the first decrypted client bytes have a recognizable layout:

```text
<56 ASCII hex bytes> 0d 0a <cmd> <atyp> <address...> <port-be> 0d 0a [payload...]
```

For `CONNECT`, all following plaintext bytes belong to the destination byte stream. For `UDP ASSOCIATE`, the parser repeatedly returns to `ATYP` and decodes address → port → length → `CRLF` → payload.

Do not infer protocol-message boundaries from TCP segments or TLS records. Segmentation, coalescing, retransmission, and buffering can make the same logical Trojan header appear in many different packet layouts.

### Boundary Conditions and Current Chimera Behavior
The following checks are especially useful when implementing or reviewing a parser:

| Condition | Wire meaning | Current Chimera behavior |
| --- | --- | --- |
| Authentication field | 56 hexadecimal ASCII bytes before `CRLF` | Server hashes configured passwords with SHA-224, expects a 56-byte hex digest, and uses constant-time comparison; password-line parsing is bounded |
| Unsupported `CMD` | Not a valid base Trojan command | rejected; only `0x01` and `0x03` are accepted |
| Unknown `ATYP` | Address cannot be decoded | rejected |
| Domain length `0` | Empty domain encoding | server rejects it |
| Domain bytes | Length-prefixed opaque field in SOCKS-style encoding | current server/client parsers require valid UTF-8 when converting to their domain type |
| Port | 2-byte unsigned integer | decoded as big-endian/network byte order |
| Missing/bad request `CRLF` | Header terminator invalid | rejected |
| UDP `Length` | 2-byte unsigned integer | current server additionally limits payload to 8192 bytes |
| Bad UDP frame `CRLF` | Frame boundary invalid | UDP relay parser terminates/errors |
| Header split across reads | Normal stream behavior | parser must continue reading until each required field is complete |

When documenting interoperability, distinguish constraints imposed by the official wire format from limits imposed by one implementation. For example, the 8192-byte UDP limit is present in `Chimera_Server`, while the on-wire `Length` field itself is 16 bits.

### Connection Closure and Error Handling
Base Trojan has no dedicated close command. The lifetime is the lifetime of the TLS/TCP stream:

- a clean EOF from either side ends the corresponding relay direction and eventually the connection;
- TLS alerts, TCP reset, upstream connect errors, or local I/O errors terminate the tunnel;
- malformed authentication/request data cannot be reported with a portable Trojan error frame because no such frame is defined;
- invalid initial traffic may be sent to a configured fallback service, preserving the appearance of an ordinary TLS endpoint;
- a malformed UDP frame causes loss of framing synchronization, so implementations should fail the association rather than guess at the next boundary.

Half-close behavior is ultimately transport/implementation dependent. Implementations should preserve TCP EOF semantics where practical and avoid interpreting an ordinary application EOF as a Trojan command.

### Security Notes
- The SHA-224 value is a deterministic password-derived identifier, **not a password-hardening KDF**. Use high-entropy, unique Trojan passwords; do not rely on SHA-224 alone to make weak passwords resistant to offline guessing if a digest is disclosed.
- TLS is the confidentiality and integrity boundary for the Trojan header and payload. Certificate/hostname verification on the client is therefore security-critical unless trust is established by another explicit mechanism.
- Base Trojan defines no additional per-request nonce or anti-replay field; replay protection and channel freshness come from the TLS session rather than the Trojan header.
- TLS hides Trojan fields but does not automatically hide all traffic metadata. Endpoint IPs, timing, sizes, and some handshake metadata can remain observable.
- Fallback destinations should be intentionally controlled. Pointing fallback traffic at sensitive internal or administrative services can turn probing behavior into unwanted access to those services.
- Parsers should bound line lengths and UDP frame lengths before allocating buffers, reject impossible address lengths early, and compare credentials without data-dependent early exits.

### Implementation Notes
The current Chimera implementations used to cross-check this chapter are:

- client request construction: `Chimera_Client/clash-lib/src/proxy/trojan/mod.rs`;
- client UDP frame encoder/decoder and read state machine: `Chimera_Client/clash-lib/src/proxy/trojan/datagram.rs`;
- server authentication/request parser: `Chimera_Server/chimera_server_lib/src/handler/trojan.rs`;
- server UDP frame parser/encoder: `Chimera_Server/chimera_server_lib/src/handler/trojan_udp.rs`.

These implementation notes describe current project behavior and should not be mistaken for additional normative Trojan fields.

### References
- Trojan protocol specification: https://trojan-gfw.github.io/trojan/protocol.html
- SOCKS Protocol Version 5 (RFC 1928): https://datatracker.ietf.org/doc/html/rfc1928
- Username/Password Authentication for SOCKS V5 (RFC 1929): https://datatracker.ietf.org/doc/html/rfc1929
