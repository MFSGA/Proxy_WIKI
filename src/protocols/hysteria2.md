# Hysteria 2

## Positioning

Hysteria 2 is a TCP and UDP proxy protocol built on QUIC. Its design combines
QUIC streams for reliable TCP-style proxying, QUIC datagrams for UDP relay, TLS
security from QUIC, and an HTTP/3-facing authentication path intended to make an
unauthenticated endpoint behave like an ordinary HTTP/3 service.

Hysteria 2 is especially relevant on paths where packet loss or high latency
makes conventional TCP-over-TCP-style designs perform poorly. It is not a
universal replacement for TCP-based protocols: the network must permit stable
UDP/QUIC traffic.

## Protocol Layers

A useful mental model is:

```text
Application TCP / UDP
        │
        ▼
Hysteria 2 proxy requests
        │
        ├── TCP: QUIC bidirectional streams
        └── UDP: QUIC datagrams
        │
        ▼
QUIC + TLS
        │
        ▼
UDP/IP
```

The protocol depends on standard QUIC and the QUIC unreliable datagram
extension. Authentication is performed through an HTTP/3 request before proxy
requests are accepted.

### QUIC substrate before Hysteria authentication

There are two different handshakes to keep separate when reading a trace or
implementing a client. First, QUIC establishes a connection over UDP and carries
a TLS 1.3 handshake in QUIC `CRYPTO` frames. The TLS/QUIC layer establishes the
server identity, traffic keys, QUIC transport parameters, and HTTP/3 (`h3`)
application protocol. Only after that protected transport exists does Hysteria
perform its own `/auth` exchange inside HTTP/3.

For standards-conforming QUIC DATAGRAM support, each endpoint advertises the
`max_datagram_frame_size` QUIC transport parameter (`0x20`) during the QUIC/TLS
handshake. The value is directional: it describes the largest DATAGRAM frame the
sender of the parameter is willing to receive. A value of zero, or absence of
the parameter, means DATAGRAM reception is not available under RFC 9221. An
endpoint must not send a DATAGRAM frame until its peer has advertised a non-zero
limit, and sending a DATAGRAM larger than the advertised limit is a QUIC
protocol violation.

This produces a layered state boundary that SOCKS5 does not have:

```text
UDP socket
  -> QUIC Initial / Handshake packets
  -> TLS authenticated + QUIC transport parameters known
  -> HTTP/3 available
  -> POST /auth
  -> :status 233
  -> Hysteria proxy streams / datagrams allowed
```

QUIC can support 0-RTT on resumed connections, but replay safety is an
application concern. A Hysteria implementation must not assume that an earlier
QUIC session ticket removes the Hysteria authentication boundary or makes a
side-effecting proxy request replay-safe. RFC 9221 permits DATAGRAM use in 0-RTT
only when the remembered peer limit is valid for the resumed connection.

## Connection and Authentication Flow

1. The client establishes a QUIC connection to the server.
2. QUIC performs its TLS-based cryptographic handshake.
3. The client sends the Hysteria authentication request through HTTP/3.
4. The server validates the supplied authentication value and communicates
   capabilities such as UDP support and receive-rate information.
5. Only after successful authentication does the connection become an active
   Hysteria proxy session.
6. TCP proxy requests use new bidirectional QUIC streams.
7. UDP packets use QUIC datagrams and Hysteria's UDP message framing.

The official protocol uses a dedicated success status for its authentication
exchange. Implementers should follow the current upstream specification rather
than hard-coding behavior from older Hysteria versions.

## Wire-Level State Machine

Hysteria 2 has two control transitions before proxy payload is accepted. QUIC/TLS first establishes a protected connection; an HTTP/3 authentication exchange then changes that connection from an ordinary HTTP/3 service into a Hysteria proxy session.

