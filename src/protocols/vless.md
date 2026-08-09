# VLESS

## Positioning

VLESS is a lightweight, stateless proxy protocol from the Xray ecosystem. It is
designed to carry destination metadata and user identity while leaving most
transport security to a separate layer such as TLS or REALITY.

A useful way to read an Xray-style configuration is to separate three layers:

```text
VLESS                 -> proxy protocol / user identity / destination
XHTTP, RAW, gRPC ...  -> transport method
TLS or REALITY        -> transport security
```

Those layers can be combined only when the selected core supports the
combination.

## Identity and Authentication

VLESS users are identified by an `id`. A UUID is the common representation,
and current Xray versions can also map supported custom strings to a stable UUID
identity.

Unlike VMess, VLESS does not rely on synchronized system time for its basic user
identity model.

The user identity is not a substitute for transport encryption. Traditional
VLESS deployments therefore pair the protocol with TLS or REALITY.

## Connection Flow

At a high level:

1. The client establishes the configured transport and transport-security
   layer.
2. The client sends the VLESS request containing user identity, command, and
   destination information.
3. The server validates the user and requested mode.
4. The server opens or dispatches the destination connection.
5. Application traffic is relayed through the established transport.

The byte-level framing below follows the current Xray-core `main` VLESS
encoder/decoder. Because VLESS is an implementation-defined Xray protocol rather
than an IETF standard, verify these details again when targeting a materially
different core version.

## Baseline Wire Format

### Request header

For a normal TCP or UDP request, current Xray-core serializes the VLESS request
header in this order:

```text
+---------+----------------+----------------+---------+----------+------------------+
| Version | User ID        | Addons         | Command | Port     | Address          |
+---------+----------------+----------------+---------+----------+------------------+
| 1 byte  | 16 bytes       | 1 + N bytes    | 1 byte  | 2 bytes  | variable         |
+---------+----------------+----------------+---------+----------+------------------+
```

The important point is that **VLESS writes the destination port before the
address**, unlike SOCKS5 and Trojan, which put the address before the port.

Current Xray-core uses request version `0x00`. The next 16 bytes are the binary
user ID. A UUID string such as:

```text
11111111-2222-3333-4444-555555555555
```

is therefore not sent as 36 ASCII characters; the corresponding 128-bit value
is sent as 16 raw bytes.

### Addons field

Immediately after the user ID comes one byte containing the length of the
serialized VLESS addons block:

```text
+--------------+---------------------+
| AddonsLength | Addons protobuf     |
+--------------+---------------------+
| 1 byte       | N bytes             |
+--------------+---------------------+
```

For the ordinary no-flow case, `AddonsLength` is `0x00` and no addon bytes
follow. For supported flow modes such as `xtls-rprx-vision`, current Xray-core
serializes the addons structure as protobuf and prefixes it with a single-byte
length.

This is not analogous to SOCKS5 METHOD negotiation. The addons field is part of
the already-selected VLESS request format and carries optional VLESS/Xray
behavior for that request.

### Command byte

Current Xray-core defines these request command values:

| Value | Command | Transfer model |
| --- | --- | --- |
| `0x01` | TCP | stream |
| `0x02` | UDP | packet |
| `0x03` | Mux | stream |
| `0x04` | Reverse (`Rvs`) | stream |

For TCP and UDP, a destination address follows the command. `Mux` and `Rvs` are
special internal stream commands; the encoder does not append an ordinary
network destination for those commands.

### Destination address encoding

For ordinary TCP/UDP requests, the on-wire order is:

```text
+----------+------+-------------------------+
| Port     | ATYP | Address                 |
+----------+------+-------------------------+
| 2 bytes  | 1    | variable                |
+----------+------+-------------------------+
```

`Port` is a 16-bit network-order integer. Current Xray address-family values are:

```text
0x01  IPv4
0x02  Domain
0x03  IPv6
```

The address body is:

```text
IPv4:
  ATYP=0x01 | 4 address bytes

Domain:
  ATYP=0x02 | 1-byte domain length | domain bytes

IPv6:
  ATYP=0x03 | 16 address bytes
```

A domain is therefore length-prefixed in the same general style as SOCKS5, but
VLESS uses a different type value for domains (`0x02` versus SOCKS5 `0x03`) and
places the two-byte port before `ATYP`.

### Example request header

Ignoring transport security and using no addons, a TCP request to
`example.com:443` has the logical layout:

```text
00
<16-byte user ID>
00
01
01 bb
02 0b 65 78 61 6d 70 6c 65 2e 63 6f 6d
```

Read as:

```text
00        Version 0
UUID      16-byte identity
00        zero-length addons
01        TCP command
01 bb     port 443, big endian
02        domain address type
0b        domain length 11
...       "example.com"
```

