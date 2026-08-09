# TUIC

## Positioning

TUIC is a standardized proxy protocol for relaying TCP and UDP traffic over a
multiplexed secure transport. The current protocol specification is version
`0x05` and is designed primarily around QUIC, although the protocol model itself
is expressed in terms of a multiplexable TLS-encrypted stream rather than being
hard-wired to one implementation.

TUIC focuses on low-latency task startup, TCP/UDP multiplexing, connection-bound
authentication, and flexible UDP relay behavior.

## Protocol Layers

A typical QUIC deployment looks like:

```text
Application TCP / UDP
        │
        ▼
TUIC commands
        │
        ├── Connect       -> TCP relay
        ├── Packet        -> UDP relay
        ├── Dissociate    -> close UDP association
        └── Heartbeat     -> keep connection alive
        │
        ▼
Multiplexed QUIC connection + TLS
        │
        ▼
UDP/IP
```

The current upstream specification also defines an `Authenticate` command used
to authenticate the multiplexed connection.

## Authentication

TUIC v5 authentication is connection-bound. The client identifies itself with a
UUID and derives an authentication token from the current TLS session using the
TLS Keying Material Exporter and the configured password.

This matters operationally because authentication is tied to the secure session
rather than being a reusable clear-text token sent independently of TLS.

The protocol allows authentication and relay-task setup to overlap. An
implementation can receive task headers before authentication completes, but it
should not process those tasks until the connection has been authenticated.

## Common Command Wire Format

TUIC v5 uses one common envelope for all application commands. All fixed-width
multi-byte fields are encoded in big-endian order unless the specification says
otherwise:

```text
+-----+------+----------+
| VER | TYPE |   OPT    |
+-----+------+----------+
|  1  |  1   | Variable |
+-----+------+----------+
```

`VER` is `0x05` for the current protocol version. `TYPE` selects the command:

| TYPE | Command | Purpose |
| --- | --- | --- |
| `0x00` | `Authenticate` | Authenticate the multiplexed connection |
| `0x01` | `Connect` | Start one TCP relay task |
| `0x02` | `Packet` | Carry one UDP packet or fragment |
| `0x03` | `Dissociate` | Destroy one UDP association |
| `0x04` | `Heartbeat` | Keep the QUIC connection active |

`OPT` is not a TLV block with its own generic length. Its layout is determined
entirely by `TYPE`, so a parser must know the command type before it can know how
many bytes belong to the command header.

This differs from SOCKS5 in an important way. SOCKS5 has several distinct
message layouts (`METHOD`, authentication sub-negotiation, request, reply, UDP
header), while TUIC starts each application command with the same two-byte
`VER | TYPE` discriminator and then switches to a command-specific structure.

## Exact `Authenticate` Frame

The `Authenticate` command-specific data is fixed length:

```text
+------------------+----------------------------------+
| UUID             | TOKEN                            |
+------------------+----------------------------------+
| 16 bytes         | 32 bytes                         |
+------------------+----------------------------------+
```

Including the common command bytes, the logical command is therefore:

```text
0x05 | 0x00 | UUID[16] | TOKEN[32]
```

The client opens a QUIC unidirectional stream and sends this command. The UUID
is the client's 128-bit identity. The 256-bit token is derived from the current
TLS session using the TLS exporter interface, with the client UUID as the
exporter label and the raw password as exporter context.

Conceptually:

```text
QUIC/TLS session
      |
      +-- TLS exporter(label = UUID, context = password)
                         |
                         v
                    32-byte TOKEN
                         |
Client -- uni stream --> 05 00 UUID TOKEN --> Server
```

The important property is session binding: knowledge of a previously observed
token is not equivalent to knowledge of the raw password because a newly
established TLS session produces a new exporter context. TLS 1.3 keeps the
exporter interface while deriving exporter values through its HKDF-based key
schedule.

There is no TUIC application-level `AUTH OK` frame. Successful authentication
changes server-side connection state. Authentication failure is handled by the
implementation, commonly by ignoring work or closing the connection.