```text
Client                                      Server
  | UDP + QUIC/TLS handshake                  |
  |------------------------------------------->|
  |<-------------------------------------------|
  | HTTP/3 POST /auth                          |
  | Hysteria-Auth + Hysteria-CC-RX             |
  |------------------------------------------->|
  |<---------------------- :status 233 HyOK    |
  | === authenticated proxy connection ===    |
  | open QUIC bidi stream -> TCPRequest        |
  |------------------------------------------->|
  |<----------------------------- TCPResponse  |
  |<========== stream payload ================>|
  |<========= QUIC DATAGRAM UDPMessage =======>|
```

A server MUST NOT interpret proxy requests before HTTP/3 authentication succeeds. A client must treat any authentication status other than `233` as failure and disconnect. This boundary matters when the endpoint also serves real HTTP/3 content or reverse-proxy masquerading.

### Authentication request and response

```text
:method: POST
:path: /auth
:host: hysteria
Hysteria-Auth: <credential>
Hysteria-CC-RX: <uint bytes/second>
Hysteria-Padding: <optional random string>
```

`Hysteria-CC-RX` is transport feedback, not authentication material. `0` means the client does not know its receive rate. Padding is ignored semantically.

Success returns:

```text
:status: 233 HyOK
Hysteria-UDP: true | false
Hysteria-CC-RX: <uint> | auto
Hysteria-Padding: <optional random string>
```

Unlike SOCKS5, there is no separate one-byte method-selection exchange. Credential validation and transport capability negotiation are carried inside an HTTP/3 exchange protected by QUIC TLS. On authentication failure, the server deliberately behaves as an ordinary HTTP/3 service or forwards the request upstream instead of emitting a stable Hysteria-specific failure frame.

## TCP Proxying

Each proxied TCP connection is mapped to a QUIC bidirectional stream. The client
sends a Hysteria TCP request containing the destination address and optional
padding. After the server accepts the request, the remainder of that QUIC stream
carries the proxied TCP byte stream.

This gives independent stream-level delivery inside one QUIC connection and
avoids coupling every proxied TCP session to a separate TCP connection between
client and server.

### TCPRequest and TCPResponse wire format

All multibyte fixed-width integers in Hysteria 2 are big-endian, while `varint`
uses the QUIC variable-length integer encoding from RFC 9000.

Each proxied TCP connection starts on a newly opened QUIC bidirectional stream:

```text
TCPRequest
+----------------------+----------------------------------+
| varint 0x401         | message/type identifier          |
| varint addr_len      | byte length of address string    |
| addr_len bytes       | destination as "host:port"       |
| varint padding_len   | random padding byte count        |
| padding_len bytes    | random padding                    |
+----------------------+----------------------------------+
```

The address is a textual `host:port` string rather than SOCKS5's binary
`ATYP | DST.ADDR | DST.PORT` tuple. A parser therefore has to honor the explicit
byte length first and only then interpret the resulting string as an endpoint.
Do not search the incoming stream for a colon or assume an IPv4-shaped address.

The shortest QUIC-varint encoding of the TCPRequest identifier `0x401`
(`1025`) is the two bytes `44 01`. Do not hard-code those two bytes as a magic
prefix, however: RFC 9000 allows non-minimal encodings for variable-length
integers other than QUIC frame-type fields. A correct Hysteria parser decodes a
varint and compares its numeric value with `0x401`.

The server answers on the same QUIC stream:

```text
TCPResponse
+----------------------+----------------------------------+
| uint8 status         | 0x00 OK, 0x01 Error              |
| varint message_len   | byte length of message           |
| message_len bytes    | diagnostic message               |
| varint padding_len   | random padding byte count        |
| padding_len bytes    | random padding                    |
+----------------------+----------------------------------+
```

On `0x00`, everything after the response belongs to the proxied byte stream. On
`0x01`, the server closes that QUIC stream. This transition is analogous to a
successful SOCKS5 `CONNECT` reply followed by raw relay, but it occurs on one
QUIC stream among potentially many concurrent proxy streams.

