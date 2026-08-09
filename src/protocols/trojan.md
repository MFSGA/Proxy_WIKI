# Trojan

## Positioning

Trojan is a TLS-based proxy protocol designed so that the outer connection uses
a normal TLS session while proxy authentication and destination metadata are
carried inside encrypted application data.

The original Trojan protocol uses a pre-shared password, represented on the wire
as the hexadecimal SHA-224 digest of that password. Its request address format
is similar to SOCKS5 and supports both TCP `CONNECT` and UDP association.

The baseline protocol described here should be distinguished from additional
transport combinations exposed by individual proxy cores, such as WebSocket,
XHTTP, or other wrappers.

## Connection Flow

1. The client opens a TCP connection to the Trojan server.
2. Client and server complete a normal TLS handshake.
3. Inside TLS application data, the client sends the password digest and Trojan
   request header.
4. The server validates the password and destination request.
5. For TCP, the server connects to the target and relays the stream.
6. For UDP, datagrams are framed inside the Trojan TLS stream.
7. Invalid traffic can be handled by a fallback service instead of exposing a
   proxy-specific response.

The detailed byte layout is documented in [Wire Format](./trojan/wire-format.md).
Fallback behavior is discussed in [Traffic Handling](./trojan/traffic-handling.md).

## Layer-by-Layer Exchange

The easiest way to understand Trojan is to separate the ordinary network layers
from the Trojan control message itself:

```text
client                                                    server
  |                                                          |
  |---------------- TCP three-way handshake ----------------->|
  |<---------------- TCP established -------------------------|
  |                                                          |
  |==================== TLS handshake ========================|
  | ClientHello (SNI/ALPN/...)                               |
  |<---------------- ServerHello / Certificate / Finished ----|
  |---------------- Finished -------------------------------->|
  |                                                          |
  | TLS application data:                                    |
  |   56-byte hex(SHA224(password))                           |
  |   CRLF                                                    |
  |   CMD + ATYP + DST.ADDR + DST.PORT                        |
  |   CRLF                                                    |
  |   optional first payload                                  |
  |---------------------------------------------------------->|
  |                                                          |
  |          server validates password + request              |
  |          server dials requested destination               |
  |                                                          |
  |<================ encrypted relay data ===================>|
```

This sequence is important when reading a packet capture. Before TLS is
decrypted, a passive capture shows the TCP and TLS handshakes but not the Trojan
password digest, destination address, command, or proxied application data.
Those fields are TLS application data.

## Initial Trojan Request Wire Format

After TLS has been established, the client sends one logical request:

```text
+-----------------------+------+----------------+------+----------+
| hex(SHA224(password)) | CRLF | Trojan Request | CRLF | Payload  |
+-----------------------+------+----------------+------+----------+
|          56           |  2   |    Variable    |  2   | Variable |
+-----------------------+------+----------------+------+----------+
```

The first field is 56 ASCII hexadecimal characters because SHA-224 produces
28 bytes and hexadecimal encoding uses two characters per byte. It is followed
by the two bytes `0x0d 0x0a`.

The Trojan request itself is:

```text
+-----+------+----------+----------+
| CMD | ATYP | DST.ADDR | DST.PORT |
+-----+------+----------+----------+
|  1  |  1   | Variable |    2     |
+-----+------+----------+----------+
```

Unlike a SOCKS5 request, there is no leading `VER` byte and no reserved `RSV`
byte. Authentication is also not negotiated with a method-selection exchange;
it has already been supplied as the password hash immediately before the
request.

### `CMD`

The baseline Trojan protocol defines:

| Value | Command | Meaning |
| --- | --- | --- |
| `0x01` | `CONNECT` | Open a TCP connection to the destination. |
| `0x03` | `UDP ASSOCIATE` | Enter Trojan's framed UDP relay mode. |

There is no Trojan equivalent of SOCKS5 `BIND` in the baseline protocol.

### `ATYP` and Destination Encoding

Trojan deliberately reuses the SOCKS5 address-type values:

| `ATYP` | Address form | Encoding |
| --- | --- | --- |
| `0x01` | IPv4 | Exactly 4 address bytes. |
| `0x03` | Domain name | One length byte, followed by that many domain-name bytes. |
| `0x04` | IPv6 | Exactly 16 address bytes. |

`DST.PORT` is two bytes in network byte order, the same convention used by
SOCKS5.