### Authentication State Machine

```text
Client                                      Server
  |                                            |
  |--- QUIC/TLS handshake ------------------->|
  |                                            |
  |--- uni stream: Authenticate ------------->|
  |                                            | verify UUID + TOKEN
  |                                            |
  |--- Connect/Packet may already arrive ---->|
  |                                            | hold header/task if auth pending
  |                                            |
  |                          auth succeeds ----+
  |                                            | resume paused tasks
  |                                            |
```

TUIC explicitly permits authentication and relay setup to overlap. A server
that sees `Connect` or `Packet` before `Authenticate` should accept enough of
the task to pause it, but should not process the relay until authentication has
completed.

## Address Encoding

TUIC uses a SOCKS-like variable-length address structure, but its type values
are different from RFC 1928:

```text
+------+--------------------------+----------+
| TYPE | ADDR                     | PORT     |
+------+--------------------------+----------+
|  1   | Variable                 | 2        |
+------+--------------------------+----------+
```

The address types are:

| TUIC TYPE | Meaning | Address bytes |
| --- | --- | --- |
| `0xff` | None | No address; used by later UDP fragments |
| `0x00` | Domain/FQDN | 1-byte length followed by domain bytes |
| `0x01` | IPv4 | 4 bytes |
| `0x02` | IPv6 | 16 bytes |

`PORT` is a 16-bit big-endian integer.

For example, `example.com:443` is conceptually:

```text
00 0b 65 78 61 6d 70 6c 65 2e 63 6f 6d 01 bb
^^ ^^ -------------------------------- ^^^^^
|  |              domain bytes          port 443
|  domain length = 11
TYPE = FQDN
```

SOCKS5 uses almost the same structural idea but different ATYP values:

```text
SOCKS5: ATYP 0x03 -> DOMAIN
TUIC:   TYPE 0x00 -> DOMAIN

SOCKS5: ATYP 0x01 -> IPv4
TUIC:   TYPE 0x01 -> IPv4

SOCKS5: ATYP 0x04 -> IPv6
TUIC:   TYPE 0x02 -> IPv6
```

The TUIC-only `0xff None` value exists because a fragmented UDP packet does not
need to repeat the target address in every fragment.

## TCP Relay

TCP relaying uses a `Connect` command on a bidirectional stream:

1. The client opens a bidirectional stream.
2. The client sends the target address in a `Connect` command.
3. The client can begin sending stream data without waiting for a separate
   application-level success response.
4. The server opens the requested TCP connection.
5. Once available, the server relays data between the destination socket and
   the QUIC stream.

This design contributes to TUIC's low-startup-latency behavior.

### Exact `Connect` Command

The command-specific part of `Connect` contains only the encoded target
address:

```text
+----------+
| ADDR     |
+----------+
| Variable |
+----------+
```

On a QUIC bidirectional stream the byte sequence is therefore logically:

```text
05 01 | ADDR | first TCP payload ...
```

There is no TUIC equivalent of SOCKS5's explicit success reply:

```text
SOCKS5
Client -> CONNECT request
Client <- REP=0x00 success
Client -> application bytes

TUIC
Client -> Connect header | application bytes
Client <- no protocol success frame
```

The TUIC server opens the requested TCP connection after parsing the `Connect`
header. The client is allowed to send application payload immediately after the
header without waiting for target-dial completion. A server implementation must
therefore be prepared to buffer or naturally backpressure that QUIC stream
while the outbound TCP dial is pending.

If the target cannot be reached, TUIC v5 defines no universal error reply. An
implementation may reset/close the QUIC bidirectional stream, close the whole
QUIC connection, or otherwise apply implementation-defined behavior.

### TCP Relay State Machine