Application bytes can follow the header on the same underlying byte stream. A
server parser must therefore stop exactly at the end of the address and retain
any already-read application bytes.

## Server-Side Request Parsing State Machine

A minimal inbound parser can be modeled as:

```text
TRANSPORT_READY
      |
      v
READ_VERSION (1)
      |
      | version == 0
      v
READ_USER_ID (16)
      |
      | user exists
      v
READ_ADDONS_LENGTH (1)
      |
      v
READ_ADDONS (N)
      |
      v
READ_COMMAND (1)
      |
      +---- Mux/Rvs ------> INTERNAL_STREAM_DISPATCH
      |
      +---- TCP/UDP
      v
READ_PORT (2)
      |
      v
READ_ATYP (1)
      |
      v
READ_ADDRESS
      |
      v
DISPATCH_DESTINATION
      |
      v
SEND_RESPONSE_HEADER
      |
      v
RELAY
```

An invalid request version, unknown user ID, malformed addons block, unsupported
command, invalid address type, truncated port, or truncated address must abort
normal VLESS request processing. Whether the outer connection is simply closed,
reset, or handled by another transport/fallback path depends on the surrounding
Xray transport and security configuration.

The parser must use exact-length reads for fixed-size fields. TCP, TLS, XHTTP,
and other stream transports do not preserve VLESS header boundaries.

## Response Header

VLESS has a small server-to-client response header before downlink application
data. Current Xray-core writes:

```text
+---------+--------------+------------------+
| Version | AddonsLength | Addons protobuf  |
+---------+--------------+------------------+
| 1 byte  | 1 byte       | N bytes          |
+---------+--------------+------------------+
```

The response version must equal the request version. In the common no-addon
case, the response begins:

```text
00 00
```

This is an important difference from SOCKS5. SOCKS5 returns a `REP` status plus
`BND.ADDR/BND.PORT`; baseline VLESS does **not** return an equivalent fixed
per-destination status code or bound-address tuple in this response header.

Consequently, a VLESS implementation normally learns about many destination or
transport failures through stream termination/reset and implementation error
handling rather than by parsing a SOCKS5-style `REP` byte.

## TCP Data Path

For `Command=0x01`, once the server has accepted the request and dispatched the
destination, the remaining body is a byte stream:

```text
Client                                Server                         Target
  |                                     |                              |
  | VLESS request header + early data   |                              |
  |------------------------------------>|                              |
  |                                     | TCP connect / dispatch       |
  |                                     |----------------------------->|
  |                                     |                              |
  |<------- VLESS response header ------|                              |
  |                                     |                              |
  |============ application bytes ================================>   |
  |<=========== application bytes =================================   |
```

There is no per-record VLESS framing for ordinary TCP payload in the no-flow
case. The outer transport may of course add its own framing: TLS records, XHTTP
requests, WebSocket frames, HTTP/2 frames, and so on are separate layers.

This separation is useful when debugging. A packet boundary from the outer
transport is not a VLESS application-message boundary.

## UDP Body Framing

Current Xray-core handles `Command=0x02` differently from TCP. Each UDP packet
is serialized onto the VLESS body stream as:

```text
+----------+------------------------+
| Length   | UDP payload            |
+----------+------------------------+
| 2 bytes  | Length bytes           |
+----------+------------------------+
```

The two-byte length is big endian. The destination is supplied by the VLESS
request header; ordinary packets in that VLESS request therefore do not repeat
`ATYP + address + port` for every datagram.

Conceptually:

```text
VLESS UDP request header
    |
    +-- uint16 length -- UDP datagram #1
    +-- uint16 length -- UDP datagram #2
    +-- uint16 length -- UDP datagram #3
```

This design is markedly different from SOCKS5 UDP relay:

- SOCKS5 sends each datagram over a real UDP socket and repeats the destination
  in every SOCKS UDP header.
- VLESS can carry UDP packet semantics over a stream transport by restoring
  packet boundaries with a two-byte length.
- Baseline VLESS body framing has no SOCKS5 `FRAG` byte. Fragmentation, MTU, or
  packetization behavior introduced by the outer transport is a separate
  concern.

A receiver must first read exactly two bytes, decode the length, and then read
exactly that many payload bytes. Treating a single socket read as one UDP packet
will fail as soon as the underlying stream splits or combines writes.

## Multiplexing Boundaries

A normal VLESS TCP request represents one logical destination stream. VLESS
itself does not magically make every `Command=TCP` request multiplexed just
because the outer connection is HTTP/2, XHTTP, or another multiplex-capable
transport.

There are two distinct places where multiplexing may appear:

1. the VLESS `Mux` command / Xray multiplexing layer; and
2. the outer transport, which may itself provide multiple logical streams or
   request flows.

Do not collapse these into one concept in implementation documentation. The
SOCKS5 baseline has neither feature: one SOCKS5 TCP control connection becomes
one CONNECT relay stream.