### Stream parser boundary

QUIC provides an ordered byte stream, not message-sized reads. A single read can
contain only part of a varint, exactly one request, or the request plus later
bytes. Implementations should therefore parse incrementally and preserve any
bytes already read beyond the control message. Treating one socket/stream read
as one `TCPRequest` is incorrect for the same reason it is incorrect for a
SOCKS5 request on TCP.

### Multiplexing, stream limits, and TCP backpressure

Hysteria multiplexes independent proxied TCP connections as independent QUIC
bidirectional streams inside one QUIC connection. Loss on one stream does not
force bytes from another stream to wait for the missing stream offset, but all
streams still share the connection's congestion controller and path capacity.
This is transport multiplexing, not an application-level `MUX` command.

Reliable stream bytes are governed by two layers of QUIC flow control:

- connection-level credit (`MAX_DATA`) limits the total stream data in flight
  against the peer's advertised allowance;
- per-stream credit (`MAX_STREAM_DATA`) limits one individual proxy stream;
- the peer's bidirectional-stream limit controls how many new proxied TCP
  streams can be opened concurrently.

Consequently, a client that cannot immediately open a new proxy stream may be
stream-limit blocked rather than rejected by the Hysteria server, and a stream
whose writes stall may be flow-control or congestion blocked rather than a
failed destination connection. These transport states are different from a
`TCPResponse status=0x01` application-level failure.

QUIC stream directions can finish independently. Closing or resetting one
proxied TCP stream does not inherently close the parent QUIC connection or the
other proxy streams. Implementations should preserve TCP half-close semantics
where their socket abstraction supports them and should scope stream-local
errors to the affected proxy stream whenever the underlying QUIC connection is
still healthy.

## UDP Proxying

UDP relay uses QUIC's unreliable datagram capability. Hysteria adds metadata
including a session identifier, packet identifier, destination, and fragment
information.

When a UDP payload does not fit into the available QUIC datagram size, the
protocol can fragment it. Reassembly requires all fragments of a packet; loss
of one fragment means that datagram cannot be reconstructed.

Operationally, this makes MTU and path quality especially important for large
UDP packets.

### UDPMessage wire format

UDP does not open a QUIC stream. Each direction sends a complete Hysteria
`UDPMessage` through QUIC DATAGRAM:

```text
+----------------------+----------------------------------+
| uint32 session_id    | logical UDP association          |
| uint16 packet_id     | packet identity for fragments    |
| uint8 fragment_id    | zero-based fragment index        |
| uint8 fragment_count | total fragments                  |
| varint addr_len      | byte length of "host:port"       |
| addr_len bytes       | destination/source endpoint      |
| remaining bytes      | UDP payload fragment             |
+----------------------+----------------------------------+
```

The client chooses a unique `Session ID` for each logical UDP session. The
server normally associates a distinct outbound UDP source port with that ID so
that replies can be mapped back to the correct client-side flow.

There is no explicit `UDP CLOSE` command. The client may reuse a Session ID, and
the server expires its mapping according to inactivity or implementation
policy. If an expired ID later appears again, the server treats it as a new UDP
session. This is a major lifecycle difference from SOCKS5, whose UDP association
is explicitly anchored to the lifetime of a TCP control connection.

If the server advertised no UDP support, received UDP messages should be
silently discarded rather than producing a reliable error exchange.

### Fragmentation semantics

When one original UDP datagram is fragmented, all fragments carry the same
`Packet ID`; `Fragment ID` runs from zero and `Fragment Count` states how many
pieces must be reassembled. No fragment may be delivered upward until all pieces
arrive. Loss of any one piece causes the entire original UDP datagram to be
unrecoverable and it must be discarded.

For an unfragmented packet, `Fragment Count` is `1`; `Packet ID` and
`Fragment ID` then have no semantic significance. Implementations should bound
fragment reassembly memory and lifetime even though those resource limits are
local policy rather than fields in the base wire format.