```text
Client                              Server
  |                                   |
  | open QUIC bidi stream             |
  |--- 05 01 | ADDR ----------------->| parse target
  |--- first application bytes ------>| outbound connect pending
  |                                   |
  |                                   +--- TCP connect ---> target
  |                                   |
  |<========== QUIC stream ==============================>|
  |             bidirectional byte relay                  |
```

Each proxied TCP flow gets its own QUIC bidirectional stream. Loss affecting one
stream does not force the application data of unrelated TUIC streams into one
single ordered byte sequence, although all streams still share the QUIC
connection's congestion-control and path state.

## UDP Relay

TUIC uses an association identifier to keep UDP traffic for a logical session on
a corresponding server-side UDP socket.

A UDP packet can be carried using:

- a QUIC unidirectional stream for reliable delivery,
- or a QUIC datagram for native unreliable delivery.

The first packet for an association determines the reply mode for that
association in the reference protocol flow.

TUIC also defines packet identifiers and fragment fields so oversized UDP
packets can be split and reassembled.

When the client no longer needs a UDP association, it can send a `Dissociate`
command so the server releases the corresponding UDP socket.

### Exact `Packet` Header

A TUIC UDP packet or fragment uses:

```text
+----------+--------+------------+---------+------+----------+
| ASSOC_ID | PKT_ID | FRAG_TOTAL | FRAG_ID | SIZE | ADDR     |
+----------+--------+------------+---------+------+----------+
| 2        | 2      | 1          | 1       | 2    | Variable |
+----------+--------+------------+---------+------+----------+
```

Prepending the common command header gives:

```text
05 02 | ASSOC_ID | PKT_ID | FRAG_TOTAL | FRAG_ID | SIZE | ADDR | PAYLOAD
```

Fields mean:

- `ASSOC_ID`: 16-bit UDP association identifier generated by the client.
- `PKT_ID`: 16-bit identifier shared by all fragments of one original UDP
  datagram.
- `FRAG_TOTAL`: number of fragments in that original UDP datagram.
- `FRAG_ID`: index identifying this fragment.
- `SIZE`: byte length of this fragment's UDP payload.
- `ADDR`: destination address for client-to-server traffic, or source address
  for server-to-client traffic.
- `PAYLOAD`: exactly `SIZE` bytes belonging to this packet fragment.

Later fragments can encode `ADDR.TYPE = 0xff` (`None`) rather than repeating the
same address. This makes the first fragment important to reassembly metadata.

### Association Semantics

Both peers maintain an association table scoped to one QUIC connection:

```text
ASSOC_ID 0x0010 -> server UDP socket A
ASSOC_ID 0x0011 -> server UDP socket B
ASSOC_ID 0x0012 -> server UDP socket C
```

When the server receives the first `Packet` for a new `ASSOC_ID`, it allocates a
UDP socket and stores the mapping. Reusing that association ID causes later
client packets to leave through the same server-side UDP socket. That property
is what gives the protocol its Full Cone-style UDP behavior in the reference
flow.

Unlike SOCKS5, there is no separate `UDP ASSOCIATE` request/reply transaction
before the first UDP payload. The first TUIC `Packet` can implicitly create the
association.

### Native vs Reliable UDP Modes

TUIC defines two carriage choices for `Packet` commands:

```text
UDP relay mode "quic"
  Packet command -> QUIC unidirectional stream
  reliable delivery semantics

UDP relay mode "native"
  Packet command -> QUIC DATAGRAM
  unreliable delivery semantics
```

The server uses the same mode for return traffic that the client used for the
first packet of that association.

This is a major difference from Hysteria 2. Hysteria 2's UDP data path is
specified around QUIC DATAGRAM, whereas TUIC explicitly permits either a
reliable QUIC stream or an unreliable QUIC datagram for UDP packet carriage.
QUIC DATAGRAM frames themselves are not retransmitted by QUIC.

### Fragmentation and Reassembly

If one UDP datagram is too large for the chosen transport unit, TUIC can split
it into several `Packet` commands. Every fragment of one original datagram uses
the same `PKT_ID`; `FRAG_TOTAL` and `FRAG_ID` identify the reassembly set and
position.

