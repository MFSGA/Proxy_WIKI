# VLESS

## Positioning

VLESS is a lightweight, stateless proxy protocol from the Xray ecosystem. Its
baseline request carries destination metadata and user identity. Historically
VLESS relied almost entirely on a separate TLS or REALITY layer for
confidentiality; current Xray also implements optional **VLESS Encryption**, a
protocol-layer encrypted wrapper that can protect the VLESS request and body.

A useful way to read an Xray-style configuration is to separate three layers:

```text
VLESS request/body           -> proxy protocol / user identity / destination
optional VLESS Encryption    -> protocol-layer encryption + key exchange
XHTTP, RAW, gRPC ...         -> transport method
optional TLS or REALITY      -> outer transport security / HTTPS appearance
```

Those layers can be combined only when the selected core supports the
combination.

## Identity and Authentication

VLESS users are identified by an `id`. A UUID is the common representation,
and current Xray versions can also map supported custom strings to a stable UUID
identity.

Unlike VMess, VLESS does not rely on synchronized system time for its basic user
identity model.

The user identity is not itself encryption. Traditional deployments therefore
pair VLESS with TLS or REALITY. Current Xray can instead, or additionally, use
VLESS Encryption; that protects the VLESS payload but does not by itself create
the ordinary HTTPS appearance supplied by TLS or REALITY.

## Connection Flow

At a high level:

1. The client establishes the configured outer transport and, if configured,
   TLS/REALITY.
2. If VLESS Encryption is enabled, client and server complete its key-exchange
   wrapper (or resume an accepted 0-RTT session).
3. The client sends the VLESS request containing user identity, command, and
   destination information through the resulting plain or encrypted body path.
4. The server validates the VLESS user and requested mode.
5. The server opens or dispatches the destination connection.
6. Application traffic is relayed through the same layered path.

The byte-level framing below follows the current Xray-core `main` VLESS
encoder/decoder. Because VLESS is an implementation-defined Xray protocol rather
than an IETF standard, verify these details again when targeting a materially
different core version.

## VLESS Encryption: Outer Handshake and Record Layer

VLESS Encryption is negotiated by configuration rather than by adding a new
method-selection field to the baseline VLESS header. The client `encryption`
and server `decryption` strings must describe compatible handshake and
traffic-appearance modes. Current official configuration uses
`mlkem768x25519plus` as the handshake method and exposes three appearances:
`native`, `xorpub`, and `random`.

A typical generated pair conceptually has this shape:

```text
server decryption:
  mlkem768x25519plus.<appearance>.<ticket-lifetime>.<padding>.<client-auth-key>

client encryption:
  mlkem768x25519plus.<appearance>.0rtt|1rtt.<padding>.<server-auth-key>
```

The authentication key block can use X25519 material or ML-KEM-768 material.
The ephemeral handshake itself combines ML-KEM-768 with X25519, so the
configured static authentication choice and the per-connection PFS exchange are
different concepts.

### 1-RTT client-to-server handshake layout

The current `proxy/vless/encryption` implementation starts with a random 16-byte
IV followed by one or more **NFS relays** derived from the configured static
authentication keys. For a relay using X25519, the public-key contribution is 32
bytes; for ML-KEM-768, the encapsulated ciphertext contribution is 1088 bytes.
When more than one configured relay participates, 32-byte BLAKE3-derived linkage
values bind the relay chain so an intermediate relay cannot simply be replaced.

After the IV and NFS relay area, the normal 1-RTT client handshake sends:

```text
+----------------------+--------------------------------------------+
| 16 bytes             | random IV                                  |
| variable             | NFS relay/authentication material          |
| 18 bytes             | AEAD( uint16 length = 1232 )               |
| 1232 bytes           | AEAD( ML-KEM-768 pub 1184                  |
|                      |       + X25519 pub 32 )                     |
| 18 bytes             | AEAD( uint16 encrypted-padding length )    |
| variable             | AEAD( client padding )                     |
+----------------------+--------------------------------------------+
```

Why `18` bytes for a two-byte length? The length itself is a big-endian
`uint16`, and the AEAD adds a 16-byte authentication tag. Likewise, the
1216-byte hybrid client PFS public material becomes 1232 bytes after the tag.
The client can split the configured padding into multiple writes with delays;
those write boundaries are camouflage behavior and are not protocol-message
boundaries for a parser.

The server first derives the NFS key from the relay area and uses it to open the
encrypted length. For the 1-RTT path it then decrypts the 1184-byte ML-KEM-768
encapsulation key plus the 32-byte X25519 public key, creates its own ML-KEM and
X25519 contributions, and derives a 64-byte PFS secret (`32 ML-KEM + 32 X25519`).
That PFS secret is combined with the per-connection NFS key to form the keying
material used by the later record layer.