### QUIC DATAGRAM framing, sizing, and backpressure

A Hysteria `UDPMessage` is the application payload carried inside one QUIC
DATAGRAM frame. RFC 9221 defines two DATAGRAM frame types, `0x30` and `0x31`; the
low bit only determines whether an explicit QUIC-level Length field is present.
Neither QUIC frame type changes the Hysteria `UDPMessage` layout.

The usable Hysteria payload size is therefore smaller than a naïve
`max_datagram_frame_size` calculation suggests. The sender has to fit all of
these into one QUIC packet:

```text
QUIC DATAGRAM frame overhead
+ Hysteria UDPMessage fixed header (8 bytes)
+ QUIC-varint address length
+ address string bytes
+ UDP payload fragment
```

The effective ceiling can be reduced further by QUIC's `max_udp_payload_size`
and by the current path MTU. QUIC DATAGRAM frames themselves are never
transport-fragmented or retransmitted. If one Hysteria UDP packet is too large,
Hysteria's `Packet ID / Fragment ID / Fragment Count` layer performs the
application-level fragmentation described above, or the packet is discarded.

DATAGRAM delivery has deliberately different backpressure semantics from TCP
proxy streams. RFC 9221 DATAGRAM frames:

- do **not** consume QUIC connection or per-stream flow-control credit;
- are still subject to the QUIC connection's congestion controller and pacing;
- are ack-eliciting, but their application payload is not retransmitted after
  loss;
- may be dropped locally if the sender cannot transmit them in time, or by the
  receiver if it cannot allocate resources to process them.

This explains an important diagnostic case: TCP proxy streams may remain healthy
while UDP relay loses packets under pressure. SOCKS5 UDP has a similar
unreliable application expectation, but it uses a separate UDP relay socket;
Hysteria's UDP traffic competes with its reliable streams inside the same QUIC
connection's congestion-control budget.

Because `Packet ID` is only 16 bits, long-lived high-rate sessions inevitably
wrap the identifier space. Senders should avoid reusing an identifier while an
older fragmented packet with the same identifier can still be reassembled, and
receivers should key reassembly state with at least the logical session plus
packet identity and expire incomplete entries promptly. `Fragment Count=0`, a
fragment index outside the declared count, inconsistent counts for one in-flight
packet, or lengths exceeding the received datagram are malformed inputs and
should be rejected without unbounded allocation.

## SOCKS5 Comparison by Stage

| Stage | SOCKS5 | Hysteria 2 |
| --- | --- | --- |
| Underlying transport | TCP control connection; separate UDP relay | One UDP-based QUIC connection |
| Security | None in RFC 1928/1929 | QUIC TLS before proxy authentication |
| Authentication negotiation | `VER/NMETHODS/METHODS`, then selected sub-negotiation | HTTP/3 `POST /auth` with `Hysteria-Auth` |
| Auth success | Authentication-method-specific result | HTTP status `233` |
| TCP command | `CMD=CONNECT` | Open bidi stream and send varint `0x401` TCPRequest |
| Destination | `ATYP + binary/domain address + uint16 port` | length-prefixed textual `host:port` |
| TCP result | SOCKS `REP` plus bound address | `status + message + padding` TCPResponse |
| TCP data | Raw bytes on the SOCKS TCP connection | Raw bytes on that QUIC stream |
| Concurrency | Normally another SOCKS TCP connection per independent CONNECT | Many independent QUIC streams share one QUIC connection |
| UDP setup | `UDP ASSOCIATE` command and returned relay endpoint | No separate command; auth response advertises UDP capability |
| UDP transport | Native UDP to SOCKS relay with SOCKS UDP header | QUIC DATAGRAM with Hysteria UDPMessage |
| UDP session lifetime | Bound to TCP control connection | Session ID plus server inactivity policy; no explicit close |
| Fragmentation | SOCKS UDP `FRAG` field; RFC recommends dropping if unsupported | Explicit Packet ID + Fragment ID + Fragment Count reassembly |
| Congestion control | Inherited independently from TCP/UDP transports | QUIC connection congestion control shared by streams and DATAGRAMs, plus receive-rate signaling |
| Reliable flow control | TCP receive windows on each SOCKS TCP connection | QUIC connection + per-stream flow control (`MAX_DATA`, `MAX_STREAM_DATA`) |
| Multiplexing | No multiplexing in RFC 1928; normally one CONNECT per control connection | Many TCP proxy streams and UDP DATAGRAMs share one QUIC connection |
| Failure scope | SOCKS reply failure normally ends that requested relay; transport loss ends the TCP control connection | `TCPResponse` error is stream-local; QUIC connection errors affect every proxy stream/session on that connection |
| Optional packet obfuscation | None | Salamander, optionally wrapped by Gecko before QUIC reaches the wire |