A receiver needs reassembly state conceptually keyed by at least:

```text
QUIC connection + ASSOC_ID + PKT_ID
```

and should enforce bounds for:

- maximum fragment count,
- maximum aggregate packet size,
- duplicate fragment handling,
- reassembly timeout,
- number of simultaneously incomplete packets.

Those limits are important because the base specification defines the wire
fields but does not define a universal resource-management policy.

### `Dissociate`

The close command for a UDP association is compact:

```text
05 03 | ASSOC_ID[2]
```

The client sends it on a QUIC unidirectional stream. The server removes that
association from its table and releases the corresponding UDP socket.

This is more explicit than Hysteria 2, whose protocol does not provide an
explicit UDP-session close message, and structurally different from SOCKS5,
where the UDP association lifetime is tied to the accompanying TCP control
connection.

## 0-RTT Considerations

TUIC is designed to support very early relay-task setup and markets 0-RTT TCP
and UDP proxying as a core goal.

0-RTT should be understood as a latency optimization, not a reason to ignore
replay and session-security considerations. Actual behavior depends on the QUIC
and TLS implementation, resumption state, server policy, and the commands being
processed.

## Heartbeats

When relay tasks are active, the protocol defines a heartbeat command carried
through QUIC datagrams to keep the connection alive.

Long-lived mobile or NATed deployments should still account for operating-system
power management, NAT timeouts, and network transitions; application heartbeats
cannot guarantee that an external network preserves state indefinitely.

The logical heartbeat is simply:

```text
05 04
```

with no command-specific body. In the reference QUIC flow it is periodically
sent through a QUIC DATAGRAM while relay tasks are active.

## Error and Close Semantics

TUIC v5 deliberately does not define a response for every command. The
specification states that invalid commands, authentication failure, and target
connection errors have implementation-defined handling.

That has several consequences for client implementations:

1. Absence of a reply is normal for `Authenticate`, `Connect`, `Packet`,
   `Dissociate`, and `Heartbeat`; a client must not wait for a SOCKS-style
   success frame that will never arrive.
2. A reset/close of one bidirectional stream can be used by an implementation
   to signal failure of one TCP relay without necessarily closing the whole
   QUIC connection.
3. Authentication failure can cause connection close or silent rejection,
   depending on the implementation.
4. UDP `Packet` commands do not have per-packet acknowledgements at the TUIC
   layer. Reliable-stream mode relies on QUIC stream reliability; native mode
   deliberately accepts datagram loss.
5. `Dissociate` is advisory protocol state transition rather than a request that
   receives a standardized acknowledgement.

A robust implementation therefore needs to distinguish QUIC transport errors,
stream reset, application timeout, UDP loss, and explicit association teardown
rather than mapping every failure to one generic "proxy rejected" error.

## Packet-Capture View

Without QUIC session keys, a normal packet capture sees approximately:

```text
UDP/IP
  -> QUIC Initial / Handshake
  -> protected QUIC 1-RTT packets
       -> STREAM frames
       -> DATAGRAM frames
       -> ACK / flow-control / connection-management frames
```

The TUIC command bytes are encrypted inside QUIC application data. With QUIC
keys available to a dissector, the mapping becomes easier to reason about:

```text
QUIC uni stream    -> Authenticate / Packet(quic mode) / Dissociate
QUIC bidi stream   -> Connect header + proxied TCP bytes
QUIC DATAGRAM      -> Packet(native mode) / Heartbeat
```

A QUIC STREAM frame boundary is not a TUIC command boundary. Stream data can be
split across QUIC frames or delivered from multiple frames to one application
read. Parsers must accumulate exactly the fixed and variable fields required by
the command before treating subsequent bytes as payload.

For `Connect`, parser read-ahead is especially important: bytes obtained in the
same read after the variable-length `ADDR` are already proxied application data
and must not be discarded as command padding.

## Client and Server Connection State