The 1-RTT server response begins with:

```text
+----------------------+--------------------------------------------+
| 1136 bytes           | AEAD( ML-KEM-768 ciphertext 1088           |
|                      |       + X25519 pub 32 )                     |
| 32 bytes             | AEAD( 16-byte session ticket )             |
| 18 bytes             | AEAD( uint16 server-padding length )       |
| variable             | AEAD( server padding )                     |
+----------------------+--------------------------------------------+
```

The first field is 1120 bytes of server PFS public/ciphertext material plus a
16-byte tag. The ticket plaintext is 16 bytes and becomes 32 bytes with its tag.
The first two ticket bytes encode the accepted ticket lifetime. A zero lifetime
means there is no resumable 0-RTT session.

### 0-RTT resumption and replay boundary

When the client is configured for `0rtt`, has an unexpired cached ticket, and the
server allows resumption, it can avoid the full PFS exchange. It still creates a
fresh IV and NFS key, then sends:

```text
IV + NFS relays
AEAD(uint16 32)          # says the next item is a ticket
AEAD(16-byte ticket)     # 32 bytes on wire including tag
first encrypted VLESS record(s) immediately
```

The resumed traffic key combines the cached PFS secret with the **new** NFS key,
so each resumed connection still has fresh connection-specific material. The
server stores NFS-key use per ticket and rejects a repeated key as a replay. If
the ticket has expired, current server code sends random-looking bytes so the
client abandons the cached session and retries with a new handshake rather than
silently accepting old 0-RTT state.

0-RTT therefore reduces startup latency; it is not a promise that arbitrary
application actions become replay-safe. A caller should keep the same security
caution it would apply to any early-data mechanism.

### Encrypted application-record layout

After either handshake path, the VLESS header and subsequent body are carried
through `CommonConn`. Current Xray splits writes into plaintext chunks of at
most 8192 bytes and wraps each chunk as:

```text
+--------+--------+--------+----------------+---------------------------+
| 0x17   | 0x03   | 0x03   | Length (BE16)  | AEAD ciphertext           |
+--------+--------+--------+----------------+---------------------------+
| 1 byte | 1 byte | 1 byte | 2 bytes        | plaintext + 16-byte tag   |
+--------+--------+--------+----------------+---------------------------+
```

The five-byte prefix intentionally has the shape of a TLS 1.3 application-data
record (`17 03 03`), but **VLESS Encryption is not TLS**. The header is used as
AEAD associated data. Receivers require a ciphertext length from 17 through
16640 bytes; malformed headers, truncated records, or failed AEAD tags terminate
that encrypted stream.

Record keys are derived with BLAKE3 from the handshake key material and a
connection-specific context. Current code chooses AES-GCM when the endpoint has
appropriate AES-GCM hardware support and otherwise uses ChaCha20-Poly1305; the
server can detect the peer choice while opening the first encrypted handshake
length. Nonces increment independently by direction. The implementation also
has a rekey path if the 96-bit nonce counter reaches its maximum rather than
allowing nonce reuse.

### `native`, `xorpub`, and `random` capture appearance

These options change observable encoding, not the inner VLESS command format:

- `native` leaves the key-exchange public/ciphertext material in its native
  representation and retains the TLS-record-like five-byte data headers;
- `xorpub` masks the public/ciphertext portions of the NFS relay using a
  BLAKE3-derived AES-CTR stream, reducing their native public-key appearance;
- `random` additionally masks the five-byte record headers in each direction,
  so the post-handshake stream no longer exposes the repeated `17 03 03`
  record-header pattern.

If VLESS Encryption itself is carried inside real TLS or REALITY, an ordinary
on-path capture sees the outer TLS/REALITY layer first. The inner appearance
mode only becomes directly observable after removing that outer layer.

### Encryption state machine and failure scope

```text
OUTER_TRANSPORT_READY
        |
        v
READ IV + NFS RELAYS
        |
        +-- static auth / relay failure --------> abort/fallback policy
        |
        v
OPEN ENCRYPTED LENGTH
        |
        +-- length == 32 ------------------------> 0-RTT ticket path
        |       | expired / replay / disabled --> reject; client re-handshakes
        |       ` accepted ---------------------> ENCRYPTED_RECORDS
        |
        `-- 1-RTT PFS length
                |
                v
           ML-KEM-768 + X25519 exchange
                |
                v
           TICKET + BIDIRECTIONAL PADDING
                |
                v
           ENCRYPTED_RECORDS
                |
                v
           BASELINE VLESS HEADER -> BODY
```