The conceptual correspondence is still recognizable: authentication precedes
proxy use, a TCP request names a destination and receives success/failure, and
UDP needs per-datagram destination metadata. Hysteria replaces SOCKS5's small
binary control protocol with HTTP/3 authentication plus QUIC-native streams and
datagrams, and adds connection-level multiplexing, encryption, congestion
control, and explicit UDP fragment identity.

## Boundary Conditions and Error Scope

A robust implementation has to distinguish errors at three different layers:

1. **HTTP/3 authentication:** any status other than `233` means Hysteria
   authentication failed and the client disconnects. The server intentionally
   does not need to expose a Hysteria-specific authentication error body.
2. **Proxy stream:** `TCPResponse status=0x01` means the requested destination
   failed; the server closes that QUIC stream, while unrelated streams can
   continue.
3. **QUIC transport:** malformed QUIC frames, DATAGRAM use without negotiated
   support, or DATAGRAM frames beyond the advertised transport limit can be
   connection-level protocol errors and therefore tear down every Hysteria flow
   multiplexed on that QUIC connection.

Length-prefixed fields must be validated before allocation or slicing. QUIC
varints can represent values up to 62 bits, which is far larger than any
reasonable address, diagnostic string, or padding field. The wire type alone is
not a safe allocation bound. Servers should impose practical limits on address,
padding, message, fragment-reassembly, concurrent-stream, and UDP-session state.

The base Hysteria specification deliberately leaves some malformed
application-message handling to implementations. Defensive parsers should fail
closed on truncated varints, truncated fixed-width fields, impossible fragment
metadata, and address lengths larger than the remaining message instead of
trying to recover by scanning for a later boundary.

## Packet-Capture View

Without QUIC decryption keys, a normal packet capture sees UDP packets carrying
QUIC rather than the `/auth`, TCPRequest, destination, or UDPMessage fields.
Useful observable phases are therefore:

```text
UDP/IP
  -> QUIC Initial / Handshake packets
  -> protected QUIC 1-RTT packets
       -> HTTP/3 authentication (encrypted)
       -> STREAM frames for TCP proxy streams (encrypted)
       -> DATAGRAM frames for UDP relay (encrypted)
```

With endpoint-side QUIC/TLS secrets and suitable tooling, the investigator can
separate HTTP/3 authentication, individual stream IDs, and DATAGRAM traffic.
A standards-oriented trace of the QUIC handshake can also expose transport
parameters such as `max_datagram_frame_size` before 1-RTT application data is
decoded. Even then, remember that QUIC packet boundaries are not TCPRequest
message boundaries: STREAM frames can split or coalesce application bytes.

For TCP, a decrypted stream begins with the varint value `0x401`, then the
length-prefixed destination and padding, followed by a `TCPResponse`, then raw
proxied bytes. For UDP, the DATAGRAM Data begins with the 8-byte fixed Hysteria
header (`Session ID`, `Packet ID`, `Fragment ID`, `Fragment Count`) before its
address-length varint. Those are useful dissector anchors after decryption, not
plaintext signatures visible to a normal on-path capture.