## Connection Close and Error Semantics

For baseline TCP relay, end-of-stream propagates through the selected outer
transport. Implementations need to distinguish:

- clean EOF after valid response/data,
- transport reset,
- invalid VLESS request before dispatch,
- destination connection failure,
- timeout / idle expiration,
- and outer TLS/REALITY/XHTTP failure before VLESS can even be parsed.

Unlike SOCKS5, VLESS does not provide a fixed reply-code taxonomy equivalent to
`REP=connection refused`, `network unreachable`, or `address type unsupported`.
Logs and the transport's close/reset semantics therefore carry more diagnostic
weight.

For UDP-over-stream, a truncated two-byte length or EOF before the declared
payload length is a malformed/incomplete packet, not a shorter valid datagram.

## Packet-Capture View

### VLESS over TLS/RAW

Without decryption, a capture typically exposes only the outer layers:

```text
TCP
  -> TLS handshake
  -> TLS application data
       -> encrypted VLESS header
       -> encrypted target payload
```

With TLS keys or instrumentation below TLS, the first decrypted application
bytes can be interpreted as the VLESS request header described above.

### VLESS over REALITY

The capture first looks like the REALITY/TLS-facing handshake. VLESS fields are
inside the accepted secure session and are not visible as clear-text UUID,
command, or address fields on the network.

### VLESS over XHTTP

The packet capture sees HTTP-layer requests/responses or HTTP/2/HTTP/3 transport
frames first. VLESS is payload carried *inside* those XHTTP flows. Therefore:

```text
IP/TCP(or QUIC)
  -> TLS/REALITY
      -> HTTP/XHTTP
          -> VLESS
              -> destination application protocol
```

This layer ordering is essential when deciding where a failure occurred.

## VLESS Compared with SOCKS5

| Stage / concept | SOCKS5 | VLESS baseline |
| --- | --- | --- |
| Initial transport | TCP to SOCKS server | Selected Xray transport |
| Built-in confidentiality | None | Usually supplied by TLS/REALITY/other layer |
| Protocol version | `VER=0x05` | request `Version=0x00` |
| Identity negotiation | METHOD list + selected METHOD | no method negotiation |
| User identity | RFC 1929 username/password or other method | fixed 16-byte user ID in request header |
| Optional protocol metadata | authentication subprotocol | one-byte addons length + optional protobuf |
| TCP command | `CMD=0x01 CONNECT` | `Command=0x01 TCP` |
| UDP command | `CMD=0x03 UDP ASSOCIATE` | `Command=0x02 UDP` |
| Other commands | `BIND` | `Mux`, `Rvs` are Xray-specific |
| Address order | `ATYP, ADDR, PORT` | `PORT, ATYP, ADDR` |
| IPv4 type | `0x01` | `0x01` |
| Domain type | `0x03` | `0x02` |
| IPv6 type | `0x04` | `0x03` |
| Domain length | 1 byte | 1 byte |
| Port | 2-byte network order | 2-byte network order |
| TCP success reply | explicit `REP` response | version + addons response; no SOCKS-style `REP` |
| Bound address in response | yes | no baseline equivalent |
| TCP body | raw byte stream | raw body in ordinary no-flow mode |
| UDP transport | separate UDP relay endpoint | length-framed packets over selected VLESS body transport |
| Destination repeated per UDP packet | yes | no, destination is in request header |
| SOCKS UDP `FRAG` equivalent | `FRAG` byte | no baseline equivalent in VLESS body framing |
| Multiplexing | not part of SOCKS5 | optional Xray/VLESS and/or transport layers |

The conceptual inheritance is still recognizable: authenticate/identify the
client, express a command, encode a destination, then relay traffic. VLESS
compresses those control phases into one request header and delegates security,
multiplexing, and camouflage to surrounding Xray layers.

## Implementation Checklist

A low-level VLESS implementation should verify at least these points:

1. Read exactly one version byte and reject unsupported versions.
2. Read exactly 16 user-ID bytes before looking up the user.
3. Bound and completely read the one-byte-length addons block.
4. Validate the command before interpreting destination fields.
5. For TCP/UDP, read the two-byte port before the address type.
6. For domains, enforce the one-byte length and read the complete domain.
7. Preserve bytes read beyond the end of the header as application payload.
8. Emit and consume the VLESS response header before treating downlink bytes as
   target payload.
9. For UDP, reconstruct packet boundaries from the two-byte length prefix.
10. Apply strict limits/timeouts so partial headers and declared UDP lengths
    cannot retain resources indefinitely.
11. Keep outer transport errors distinct from VLESS request-validation errors.
12. Test each transport/security combination independently; a correct VLESS
    parser does not imply XHTTP or REALITY interoperability.

## Transport Security

### TLS