This introduces an error layer that baseline SOCKS5 does not have. A failed
ML-KEM/X25519 exchange or AEAD tag means the server has not yet reached the
VLESS UUID/command parser; changing a destination address or SOCKS-style command
cannot repair such a failure.

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
transport. With VLESS Encryption enabled, EOF/reset first crosses the encrypted
record wrapper and only then the baseline VLESS body. Implementations need to
distinguish:

- clean EOF after valid response/data,
- VLESS Encryption handshake failure,
- expired or replayed 0-RTT ticket,
- malformed encrypted record header or failed AEAD tag,
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
       -> [optional VLESS Encryption handshake + records]
       -> VLESS request/body
```

With TLS keys or instrumentation below TLS, the next layer is either the
baseline VLESS request header or, when enabled, the VLESS Encryption handshake.
After a VLESS Encryption 1-RTT handshake, `native`/`xorpub` mode commonly exposes
five-byte inner record headers shaped as `17 03 03 <BE16 length>`; `random` masks
those headers as well. These are inner VLESS Encryption records, not a second
real TLS session.

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

| Stage / concept | SOCKS5 | VLESS / current Xray |
| --- | --- | --- |
| Initial transport | TCP to SOCKS server | Selected Xray transport |
| Built-in confidentiality | None | Baseline none; optional VLESS Encryption; TLS/REALITY can be an additional outer layer |
| Encryption negotiation | none in RFC 1928/1929 | preconfigured `encryption` / `decryption`; no on-wire method list |
| Encryption handshake | none | optional NFS authentication + ML-KEM-768/X25519 hybrid PFS, or ticket resumption |
| Early data | SOCKS request follows method/auth completion | VLESS Encryption can resume with ticket-backed 0-RTT |
| Encrypted record framing | none beyond TCP | optional `17 03 03 + uint16 length + AEAD(ciphertext)` style records; `random` masks header appearance |
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
| Failure before proxy command | method/auth failure | outer transport or VLESS Encryption handshake/AEAD failure can happen before UUID/command parsing |

The conceptual inheritance is still recognizable: authenticate/identify the
client, express a command, encode a destination, then relay traffic. Baseline
VLESS compresses those control phases into one request header. Current VLESS
Encryption adds a separate configured cryptographic wrapper **before** that
header, while TLS/REALITY, XHTTP, and multiplexing can still add further outer
layers. None of those encryption stages replaces the VLESS destination command.

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
12. If VLESS Encryption is enabled, bound/read the IV, relay area, encrypted
    lengths, PFS material, ticket, and padding exactly; reject failed AEAD tags.
13. Keep 0-RTT ticket expiry and replay rejection distinct from UUID or
    destination rejection.
14. Parse encrypted application records incrementally: exactly 5 header bytes,
    then exactly the declared ciphertext length; never use transport read
    boundaries as record boundaries.
15. Test `native`, `xorpub`, and `random` independently if the selected core
    exposes them; they change outer encoding, not the baseline VLESS header.
16. Test each transport/security combination independently; a correct VLESS
    parser does not imply XHTTP or REALITY interoperability.

## Transport Security

### VLESS Encryption

Current Xray treats VLESS Encryption as optional **protocol-layer security**.
It can make `streamSettings.security: "none"` acceptable on a public-address
connection from the confidentiality/integrity perspective, but the official
transport guidance explicitly distinguishes that from censorship camouflage:
VLESS Encryption does not make the connection look like ordinary HTTPS in the
way TLS or REALITY can.

Use `xray vlessenc` to generate matching client `encryption` and server
`decryption` values unless there is a specific reason to construct the detailed
blocks manually. A mismatch in handshake method, appearance, or authentication
material fails before the baseline VLESS request can be decoded.

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

Current Xray also allows Vision with VLESS Encryption without the older
transport restrictions. If the underlying path cannot use direct raw copying,
Vision can still penetrate the VLESS Encryption layer to avoid redundant
crypto-copy overhead; on compatible raw TCP paths it can additionally attempt
the normal direct/splice optimization. This is an optimization layer above the
wire-format correctness described earlier, not a new VLESS command.

When documenting Chimera compatibility, treat Vision and VLESS Encryption
support separately from basic VLESS request parsing.

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
- Xray-core VLESS Encryption client implementation:
  <https://github.com/XTLS/Xray-core/blob/main/proxy/vless/encryption/client.go>
- Xray-core VLESS Encryption server implementation:
  <https://github.com/XTLS/Xray-core/blob/main/proxy/vless/encryption/server.go>
- Xray-core VLESS Encryption record implementation:
  <https://github.com/XTLS/Xray-core/blob/main/proxy/vless/encryption/common.go>