## Congestion Control and Bandwidth Information

Hysteria 2 allows peers to communicate receive-rate information during the
authentication exchange. Depending on configuration and the values exchanged,
the implementation can use explicit bandwidth information or rely on a normal
congestion-control algorithm.

Do not treat configured upload/download values as guaranteed throughput. They
influence transport behavior; the real path is still limited by RTT, packet
loss, server capacity, ISP shaping, and the congestion-control implementation.

## HTTP/3 Masquerading

An unauthenticated Hysteria endpoint is expected to behave like an HTTP/3
service rather than immediately exposing a proxy-specific protocol response.
Deployments can serve ordinary content or reverse-proxy to another site for
non-Hysteria requests.

This is an operational behavior, not a reason to neglect normal TLS and server
hardening. A Hysteria server remains a public UDP service and should be patched,
rate-limited where appropriate, and protected from credential leakage.

## Optional Obfuscation

Obfuscation is an outer packet transform below QUIC. It does not replace QUIC
TLS, Hysteria authentication, or proxy framing.

### Salamander

Salamander prepends an 8-byte random salt to every QUIC packet and XORs the QUIC
packet bytes with a repeating 32-byte BLAKE2b-256-derived mask:

```text
on-wire datagram
+----------------------+----------------------------------+
| 8-byte random salt   | sent in clear                    |
| obfuscated payload   | original QUIC packet XOR mask    |
+----------------------+----------------------------------+

mask = BLAKE2b-256(pre_shared_key || salt)
payload[i] ^= mask[i mod 32]
```

The receiver derives the same mask from the configured pre-shared key and the
received salt, reverses the XOR, and passes the recovered packet to QUIC. This
is traffic obfuscation, not an independent authenticated-encryption layer; QUIC
TLS remains responsible for confidentiality and integrity of Hysteria traffic.

### Gecko

The current upstream specification also defines Gecko as a wrapper around
Salamander. Gecko only changes the treatment of QUIC packets with the long-header
bit set. Short-header packets go directly through Salamander. A long-header
packet is split into between 2 and 8 chunks, and every chunk is wrapped before
Salamander processing:

```text
Gecko frame before Salamander
+----------------------+----------------------------------+
| uint8 flags          | 0x80 fragment marker             |
| uint8 msg_id         | original-packet identifier       |
| uint8 idx_count      | high/low 4-bit chunk metadata    |
| uint16 pad_len       | big-endian random padding length |
| pad_len bytes        | random padding                   |
| remaining bytes      | original QUIC packet chunk       |
+----------------------+----------------------------------+
```

`chunkIdx` must be smaller than `totalChunks`, and `totalChunks` is in the range
2 through 8. All chunks of one original QUIC packet carry the same `msgID` and
count. The receiver first reverses Salamander, groups Gecko fragments by source
address and message ID, validates consistent metadata, concatenates chunks in
index order, and only then gives the reconstructed long-header packet to QUIC.
Reassembly state needs per-source and global bounds plus a TTL to avoid turning
handshake camouflage into an allocation attack surface.

The practical capture consequence is significant. Without obfuscation, QUIC
long-header structure is visible even though its payload is encrypted. With
Salamander, the UDP payload no longer parses as ordinary QUIC. With Gecko, one
QUIC handshake packet can additionally appear as several independently padded
UDP datagrams. Client and server must agree on the obfuscation mode and key
before QUIC itself can establish a connection.

## Conceptual Client Configuration

A Clash-family profile commonly expresses a Hysteria 2 node with fields similar
to:

```yaml
proxies:
  - name: hy2-example
    type: hysteria2
    server: proxy.example.com
    port: 443
    password: "CHANGE-ME"
    sni: proxy.example.com
    skip-cert-verify: false
```