A useful implementation-oriented connection state machine is:

```text
QUIC_CONNECTING
      |
      v
TLS_READY
      |
      +------> AUTH_SENT / AUTH_PENDING
      |               |
      |               v
      |          AUTHENTICATED
      |               |
      |        +------+------------------+
      |        |      |                  |
      |        v      v                  v
      |      TCP    UDP associations   heartbeat
      |      tasks   + reassembly       timer
      |        |      |                  |
      +--------+------+------------------+
                       |
                       v
                 QUIC_CLOSING
```

The server additionally needs per-stream and per-association state, because one
QUIC connection can contain many simultaneous TCP tasks and UDP associations.

## SOCKS5 vs Hysteria 2 vs TUIC

The three protocols expose similar proxy concepts through very different wire
models:

| Stage / concept | SOCKS5 | Hysteria 2 | TUIC v5 |
| --- | --- | --- | --- |
| Underlying transport | TCP control; separate UDP relay | QUIC over UDP | Usually QUIC over UDP |
| Security | None in base protocol | QUIC TLS | QUIC/TLS |
| Authentication | METHOD negotiation + selected sub-protocol | HTTP/3 `/auth` request | `Authenticate` command on uni stream |
| Auth success reply | Explicit method/auth response | HTTP status `233` | No TUIC success frame |
| User identity | Depends on auth method | Auth string | 16-byte UUID + TLS-exporter token |
| TCP request | `CONNECT` | `TCPRequest` on new bidi stream | `Connect` on new bidi stream |
| TCP success | `REP=0x00` | `TCPResponse Status=0` | No success response |
| Address model | `ATYP + ADDR + PORT` | text `host:port` | `TYPE + ADDR + PORT` |
| Concurrent TCP flows | Usually independent TCP control sessions | QUIC bidi streams | QUIC bidi streams |
| UDP setup | Explicit `UDP ASSOCIATE` | First datagram/session ID creates logical session | First `Packet`/ASSOC_ID creates association |
| UDP transport | Separate UDP socket | QUIC DATAGRAM | QUIC uni stream or DATAGRAM |
| UDP session ID | None in UDP header; tied to TCP control session | 32-bit Session ID | 16-bit ASSOC_ID |
| UDP packet ID | None | 16-bit Packet ID | 16-bit PKT_ID |
| Fragmentation | `FRAG` field, rarely implemented | Fragment ID + count | FRAG_TOTAL + FRAG_ID |
| Explicit UDP close | TCP control connection lifetime | No explicit protocol close | `Dissociate` command |
| Error model | Standard `REP` values | TCPResponse error for TCP setup | Mostly implementation-defined |
| Congestion/flow control | TCP + native UDP behavior | QUIC | QUIC |

### What TUIC Reuses from the SOCKS5 Mental Model

The same basic proxy operations are still present:

```text
identify/authenticate client
        -> name a target
        -> establish TCP relay
        -> optionally relay UDP
        -> tear state down
```

TUIC also retains the familiar variable-length `address type + address + port`
idea. This makes its `Connect` target structurally closer to SOCKS5 than
Hysteria 2's textual `host:port` field.

### What TUIC Replaces

TUIC replaces several SOCKS5 control transactions:

- METHOD negotiation becomes connection-bound TLS-exporter authentication.
- SOCKS5 `CONNECT request -> REP success` becomes a one-way `Connect` header
  followed immediately by payload.
- `UDP ASSOCIATE request -> relay endpoint reply` becomes an implicitly created
  `ASSOC_ID` mapping.
- one TCP control connection no longer represents one proxy task; QUIC streams
  multiplex many tasks inside one secure connection.

### What TUIC Adds

TUIC adds concepts with no direct SOCKS5 equivalent:

- TLS-exporter-bound authentication token,
- QUIC stream multiplexing,
- QUIC connection migration and shared connection-level congestion state,
- selectable reliable/unreliable UDP carriage,
- explicit UDP association IDs,
- packet IDs and protocol-level UDP fragmentation,
- `Dissociate`,
- application heartbeat over QUIC DATAGRAM,
- possible overlap between authentication and relay-task creation.

These are the main reasons TUIC should be understood as a complete secure,
multiplexed proxy transport rather than simply "SOCKS5 over QUIC".

## Conceptual Configuration

A Clash-family TUIC node commonly contains information similar to:

```yaml
proxies:
  - name: tuic-example
    type: tuic
    server: proxy.example.com
    port: 443
    uuid: 11111111-2222-3333-4444-555555555555
    password: "CHANGE-ME"
    sni: proxy.example.com
    skip-cert-verify: false
```

Additional fields may select congestion control, UDP relay mode, ALPN, and
heartbeat/timeout behavior. Use the schema of the selected core rather than
copying options blindly between Mihomo, ClashRS, sing-box, or another
implementation.

## Strengths

- TCP and UDP relay in one multiplexed secure connection.
- Designed for low relay-task startup latency.
- Native QUIC advantages such as multiplexing and connection migration.
- UDP can use unreliable QUIC datagrams or reliable stream-based delivery.
- Connection-bound authentication using TLS exporter material.
- Explicit UDP association lifecycle and fragmentation support.

## Limitations

- Requires a network path that handles QUIC/UDP reliably for the common
  deployment model.
- Different TUIC protocol versions are not guaranteed to interoperate.
- Configuration names and optional behavior differ between implementations.
- QUIC fingerprinting, UDP throttling, and MTU issues can still affect real
  deployments.
- Very aggressive congestion-control tuning can hurt fairness and stability.

## Security Notes

- Keep certificate verification enabled unless a controlled development setup
  explicitly requires otherwise.
- Use unique UUID/password credentials per user or deployment where practical.
- Treat 0-RTT as an optimization with security trade-offs, not as a universal
  fast path.
- Protect server configuration files because the raw password participates in
  authentication-token derivation.
- Keep server and client on compatible protocol versions.

## Chimera Status

### Chimera_Client

TUIC is currently listed in this Wiki under **planned client support**, not in
the current client capability list. Do not present a TUIC profile as supported
by `chimera_client` until the relevant implementation is enabled and validated
in the client repository.

### Chimera GUI

The GUI can only expose TUIC if the selected proxy core supports it. A profile
accepted by Mihomo or another core does not automatically imply support by
`chimera_client`.

### Chimera_Server

The server capability map includes TUIC-related inbound parsing/handling work.
That should be treated as implementation scope rather than a blanket guarantee
of TUIC v5 interoperability, UDP modes, 0-RTT behavior, or every client option.

## Troubleshooting

### Cannot connect

1. Verify UDP reachability to the server.
2. Confirm server/client TUIC protocol versions are compatible.
3. Validate SNI and certificate trust.
4. Check UUID and password independently.
5. Compare ALPN and other QUIC/TLS settings.

### TCP works but UDP fails

1. Verify the selected UDP relay mode is supported on both ends.
2. Test small datagrams first.
3. Inspect MTU and packet fragmentation.
4. Check association timeout behavior.
5. Confirm NAT/firewall policy allows return UDP traffic.

### Intermittent mobile failures

1. Check whether the client's network changed between Wi-Fi and cellular.
2. Compare with a fresh connection rather than only relying on migration.
3. Inspect NAT and idle timeouts.
4. Reduce optional tuning to defaults.
5. Compare against another QUIC-based protocol to isolate path-level blocking.

## References

- TUIC protocol repository: <https://github.com/tuic-protocol/tuic>
- TUIC v5 specification: <https://github.com/tuic-protocol/tuic/blob/master/SPEC.md>
- QUIC, RFC 9000: <https://www.rfc-editor.org/rfc/rfc9000>
- TLS Exported Authenticators / exporter background, RFC 5705:
  <https://www.rfc-editor.org/rfc/rfc5705>
