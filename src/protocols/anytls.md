# AnyTLS

AnyTLS is a TLS-carried proxy protocol with its own authentication prefix and framed stream commands. It is not “arbitrary traffic inside TLS”: after the TLS handshake, the peer still has to authenticate, negotiate protocol metadata, open a logical stream, provide a destination, and exchange framed payloads.

This chapter documents the current AnyTLS wire behavior implemented by `Chimera_Client`. The current `Chimera_Server` protocol enum does not contain an AnyTLS inbound, so Client-side AnyTLS interoperability should be evaluated against a compatible AnyTLS server implementation rather than inferred from Chimera Server support.

## Position in the Stack

```text
Application
   │
   ▼
SOCKS / HTTP / TUN                 local ingress, optional
   │
   ▼
TCP connection to AnyTLS server
   │
   ▼
TLS handshake                      mandatory in normal deployments
   │
   ▼
AnyTLS authentication + frames
   │
   ▼
TCP target or UDP-over-TCP v2
```

The TLS layer provides transport confidentiality and server authentication when certificate verification is enabled. The AnyTLS password hash is a separate protocol authentication layer inside the established TLS application-data stream.

## Current Chimera Connection Sequence

The current outbound path performs these stages:

```text
TCP_CONNECT
   |
   v
TLS_HANDSHAKE
   |
   v
SEND SHA256(password)        32 bytes
   |
   v
SEND padding_len             u16 BE
   |
   v
SEND SETTINGS frame
   |
   v
SEND SYN frame
   |
   v
SEND PSH(destination) frame
   |
   v
RELAY PSH / FIN / ALERT
```

The implementation deliberately builds the initial AnyTLS authentication bytes and first frames into one write so compatible servers that expect the first TLS application-data record as one authentication packet do not observe an incomplete password/padding structure.

## Authentication Prefix

Immediately after TLS, the current Chimera client writes:

```text
+----------------------------------+
| SHA256(password)                 | 32 bytes
+----------------------------------+
| padding_len                      | u16 BE
+----------------------------------+
| padding                          | padding_len bytes
+----------------------------------+
| AnyTLS frames ...                |
+----------------------------------+
```

The current outbound advertises no initial padding, so `padding_len = 0`.

The inbound implementation builds an O(1) lookup map from `SHA256(password)` to the configured user identity. In multi-user mode the hash selects the user; in single-password fallback mode the user identity is empty.

This is not RFC 1929 username/password authentication. The password itself is not sent directly; the fixed 32-byte SHA-256 digest is the lookup/authentication token inside TLS.

## Authentication Failure and Fallback

The current Client inbound can be configured with a fallback backend. If the 32-byte password hash is unknown:

1. the AnyTLS parser stops;
2. the already consumed 32 bytes are prepended back into the decrypted TLS application stream;
3. the remaining decrypted stream is bidirectionally proxied to the fallback backend;
4. the inbound sends a TLS `close_notify` on clean shutdown where possible.

Without a fallback, the connection is rejected.

This fallback occurs **after TLS termination** in the current implementation. It is therefore different from a raw TCP fallback that forwards the original encrypted ClientHello/application records untouched.

## Initial Padding Field

After the 32-byte hash, the server reads a 2-byte big-endian padding length and skips exactly that many bytes.

```text
padding_len:u16 | padding[padding_len]
```

Malformed/truncated padding terminates the handshake. The current outbound sends zero bytes here even though later protocol metadata can advertise a padding scheme.

## Frame Format

Every AnyTLS frame in the current implementation uses this header:

```text
+---------+------------------+------------------+-------------------+
| CMD     | Stream ID        | Data Length      | Data              |
| u8      | u32 big-endian   | u16 big-endian   | DataLen bytes     |
+---------+------------------+------------------+-------------------+
   1 B          4 B                2 B              0..65535 B
```

The fixed frame header is therefore 7 bytes. A single frame payload cannot exceed 65535 bytes.

## Command Values

The current implementation recognizes these command numbers:

| Command | Value | Current meaning |
| --- | ---: | --- |
| `WASTE` | `0` | Padding/noise frame; ignored by the current inbound handshake parser. |
| `SYN` | `1` | Opens/selects a logical stream ID. |
| `PSH` | `2` | Carries destination bytes during setup and application bytes during relay. |
| `FIN` | `3` | Ends the logical stream. |
| `SETTINGS` | `4` | Client metadata/settings. |
| `ALERT` | `5` | Error/alert text from peer. |
| `UPDATE_PADDING_SCHEME` | `6` | Padding-scheme update; current outbound reads and discards it. |
| `SERVER_SETTINGS` | `10` | Server settings; current outbound reads and discards it. |