This is a compatibility-oriented example, not a promise that every field name
is accepted by every Chimera core version. Use the schema of the selected core
as the source of truth.

## Server Deployment Checklist

A Hysteria 2 server needs:

- UDP reachability on the selected listening port,
- valid TLS identity/configuration expected by the client,
- an authentication policy,
- sufficient UDP socket buffers for the target workload,
- appropriate firewall rules,
- and a decision about ordinary HTTP/3 fallback/masquerade behavior.

If a cloud provider, home router, or enterprise firewall blocks UDP, changing
Hysteria settings will not fix the underlying reachability problem.

## Strengths

- Native TCP and UDP proxying on top of QUIC.
- Independent QUIC streams reduce cross-stream interference compared with one
  monolithic reliable stream.
- QUIC connection behavior can perform well on lossy or high-latency paths.
- UDP relay maps naturally to QUIC datagrams.
- HTTP/3-facing authentication/fallback behavior provides a normal service path
  for unauthenticated requests.

## Limitations

- Requires usable UDP connectivity from client to server.
- Networks may block, throttle, or degrade QUIC independently of TCP/HTTPS.
- MTU problems can cause disproportionately confusing UDP failures.
- Aggressive bandwidth settings can create loss rather than improve throughput.
- Optional obfuscation adds configuration and interoperability complexity.

## Security Notes

- Keep certificate verification enabled for normal deployments.
- Use high-entropy authentication credentials and rotate them when clients are
  retired.
- Do not expose authentication values in URLs, screenshots, or debug logs.
- Treat HTTP/3 fallback content as a real public service and patch it normally.
- Rate limiting and abuse controls may be appropriate on publicly reachable
  servers.

## Chimera Status

### Chimera_Client

Hysteria 2 is listed as a current client-core capability. Validate the exact
accepted configuration schema and optional features against the current
`Chimera_Client` branch before assuming full parity with Hysteria's reference
implementation or Mihomo.

### Chimera GUI

Chimera stores and generates profile/runtime configuration but does not itself
implement Hysteria 2 transport logic.

### Chimera_Server

The current server capability map includes Hysteria 2 inbound work, and the
server documentation lists a Hysteria example configuration. Treat that as a
stronger signal than a purely planned feature, while still validating TCP, UDP,
authentication, and optional transport behavior separately.

## Troubleshooting

### Cannot connect at all

1. Confirm the hostname resolves to the intended server.
2. Verify UDP reachability to the configured port.
3. Check firewall/security-group rules on both ends.
4. Verify TLS name/certificate expectations.
5. Check the authentication value.

### TCP works but UDP fails

1. Confirm the server advertises/supports UDP relay.
2. Test small UDP packets first.
3. Check MTU and fragmentation behavior.
4. Check NAT/firewall timeout behavior.
5. Disable optional obfuscation temporarily to reduce variables.

### Poor throughput

1. Measure packet loss and RTT before changing bandwidth values.
2. Compare with a TCP-based protocol to determine whether the path is
   specifically hostile to UDP/QUIC.
3. Avoid over-reporting available bandwidth.
4. Check server CPU, socket-buffer limits, and uplink capacity.
5. Inspect whether a VPN, ISP, or enterprise firewall is rate-limiting QUIC.

## References

- Hysteria 2 protocol specification:
  <https://v2.hysteria.network/docs/developers/Protocol/>
- QUIC, RFC 9000: <https://www.rfc-editor.org/rfc/rfc9000>
- QUIC Datagram, RFC 9221: <https://www.rfc-editor.org/rfc/rfc9221>
- Using TLS to Secure QUIC, RFC 9001:
  <https://www.rfc-editor.org/rfc/rfc9001>
- QUIC Loss Detection and Congestion Control, RFC 9002:
  <https://www.rfc-editor.org/rfc/rfc9002>
- HTTP/3, RFC 9114: <https://www.rfc-editor.org/rfc/rfc9114>