TLS gives VLESS ordinary certificate-based transport security. The server name,
certificate chain, and client verification settings must be configured
correctly.

### REALITY

REALITY modifies the TLS-facing security layer and is commonly combined with
VLESS. See [Reality](./reality.md) for its key, short-ID, target, and fallback
model.

### No transport security

Current Xray documentation warns against using VLESS with no outer transport
security for ordinary public-internet proxying unless the peer is on a trusted
private path or VLESS Encryption is explicitly enabled and appropriate for the
deployment.

For this Wiki, the conservative rule is simple: **do not deploy bare VLESS over
an untrusted public path unless you understand and intentionally configure the
security model of the selected implementation.**

## Flow Control / XTLS Vision

Xray exposes `flow` options such as `xtls-rprx-vision` for compatible VLESS
combinations. Flow control is not merely a cosmetic config flag: client,
server, transport security, and underlying transport need to agree on the
supported combination.

When documenting Chimera compatibility, treat Vision support separately from
basic VLESS request parsing.

## Minimal Xray-Style Server Example

```json
{
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": 443,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "11111111-2222-3333-4444-555555555555"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "xhttp",
        "security": "reality",
        "xhttpSettings": {
          "path": "/api/sync",
          "mode": "auto"
        },
        "realitySettings": {
          "target": "example.com:443",
          "serverNames": ["example.com"],
          "privateKey": "SERVER-PRIVATE-KEY",
          "shortIds": ["0123456789abcdef"]
        }
      }
    }
  ]
}
```

This example demonstrates layer composition. It is not intended to be copied
unchanged: the target, keys, identifiers, path, and supported option names must
match the actual core version.

## Conceptual Client Example

```yaml
proxies:
  - name: vless-example
    type: vless
    server: proxy.example.com
    port: 443
    uuid: 11111111-2222-3333-4444-555555555555
    network: xhttp
    tls: true
    servername: example.com
```

Clash-family field names are implementation-specific. A profile valid in Mihomo
is not automatically valid in `chimera_client`.

## Strengths

- Small and relatively simple proxy-protocol layer.
- User identities scale beyond one shared global password.
- Can be combined with multiple Xray transport methods.
- Works with TLS and REALITY security layers in supported combinations.
- XTLS/Vision modes can optimize compatible traffic paths.

## Limitations

- VLESS alone should not be treated as complete public-internet transport
  security.
- Many useful deployments depend on Xray-specific transport/security behavior.
- Flow and transport compatibility can be confusing across different clients.
- Configuration schemas differ between Xray, Mihomo, Clash-family clients, and
  other implementations.
- A successful parser import does not prove transport interoperability.

## Security Notes

- Prefer TLS or REALITY for public deployments unless using a deliberately
  configured alternative security mechanism.
- Keep certificate verification enabled for TLS.
- Protect VLESS user IDs and server configuration even though an ID should not
  be treated like a human-memorable password.
- Rotate or disable identities for retired clients.
- Do not copy `flow` settings between unrelated transports without confirming
  support.

## Chimera Status

### Chimera_Client

The current `Chimera_Client` overview does **not** list standalone VLESS as a
separate current capability, even though related capabilities such as Reality +
TCP and XHTTP are documented. Until the client repository is used to establish
the exact supported combination, treat VLESS client support as
combination/branch-specific rather than claiming full parity.

### Chimera GUI

The GUI can store or generate VLESS-style profiles only to the extent that the
selected core understands them. Selecting Mihomo, clash-rs, or
`chimera_client` can therefore change the effective feature set.

### Chimera_Server

VLESS is explicitly included in the current server capability map, with example
server configurations documented in the server repository. This still does not
mean every transport, `flow`, fallback, encryption option, or Xray version is
fully compatible.

## Troubleshooting

### Authentication / immediate disconnect

1. Verify the user `id` on both ends.
2. Confirm the client and server are using compatible VLESS configuration
   shapes.
3. Check `flow` independently; remove optional flow tuning while isolating the
   base connection.

### TLS/REALITY succeeds but VLESS fails

1. Confirm the server inbound protocol is actually VLESS.
2. Check the user identity and decryption/encryption settings.
3. Verify the transport method (`raw`, XHTTP, gRPC, etc.) matches both ends.
4. Inspect server logs for request-version or user-validation errors.

### Works in one core but not another

1. Compare accepted field names rather than only values.
2. Compare transport/security combinations.
3. Check whether one core silently ignores unsupported fields.
4. Reduce the profile to one user, one transport, and no optional flow settings.

## References

- Xray VLESS inbound:
  <https://xtls.github.io/en/config/inbounds/vless.html>
- Xray VLESS outbound:
  <https://xtls.github.io/en/config/outbounds/vless.html>
- Xray transport compatibility:
  <https://xtls.github.io/en/config/transport.html>