Unknown commands are ignored by the current outbound receive loop after a valid stream is established.

## SETTINGS Frame

The current Chimera client sends a `SETTINGS` frame on stream ID `0`. Its payload is UTF-8 metadata with the current shape:

```text
v=2
client=clash-rs/<package-version>
padding-md5=47edb1f4ed8a99480bf416d178311f10
```

The advertised MD5 corresponds to the current fixed client padding scheme `stop=0`, meaning Chimera does not actively add AnyTLS protocol padding to data packets in this implementation.

The current inbound accepts `SETTINGS` during the handshake but does not use its metadata for routing/authentication.

## Opening the Logical Stream

The current outbound uses one fixed logical stream ID:

```text
STREAM_ID = 1
```

It sends:

```text
SYN(stream=1, data="")
PSH(stream=1, data=SocksAddr(destination))
```

The inbound enforces ordering and identity:

- a `SYN` must arrive before the destination `PSH`;
- repeated `SYN` is tolerated only for the same stream ID;
- the destination `PSH` must use the selected stream ID;
- early `FIN` or `ALERT` aborts the handshake;
- malformed destination bytes abort the handshake.

Although the wire header contains a 32-bit stream ID and the protocol is structurally multiplexable, **the current Chimera outbound creates one logical AnyTLS stream with ID 1 per underlying connection**. Do not document current Chimera as performing multi-stream multiplexing merely because the field exists.

## Destination Encoding

The destination carried in the first `PSH` uses `SocksAddr`, the same address tuple used by other Clash-family protocol implementations.

Conceptually:

| Type | Value | Encoding |
| --- | ---: | --- |
| IPv4 | `0x01` | IPv4 bytes + port |
| Domain | `0x03` | length + domain bytes + port |
| IPv6 | `0x04` | IPv6 bytes + port |

The address bytes are payload of an AnyTLS `PSH`; there is no SOCKS5 `VER/CMD/RSV` envelope around them.

## TCP Data Relay

After the initial destination has been accepted, application bytes are transformed into `PSH` frames:

```text
application write
     |
     v
CMD=PSH | stream=1 | len | payload
     |
     v
TLS application data
```

The current relay reads up to 16 KiB from its local in-process pipe for each generated `PSH`. This is an implementation buffering choice, not a protocol maximum; the frame format itself permits up to 65535 bytes.

Inbound response `PSH` data for the selected stream is written back to the application-facing stream.

## FIN and Half-close Behavior

When the application-facing write side reaches EOF, the outbound sends:

```text
FIN(stream=1, len=0)
```

and flushes the TLS stream.

When a matching inbound `FIN` is received, the current outbound shuts down the application-facing read side and cancels the relay tasks.

The current implementation therefore treats `FIN` as logical-stream termination rather than supporting a long independent multiplexed connection containing other active stream IDs.

## ALERT Handling

A peer `ALERT` frame is interpreted as UTF-8/lossy text for logging. The current outbound then shuts down the relay and cancels the connection tasks.

There is no SOCKS-style numeric result mapping. An AnyTLS alert is an AnyTLS-layer failure; a local SOCKS inbound may translate the resulting connection failure into its own SOCKS response for the local application.

## Handshake Timeout

The current AnyTLS inbound allows 10 seconds for the TLS + password + padding + `SYN/PSH(destination)` handshake sequence.

A timeout closes the connection without dispatching a target session.

This timeout is a current Chimera implementation policy, not a field encoded into the AnyTLS wire format.

## UDP over TCP v2

The current AnyTLS UDP implementation does not send native UDP packets to the AnyTLS server. It creates a normal AnyTLS stream whose apparent destination is a reserved magic hostname:

```text
sp.v2.udp-over-tcp.arpa:0
```

After that AnyTLS stream is established, it sends the UoT v2 connect header:

```text
+------------------+-----------------------+
| isConnect        | real UDP destination  |
| u8 = 1           | SocksAddr             |
+------------------+-----------------------+
```

All of those bytes are still carried inside AnyTLS `PSH` frames.

## UoT Datagram Framing

After the UoT connect header, each UDP payload is framed as:

```text
+------------------+-----------------------+
| payload length   | UDP payload           |
| u16 big-endian   | length bytes          |
+------------------+-----------------------+
```

The selected destination is established once by the UoT connect header. Individual datagrams therefore do not repeat a SOCKS address header in the current connect-mode session.

The same 2-byte length-prefix form is used for responses delivered back through the stream.

## UDP Session State

The current outbound creates one stream-backed datagram object tied to the requested UDP destination. The inbound recognizes the magic hostname, unwraps AnyTLS `PSH` frames into a byte stream, parses `isConnect=1` and the real destination, and dispatches that stream as a UDP session.

This is UDP tunneling over an ordered TCP/TLS stream. Consequences include:

- UDP datagrams inherit TCP ordering;
- loss of one underlying TCP segment can delay later datagrams (head-of-line blocking);
- there is no native QUIC-style independent datagram delivery;
- MTU behavior is transformed into stream framing rather than preserved as original IP/UDP packet boundaries.

## Current Inbound State Machine

```text
TCP_ACCEPTED
    |
    v
TLS_HANDSHAKE
    |
    v
READ_PASSWORD_HASH(32)
    |
    +-- unknown --> FALLBACK or CLOSE
    |
    v
READ_PADDING_LEN + SKIP_PADDING
    |
    v
READ SETTINGS/WASTE/SYN...
    |
    v
REQUIRE SYN(stream=N)
    |
    v
REQUIRE PSH(stream=N, destination)
    |
    +-- magic UoT host --> READ UOT CONNECT --> UDP DISPATCH
    |
    +-- normal target --> TCP DISPATCH
    |
    v
RELAY PSH / FIN
```

The transport can therefore fail at several distinct layers: TCP reachability, TLS authentication, AnyTLS password authentication, frame ordering, destination parsing, or target connection.

## Packet-capture View

Without TLS session keys, a normal capture exposes:

```text
TCP 3-way handshake
TLS ClientHello / ServerHello / encrypted handshake
TLS Application Data
TLS Application Data
...
TCP FIN/RST or TLS close_notify
```

The SHA-256 password token, stream IDs, destination, UoT magic host, and frame boundaries are inside TLS application data and are not visible to a passive observer under a correctly functioning TLS session.

With TLS keys or an in-process trace, the first application bytes can be decoded as:

```text
32B password hash
00 00                         padding_len=0
04 00 00 00 00 <len> ...     SETTINGS, stream 0
01 00 00 00 01 00 00         SYN, stream 1, len 0
02 00 00 00 01 <len> <addr>  PSH, stream 1, destination
```

This is a useful parser sanity check when interoperability fails immediately after a successful TLS handshake.

## Current TLS Configuration Surface

The current AnyTLS outbound configuration includes:

- `password`;
- `alpn`;
- `sni`;
- `skip-cert-verify`;
- `udp`;
- optional client certificate/key for mTLS.

The client certificate and key must be provided together.

Certificate verification should remain enabled in normal deployments. Disabling it removes the normal TLS server-identity check and leaves the AnyTLS password as the main remote authentication secret.

## Parsed-only Configuration Fields

Several current `Chimera_Client` AnyTLS fields are explicitly annotated as parsed for configuration compatibility but not applied by the runtime:

- `fingerprint`;
- `client-fingerprint`;
- `idle-session-check-interval`;
- `idle-session-timeout`;
- `min-idle-session`.

These fields must be labeled **Parsed-only** in the Wiki. Their presence in YAML does not prove a behavior change in the current runtime.

## Current Chimera_Client Evidence

AnyTLS is behind the `anytls` Cargo feature. The current source contains:

- outbound TLS + AnyTLS handshake and framing;
- outbound TCP relay;
- outbound UDP-over-TCP v2;
- AnyTLS inbound TLS listener;
- multi-user SHA-256 password lookup;
- fallback handling;
- TCP and UDP inbound dispatch;
- integration tests for TCP and UDP.

Recent implementation work also retains UDP sessions until cancellation rather than allowing the stream-backed datagram session to disappear prematurely.

See [Implementation Status and Source Evidence](../implementation-status.md) for the cross-project evidence level.

## Chimera_Server Status

The current `Chimera_Server` protocol enum and handler tree do not contain an AnyTLS inbound implementation.

Therefore:

- `Chimera_Client → third-party AnyTLS server` can be a valid supported deployment;
- `Chimera_Client AnyTLS → Chimera_Server` is **not** a currently documented compatible pair;
- an AnyTLS page in this Wiki describes the Client implementation and protocol behavior, not an implicit Server capability.

## SOCKS5 Phase-by-phase Comparison

| Phase | SOCKS5 | AnyTLS | Relationship |
| --- | --- | --- | --- |
| Initial transport | TCP to SOCKS server | TCP then TLS to AnyTLS server | Extra TLS layer |
| Server authentication | Usually none at transport level | TLS certificate verification | Extra layer |
| Method negotiation | Client sends supported methods | None | Removed/replaced by configuration |
| User authentication | Optional RFC 1929 username/password | `SHA256(password)` token inside TLS | Replaced |
| Request command | `CONNECT/BIND/UDP ASSOCIATE` | `SYN` + `PSH(destination)`; UoT magic destination for UDP | Replaced |
| Destination address | SOCKS request fields | SocksAddr inside first `PSH` | Same concept, different framing |
| Success reply | SOCKS `REP` reply | No equivalent fixed result structure in current path | Removed |
| TCP data | Raw bytes after request | `PSH` frames inside TLS | Extra framing + TLS |
| TCP close | TCP half-close/close | `FIN` logical command plus TLS/TCP close | Extra logical close layer |
| UDP | Native UDP relay with SOCKS UDP header | UDP-over-TCP v2 stream | Replaced transport model |
| UDP destination | Repeated per SOCKS UDP datagram | Established once in UoT connect mode | Different session semantics |
| Fragmentation | SOCKS `FRAG` field | No SOCKS5-style `FRAG` | Removed |
| Multiplexing | One SOCKS TCP control connection per request in common use | Frame has stream ID, but current Chimera uses one stream ID per connection | Protocol has extra field; current implementation does not exploit full mux |
| Error reporting | Numeric SOCKS `REP` | TLS errors, auth rejection, `ALERT`, close/logging | Replaced |

## Security Notes

- TLS verification and AnyTLS password authentication protect different layers; do not treat one as a substitute for the other.
- The on-wire token is `SHA256(password)`. Choose a high-entropy password because a captured decrypted authentication token is deterministic for a given password.
- Keep `skip-cert-verify` disabled unless the trust consequences are understood.
- Fallback targets receive decrypted TLS application bytes after an unknown password; configure them intentionally and avoid exposing sensitive internal services.
- UDP-over-TCP can suffer head-of-line blocking and should not be described as equivalent to native UDP or QUIC datagrams.
- Parsed-only idle/fingerprint options should not be relied upon for timeout, fingerprinting, or resource-control guarantees.

## Troubleshooting

Debug AnyTLS from the outside inward:

1. verify TCP reachability to the server;
2. verify TLS SNI, certificate trust, ALPN, and optional mTLS material;
3. verify both sides use the same password and that the server expects the SHA-256 token form;
4. verify the first application packet contains the padding length and v2 `SETTINGS`/`SYN`/`PSH` sequence expected by the peer;
5. for TCP, verify the destination `SocksAddr` is accepted;
6. for UDP, verify `sp.v2.udp-over-tcp.arpa`, `isConnect=1`, the real destination, and 2-byte datagram lengths;
7. inspect `ALERT`, timeout, fallback, or target-connect logs before changing unrelated DNS/rule settings.

A successful TLS handshake only proves the TLS layer. It does not prove AnyTLS password authentication or frame compatibility.

## Source Anchors

Current Chimera implementation details in this chapter are grounded in:

- `Chimera_Client/clash-lib/src/proxy/anytls/mod.rs`;
- `Chimera_Client/clash-lib/src/proxy/anytls/datagram.rs`;
- `Chimera_Client/clash-lib/src/proxy/anytls/inbound/framing.rs`;
- `Chimera_Client/clash-lib/src/proxy/anytls/inbound/handler.rs`;
- `Chimera_Client/clash-lib/src/proxy/anytls/inbound/user.rs`;
- `Chimera_Client/clash-lib/src/proxy/anytls/inbound/tls.rs`;
- `Chimera_Client/clash-lib/src/config/internal/proxy.rs`;
- `Chimera_Client/clash-lib/tests/anytls_integration_tests.rs`.

For portable interoperability, verify the selected peer against the current AnyTLS protocol specification and implementation rather than assuming every AnyTLS implementation uses the same optional settings or multiplexing policy.