For example, a domain target conceptually becomes:

```text
03                     ATYP = DOMAIN
0b                     domain length = 11
65 78 61 6d 70 6c 65   "example"
2e 63 6f 6d            ".com"
01 bb                  port 443
```

The example is shown as logical bytes only; on the wire these bytes are inside
TLS application records.

## Authentication: Trojan versus SOCKS5

SOCKS5 separates method negotiation, optional authentication, and proxy command
selection. Trojan collapses those phases behind TLS:

```text
SOCKS5
TCP
 -> VER/NMETHODS/METHODS
 <- VER/METHOD
 -> optional RFC 1929 username/password
 <- authentication status
 -> CONNECT/UDP ASSOCIATE request
 <- structured REP reply
 -> relay data

Trojan
TCP
 -> TLS handshake
 -> password digest + CONNECT/UDP request + optional first payload
 -> relay data, or fallback/connection handling on invalid traffic
```

The consequences are significant:

- Trojan has no authentication-method negotiation byte sequence.
- Trojan has no username/password sub-negotiation equivalent to RFC 1929.
- Trojan authentication is protected by TLS before it is transmitted.
- The destination request can be coalesced with initial application payload.
- The baseline protocol does not define a SOCKS5-style `REP` response frame for
  a successful `CONNECT`.

The last point changes the client state machine: after sending a valid Trojan
request, the client normally proceeds by observing the resulting relay behavior
rather than waiting for a fixed `VER/REP/ATYP/BND.ADDR/BND.PORT` success frame.

## TCP `CONNECT` State Machine

A useful client-side state machine is:

```text
DISCONNECTED
   |
   | TCP connect
   v
TCP_CONNECTED
   |
   | TLS handshake + certificate validation
   v
TLS_ESTABLISHED
   |
   | send password digest + CONNECT request [+ first payload]
   v
REQUEST_SENT
   |
   | encrypted application bytes arrive / relay continues
   v
RELAYING
   |
   | TLS close_notify, TCP FIN/RST, timeout, or local close
   v
CLOSED
```

The server side can be modeled as:

```text
ACCEPT_TCP
   |
   v
TLS_HANDSHAKE
   |
   +---- TLS failure ---------------------------> CLOSE
   |
   v
READ_AUTH_AND_REQUEST
   |
   +---- invalid / unknown ---------------------> FALLBACK_OR_CLOSE
   |
   v
DIAL_DESTINATION
   |
   +---- dial failure --------------------------> implementation handling
   |
   v
BIDIRECTIONAL_RELAY
   |
   v
CLOSE
```

A robust implementation must not assume that one TLS read returns the complete
56-byte digest, both CRLF delimiters, the full variable-length address, and the
first payload. TLS records and the underlying TCP stream may split or coalesce
those bytes arbitrarily.

## First Payload and Read-Ahead

Trojan allows application payload to immediately follow the second CRLF. This
reduces an avoidable application-level round trip:

```text
TLS record payload (logical view)

[authentication][CRLF][CONNECT request][CRLF][first HTTP/TLS/etc. bytes]
```

A server parser therefore has an important boundary condition: bytes already
read beyond the end of the Trojan header are not parser garbage. They are the
first bytes destined for the requested upstream connection and must be retained
and forwarded in order.

This is analogous to the boundary after a successful SOCKS5 `CONNECT`, except
SOCKS5 normally has an explicit server reply before ordinary application data
begins.

## Trojan UDP Framing

For `CMD = 0x03`, the TLS connection becomes a stream carrying a sequence of
framed UDP datagrams:

```text
+------+----------+----------+--------+------+----------+
| ATYP | DST.ADDR | DST.PORT | Length | CRLF | Payload  |
+------+----------+----------+--------+------+----------+
|  1   | Variable |    2     |   2    |  2   | Variable |
+------+----------+----------+--------+------+----------+
```

`Length` is an unsigned two-byte payload length in network byte order. The
address fields identify the destination associated with that individual UDP
datagram.

The receiver must therefore parse the stream as repeated length-delimited
messages:

```text
READ_ATYP
  -> READ_ADDRESS
  -> READ_PORT
  -> READ_LENGTH
  -> EXPECT_CRLF
  -> READ_EXACTLY_LENGTH_BYTES
  -> DISPATCH_DATAGRAM
  -> READ_ATYP ...
```

TCP/TLS does not preserve UDP packet boundaries. The `Length` field is what
reconstructs each datagram boundary.

### UDP Fragmentation Difference from SOCKS5

SOCKS5's UDP request header includes `RSV` and a `FRAG` byte. Trojan's baseline
UDP framing does **not** carry the SOCKS5 `FRAG` field; instead it adds a
2-byte payload length plus CRLF because multiple datagrams are serialized into
one reliable TLS byte stream.

That gives a useful design comparison:

| Property | SOCKS5 UDP | Trojan UDP |
| --- | --- | --- |
| Underlying client-to-proxy transport | UDP datagrams | TLS over TCP byte stream |
| Datagram boundary | Native UDP packet | Explicit 2-byte `Length` |
| Address type | `ATYP` | Same `ATYP` values |
| Destination port | 2-byte network order | Same |
| Fragment field | `FRAG` exists | No baseline `FRAG` field |
| Control lifetime | TCP `UDP ASSOCIATE` connection | Trojan TLS connection |
| Loss semantics between client/proxy | UDP can lose/reorder | TCP retransmits/orders bytes |
| Head-of-line blocking | Not inherent to UDP relay | Possible because all frames share TCP ordering |

The final row is one of the most important architectural differences between
Trojan UDP and QUIC-datagram protocols such as Hysteria 2 and TUIC.

## SOCKS5 Phase-by-Phase Comparison

| Stage | SOCKS5 | Trojan | Relationship |
| --- | --- | --- | --- |
| Underlying connection | TCP | TCP then TLS | Trojan adds a security layer first. |
| Authentication selection | `VER/NMETHODS/METHODS` | None | Replaced by fixed Trojan credential model. |
| Authentication payload | Method-specific, e.g. RFC 1929 | 56-byte hex SHA-224 digest | Replaced and protected by TLS. |
| Proxy command | `VER/CMD/RSV/ATYP/...` | `CMD/ATYP/...` | Same core command idea, smaller header. |
| TCP command | `CONNECT = 0x01` | `CONNECT = 0x01` | Directly aligned. |
| UDP command | `UDP ASSOCIATE = 0x03` | `UDP ASSOCIATE = 0x03` | Directly aligned in command number. |
| BIND | `0x02` | Not in baseline Trojan | SOCKS5-only feature. |
| IPv4/domain/IPv6 | `ATYP 01/03/04` | `ATYP 01/03/04` | Directly reused. |
| Destination port | 2-byte network order | Same | Directly reused. |
| Success reply | Structured `REP` + bound address | No equivalent fixed success frame | Different state transition. |
| TCP payload | Raw after success reply | TLS-protected after request | TLS is an extra layer. |
| UDP packet header | `RSV/FRAG/ATYP/...` per UDP datagram | `ATYP/.../Length/CRLF/Payload` in TLS stream | Reframed for stream transport. |
| Confidentiality | None unless auth method adds it | TLS | Major Trojan addition. |
| Invalid client behavior | SOCKS failure reply | Fallback or close behavior | Trojan adds camouflage-oriented handling. |

This table is the baseline for comparing later protocols. Hysteria 2 and TUIC
retain the general ideas of authentication, destination metadata, TCP-like
streams, and UDP associations, but replace the SOCKS/Trojan TCP stream substrate
with QUIC streams and datagrams. VLESS similarly keeps destination dispatch as a
separate proxy-protocol concern while REALITY and XHTTP occupy different layers.

## Packet-Capture View

Without TLS session keys, a packet capture can usually establish:

1. DNS resolution for the Trojan server, if DNS is visible.
2. TCP connection establishment to the Trojan server.
3. TLS ClientHello metadata that is not encrypted by the negotiated TLS mode,
   such as observable handshake characteristics and commonly SNI in traditional
   TLS deployments.
4. TLS handshake success or failure.
5. Encrypted application-data records and their timing/size patterns.
6. TLS/TCP connection shutdown.

It cannot directly reveal the Trojan `CMD`, `ATYP`, destination address, password
digest, or application payload merely from the encrypted records.

With TLS key logging in a controlled development environment, the decrypted
logical sequence should line up with the request format above. Such key logging
must be treated as sensitive because it defeats the confidentiality being tested.

## Error and Closure Semantics

The baseline Trojan specification is much less reply-oriented than SOCKS5.
This means implementations need explicit local policies for conditions such as:

- TLS authentication/certificate failure,
- incomplete 56-byte password field,
- missing CRLF delimiter,
- unsupported `CMD`,
- invalid `ATYP`,
- truncated domain/IPv6 address,
- incomplete two-byte port,
- upstream dial failure,
- declared UDP `Length` larger than available buffered data,
- peer EOF in the middle of a UDP frame,
- idle timeout,
- TLS `close_notify`, TCP FIN, or TCP RST.

For malformed or unauthenticated requests, the deployment's fallback policy is
part of externally observable behavior. For already authenticated relay traffic,
normal stream shutdown should preserve half-close semantics where the runtime
and upstream socket APIs support them instead of converting every EOF into an
immediate reset.

## Minimal Deployment Model

A practical deployment needs at least:

- a TCP listening address and port,
- TLS certificate/key or another implementation-specific TLS termination path,
- one or more Trojan passwords,
- a fallback policy if camouflage behavior is desired,
- and routing rules for outbound traffic.

A conceptual client entry looks like:

```yaml
proxies:
  - name: trojan-example
    type: trojan
    server: proxy.example.com
    port: 443
    password: "CHANGE-ME"
    sni: proxy.example.com
```

Exact transport keys vary by selected core. If WebSocket or another transport
is enabled, both endpoints must use compatible transport settings.

## Authentication

The original protocol uses a shared secret. A server can assign different
passwords to different users, but credential lifecycle is still application
configuration rather than a negotiated identity system.

Operationally:

- use unique, high-entropy credentials,
- avoid reusing a password across unrelated servers,
- rotate credentials when a client is decommissioned,
- and do not expose credentials in logs or example configs.

## TLS Requirements

Trojan depends heavily on the quality of its TLS deployment. The certificate,
SNI behavior, ALPN configuration, and fallback endpoint should be internally
consistent.

For the original TLS-camouflage design, a valid and ordinary-looking HTTPS
configuration is preferable to an obviously synthetic endpoint.

## TCP and UDP

### TCP

TCP requests are straightforward after authentication: the server opens the
requested destination and relays bytes in both directions.

### UDP

UDP traffic is encapsulated in per-datagram Trojan framing carried over the TLS
stream. This differs from QUIC-native protocols such as Hysteria 2 and TUIC,
which can use QUIC datagrams.

## Strengths

- Uses mature TLS implementations for confidentiality and server identity.
- Small protocol-specific framing after TLS establishment.
- Supports both TCP and UDP relay in the baseline protocol.
- Invalid requests can be sent to a normal fallback service instead of a
  proxy-specific error page.
- Familiar certificate-based operations for administrators already running
  HTTPS services.

## Limitations

- Certificate issuance and renewal become part of server operations unless the
  selected stack provides another compatible security mechanism.
- Shared-secret authentication requires deliberate credential management.
- TLS camouflage is only as convincing as the surrounding TLS and fallback
  configuration.
- UDP is tunneled through the TLS/TCP-oriented connection model rather than
  using a native unreliable datagram transport.

## Security Notes

Do not disable certificate verification in production merely to make a test
configuration connect. A successful TCP connection with invalid TLS validation
is not equivalent to a secure deployment.

Fallbacks also need care. A fallback should not unintentionally expose private
services, administrative endpoints, or internal-only content.

## Chimera Status

### Chimera_Client

The current Wiki lists **Trojan + WebSocket** among the client-core capabilities.
Because the original Trojan protocol and an implementation-specific WebSocket
transport are separate layers, verify both the Trojan credentials and transport
options when troubleshooting.

### Chimera GUI

Chimera manages the selected core and profile. Trojan protocol behavior belongs
to that core rather than the GUI itself.

### Chimera_Server

The server capability map includes Trojan-related inbound parsing/handling.
Treat this as current implementation scope, not automatic compatibility with
every Trojan client or every optional transport combination.

## Troubleshooting

1. Confirm DNS resolves the intended server address.
2. Verify TCP reachability to the server port.
3. Validate certificate trust, SNI, and system time.
4. Check the Trojan password independently of transport-specific options.
5. If WebSocket is used, verify path/Host/header settings on both endpoints.
6. If authentication fails but HTTPS fallback works, inspect credential and
   Trojan request configuration rather than the TLS listener itself.
7. For UDP issues, first confirm TCP Trojan traffic works and then test UDP as a
   separate capability.

## References

- Trojan protocol documentation: <https://trojan-gfw.github.io/trojan/protocol.html>
