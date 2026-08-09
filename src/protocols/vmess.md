# VMess

## Positioning

VMess is an encrypted proxy protocol from the V2Ray/Xray ecosystem. It carries
client identity, a proxy command, a destination, and encrypted TCP- or UDP-style
payloads. In current Xray-core, new VMess sessions use the **VMess AEAD** request
header design; older pre-AEAD authentication formats should be treated as
legacy protocol history rather than the wire format to implement for a current
Xray-compatible peer.

VMess is a proxy-protocol layer. Xray can place its ordered byte stream inside
other transport methods such as RAW/TCP, WebSocket, or HTTP-oriented transports,
and can additionally wrap those transports in TLS where supported. Those outer
layers do not replace the VMess authentication, command, destination, or body
record format described here.

A useful layer model is:

```text
application TCP / UDP
        |
        v
VMess AEAD
  - AuthID / user authentication
  - command + destination
  - encrypted body chunks
        |
        v
optional Mux.Cool / XUDP behavior
        |
        v
selected Xray transport
        |
        v
optional outer TLS / other transport security
```

## Current Versus Legacy VMess

The official Project X protocol page still documents historical VMess fields,
including the original timestamp-derived authentication hash and older body
security choices. Current Xray-core has moved further:

- the inbound decoder first tries the 16-byte **AEAD AuthID** path;
- current VMess account security types are AES-128-GCM and
  ChaCha20-Poly1305, with `auto` resolving to one of those on the client;
- the old `alterId` model is not part of current VMess AEAD sharing;
- current Xray configuration no longer offers VMess `none/zero/plain` body
  security.

The logical command header remains recognizably derived from VMess version 1,
so the legacy specification is still useful for field meanings. The important
implementation rule is to distinguish that **logical plaintext command layout**
from the current **AEAD envelope** that protects it on the wire.

## End-to-End Connection Flow

A current VMess connection can be read as this state sequence:

```text
Client                                                   Server
  | establish selected outer transport                      |
  |--------------------------------------------------------->|
  |                                                         |
  | AuthID (16)                                             |
  | AEAD(request-header length) (18)                        |
  | connection nonce (8)                                    |
  | AEAD(request header) (L + 16)                           |
  |--------------------------------------------------------->|
  |                                    match user + timestamp|
  |                                    reject replay         |
  |                                    decrypt/validate hdr  |
  |                                    dispatch destination  |
  |                                                         |
  | encrypted/masked VMess body chunks ====================>|
  |<========================================================>|
  |                                                         |
  |<-------------- AEAD(response-header length) (18)        |
  |<-------------- AEAD(response header) (R + 16)           |
  |<================ encrypted response body chunks ========|
  |                                                         |
  | termination record / EOF / outer transport close        |
```

There is no SOCKS5-style method-selection round trip. The first VMess protocol
bytes already contain an authenticated user/time token and the encrypted proxy
request. There is also no SOCKS5-style `REP` byte: destination or dispatch
failure is normally observed as a failed/closed VMess exchange rather than a
portable numeric VMess result code.

## User Identity and Command Key

The configured VMess user ID resolves to a 16-byte UUID value. Current Xray also
allows short custom strings in configuration by deterministically mapping them
to UUID form; the wire authentication still operates on the resulting account
identity and its derived command key.

The UUID itself is **not sent as 16 plaintext bytes at the front of a current
VMess AEAD request**. Xray derives a 16-byte command key from the account ID.
That key is used to construct and validate the AEAD AuthID and to derive the
request-header AEAD keys.

This differs from VLESS, whose baseline header places its 16-byte user identity
inside the VLESS request. It also differs from SOCKS5 RFC 1929, where username
and password are sent in an explicit authentication sub-negotiation.

## AEAD AuthID: Exact 16-Byte Plaintext Before Encryption

Current Xray creates a 16-byte AuthID plaintext:

```text
+----------------------+----------------------------------+
| uint64 timestamp     | Unix seconds, big-endian         |
| 4 random bytes       | per-request random value         |
| uint32 CRC32         | CRC32 of the first 12 bytes      |
+----------------------+----------------------------------+
        8 + 4 + 4 = 16 bytes
```

Those 16 bytes are encrypted as one AES block using a key derived from the
user's command key. The resulting 16-byte ciphertext is the first VMess AEAD
field visible on the protocol stream.

Server validation performs several distinct checks:

1. try the configured users' AuthID decoders;
2. decrypt the candidate AuthID;
3. verify the CRC32 over the first 12 plaintext bytes;
4. reject negative/invalid timestamps;
5. require the timestamp to be within 120 seconds of the server's current Unix
   time;
6. reject an AuthID already present in the anti-replay filter.

This is why VMess documentation warns that client and server UTC clocks must be
synchronized. Time zone is irrelevant; Unix time freshness is what matters.

The AuthID anti-replay filter and the later request-body session-history check
protect different values. Passing AuthID validation is necessary but is not the
last replay-related check performed by the current server.

## VMess AEAD Request Header Envelope

After creating AuthID, current Xray generates an independent random 8-byte
`connectionNonce` and AEAD-protects both the logical request-header length and
the logical request header.

On the wire:

```text
+----------------------+--------------------------------------------+
| 16 bytes             | AuthID ciphertext                          |
| 18 bytes             | AEAD( uint16 request_header_length )       |
| 8 bytes              | connectionNonce                            |
| L + 16 bytes         | AEAD( L-byte logical request header )      |
+----------------------+--------------------------------------------+
```

The length plaintext is a big-endian `uint16`; AES-GCM adds its 16-byte tag, so
that field occupies 18 bytes. The request-header ciphertext similarly adds 16
bytes to the logical header length.

Both AEAD operations use keys/nonces derived from:

- the VMess user's command key,
- the 16-byte AuthID,
- the 8-byte connection nonce,
- and fixed VMess KDF labels.

The AuthID is also supplied as AEAD associated data. Consequently, changing the
AuthID, encrypted length, connection nonce, or protected header without the
correct user key causes authentication failure before the destination is parsed.

### Incremental parsing boundary

The request is carried over an ordered stream. A parser must therefore read:

1. exactly 16 bytes of AuthID;
2. exactly 18 bytes of encrypted length;
3. exactly 8 bytes of connection nonce;
4. decrypt the length;
5. then read exactly `L + 16` bytes of encrypted request header.

A single TCP/QUIC/WebSocket read is not a VMess message boundary. Conversely,
one transport read can contain the whole header plus the start of the encrypted
body; read-ahead bytes must be preserved for the body decoder.

## Logical Request Header Layout

After the AEAD envelope is opened, the current Xray logical header begins:

```text
+----------------------+--------------------------------------------+
| uint8  version       | 0x01                                       |
| 16 bytes body_iv     | random request-body IV                     |
| 16 bytes body_key    | random request-body key                    |
| uint8 response_v     | random response authentication byte        |
| uint8 options        | body framing/options bitmask                |
| uint8 P|security     | high nibble padding length; low security    |
| uint8 reserved       | currently 0                                 |
| uint8 command        | TCP=0x01, UDP=0x02, Mux=0x03               |
| destination          | absent for Mux; otherwise port+address      |
| P bytes              | random command-header padding               |
| uint32 FNV1a         | checksum of preceding logical header        |
+----------------------+--------------------------------------------+
```

The first 38 bytes end with the command byte. Destination length is variable,
then `P` can add 0--15 random bytes, followed by the four-byte FNV-1a checksum.
The server validates that checksum **after** successfully opening the outer
AEAD header. AEAD integrity and the inner FNV checksum are therefore separate
validation layers.

Current Xray rejects an unresolved/unknown body security value after parsing the
logical header. `auto` is a client configuration choice; the client resolves it
to an actual on-wire security type before sending the request.

### Option bits

The current common protocol definitions use these relevant bits:

| Bit | Name | Meaning |
| --- | --- | --- |
| `0x01` | chunk stream | payload uses VMess chunk records; historical name is now marked deprecated in code, but current VMess outbound still sets the bit |
| `0x04` | chunk masking | two-byte chunk lengths are XOR-masked with a SHAKE128-derived stream |
| `0x08` | global padding | each chunk may have pseudo-random padding in addition to encrypted payload |
| `0x10` | authenticated length | experimental AEAD protection for chunk-length fields |

For current AES-GCM/ChaCha20-Poly1305 VMess, Xray enables chunk masking and
global padding by default. `AuthenticatedLength` remains an experiment that
must be compatible on both peers.

## Destination Encoding

VMess encodes the destination in a different order from SOCKS5. Current Xray's
VMess address parser is configured with **port first**:

```text
+----------------------+----------------------------------+
| uint16 DST.PORT      | big-endian                       |
| uint8  ATYP          | 0x01 IPv4, 0x02 domain, 0x03 IPv6|
| address bytes        | depends on ATYP                  |
+----------------------+----------------------------------+
```

Address payloads are:

| ATYP | Address layout |
| --- | --- |
| `0x01` | 4 IPv4 bytes |
| `0x02` | `uint8 length` + that many domain bytes |
| `0x03` | 16 IPv6 bytes |

For comparison, SOCKS5 uses `ATYP | DST.ADDR | DST.PORT`; VMess uses
`DST.PORT | ATYP | DST.ADDR`. A parser shared between the protocols must not
reuse the SOCKS5 field order accidentally.

The base VMess TCP/UDP commands are:

```text
0x01  TCP
0x02  UDP
0x03  Mux.Cool logical stream
```

Current common Xray definitions also have other internal request-command values,
but VMess interoperability documentation should not invent wire semantics for a
command unless both peers implement it.

## Request Body Record Format

After the protected command header, VMess switches to independently
authenticated body chunks. In the ordinary current AEAD body modes the logical
record is:

```text
+----------------------+--------------------------------------------+
| size field           | 2 bytes masked, or 18 bytes when the       |
|                      | AuthenticatedLength experiment is used     |
| ciphertext           | plaintext chunk + 16-byte AEAD tag         |
| optional padding     | 0..63 clear random bytes with global pad   |
+----------------------+--------------------------------------------+
```

The size value describes the encrypted payload plus any global padding. With
normal chunk masking, the two-byte big-endian value is XORed with successive
16-bit values from SHAKE128 seeded by the request-body IV. The same SHAKE stream
also produces the global-padding length modulo 64.

Global padding is outside the AEAD ciphertext. It changes chunk size/shape but
does not become application bytes after decoding.

With the `AuthenticatedLength` experiment, the logical two-byte size is itself
AEAD-protected and therefore occupies 18 bytes. This adds integrity to the
record length rather than relying only on masking.

### AES-128-GCM body mode

The request's random 16-byte body key is used as the AES-128-GCM key. Each
record uses a direction-local increasing counter in its nonce construction and
adds a 16-byte authentication tag.

### ChaCha20-Poly1305 body mode

Xray expands the 16-byte request body key into the 32-byte ChaCha20-Poly1305 key
using the VMess-defined MD5-based expansion. Record nonces follow the same
counter-plus-IV model and each record carries a 16-byte Poly1305 tag.

Current Xray outbound configuration exposes `aes-128-gcm`,
`chacha20-poly1305`, and `auto`. As of the current implementation, `none` is not
a valid current VMess body security mode.

## TCP Data Path

For `command=0x01`, the destination in the request header is a TCP destination.
After user/header validation the server dispatches that target, decodes VMess
body records, and writes the recovered bytes to the destination TCP stream.
Bytes received from the target take the reverse path through the VMess response
header and response-body record encoder.

VMess body chunks are framing units, not application message boundaries. A TCP
application record can span multiple VMess chunks, and one VMess chunk can
contain bytes from multiple application writes. Implementations must preserve
byte order, not write-call boundaries.

Flow control comes primarily from the selected outer reliable transport and the
server's destination socket. VMess chunk framing does not define a SOCKS-like
window-update command or independent stream credit.

## UDP Data Path

For base `command=0x02`, the request header names a UDP destination and body
handling switches to packet transfer semantics. Current Xray's authentication
writer preserves each packet buffer as one authenticated VMess body record
rather than concatenating packets into a TCP-style byte stream.

Base VMess UDP therefore differs from SOCKS5 UDP in two major ways:

- the destination is established in the encrypted VMess request header rather
  than repeated in every UDP relay datagram;
- the VMess client/server transport remains the selected reliable VMess stream,
  rather than switching to the separate native UDP relay socket defined by
  SOCKS5 `UDP ASSOCIATE`.

Base VMess has no SOCKS5 `FRAG` byte and no Hysteria/TUIC-style packet ID plus
fragment count. If a deployment needs broader UDP association semantics,
current Xray can add XUDP over its Mux path. That is an extra layer and should
not be mistaken for the base `command=0x02` wire format.

Current Xray outbound can, under its cone/XUDP policy, rewrite some UDP flows to
`command=0x03` with the Mux destination `v1.mux.cool` and then use an XUDP packet
writer. A capture/dissector must therefore determine whether it is seeing base
VMess UDP or VMess carrying Mux/XUDP before interpreting packet boundaries.

## Response Header

Current Xray derives response body key and IV values by SHA-256 hashing the
request body key and IV and taking the first 16 bytes. The response control
header is then AEAD-protected separately from the body.

Wire layout:

```text
+----------------------+--------------------------------------------+
| 18 bytes             | AEAD( uint16 response_header_length )      |
| R + 16 bytes         | AEAD( R-byte response header )             |
+----------------------+--------------------------------------------+
```

The decrypted response header is logically:

```text
+----------------------+----------------------------------+
| uint8 response_v     | must equal request response_v    |
| uint8 options        | response options                 |
| uint8 command        | response command, normally 0     |
| uint8 command_len    | command-content length           |
| command_len bytes    | optional command content         |
+----------------------+----------------------------------+
```

The client checks `response_v`; a mismatch means the response is not valid for
that VMess session. There is no general success/failure status byte comparable
to SOCKS5 `REP`. A valid response header authenticates the responding VMess peer
at the protocol level, while target failures are handled by stream/error
behavior rather than a portable VMess result-code table.

After this header, response body chunks use the same selected body-security
algorithm, but with response-direction keys, IV, length-mask stream, nonces, and
padding state.

## Termination, Half-Close, and Error Scope

Historically, chunked VMess sends a termination record when a direction has no
more payload. With AEAD body security, an empty plaintext packet is represented
by a record whose encrypted portion consists only of the AEAD authentication
overhead (plus any generated padding). The decoder recognizes that shape as
end-of-stream.

Current Xray also has a `NoTerminationSignal` experiment/behavior; the outbound
checks that setting before emitting the explicit empty body record. Therefore a
robust peer must also handle clean outer EOF according to the negotiated/current
implementation behavior.

Keep these error scopes separate:

- **outer transport error**: TCP/WebSocket/TLS/etc. fails before VMess parsing;
- **AuthID error**: unknown user, timestamp outside the ±120-second window, CRC
  mismatch, or AuthID replay;
- **request-header AEAD error**: encrypted length or payload tag fails;
- **session replay error**: the tuple of VMess user + request body key + request
  body IV is reused within the server's session-history window;
- **logical-header error**: checksum, address, command, or security is invalid;
- **body-record error**: masked/authenticated size is malformed or an AEAD tag
  fails;
- **destination/dispatch error**: VMess parsed correctly but the requested
  target cannot be opened or routed;
- **response error**: response AEAD or `response_v` validation fails.

Current Xray keeps body-session replay history for several minutes and separately
keeps AuthID anti-replay state around the authentication timestamp window. Do
not merge those caches into one conceptual "VMess replay token" when
implementing diagnostics.

A VMess protocol error normally terminates the affected outer connection. If
Mux.Cool is layered above VMess, inner logical stream failures can have a
narrower scope than failure of the parent VMess/transport connection.

## State Machines

### Client

```text
DISCONNECTED
    |
    v
OUTER_TRANSPORT_READY
    |
    v
BUILD AuthID + AEAD REQUEST HEADER
    |
    v
SEND HEADER
    |
    +------------------------------+
    |                              |
    v                              v
SEND BODY RECORDS              READ RESPONSE HEADER
    |                              |
    |                              +-- AEAD / response_v fail -> ERROR
    |                              |
    |                              v
    |                          READ BODY RECORDS
    |                              |
    +--------------+---------------+
                   v
              DRAIN / EOF
                   |
                   v
                 CLOSED
```

The two data directions can run concurrently once the request has been sent.
The client does not wait for a SOCKS-style explicit success byte before it can
start sending proxied body data.

### Server

```text
ACCEPT OUTER STREAM
    |
    v
READ 16-BYTE AuthID
    |
    +-- no user / stale / replay --------> DRAIN/REJECT/CLOSE
    |
    v
OPEN AEAD LENGTH + REQUEST HEADER
    |
    +-- tag/length/checksum error -------> DRAIN/REJECT/CLOSE
    |
    v
CHECK BODY KEY+IV SESSION REPLAY
    |
    +-- duplicate -----------------------> REJECT/CLOSE
    |
    v
PARSE COMMAND + DESTINATION + SECURITY
    |
    +-- invalid -------------------------> REJECT/CLOSE
    |
    v
DISPATCH DESTINATION
    |
    +-- failure -------------------------> CLOSE/ERROR
    |
    v
RELAY BODY <====> ENCODE RESPONSE HEADER/BODY
    |
    v
EOF / TIMEOUT / ERROR
```

Current Xray intentionally drains a behavior-derived amount of data on some
invalid-request paths before closing. That is an implementation-level traffic
analysis defense; clients must not interpret delayed close as protocol success.

## Multiplexing and Flow Control

Base VMess does not multiplex arbitrary independent TCP proxy requests inside
one VMess request. Normally each independent VMess TCP command is associated
with its own outer proxy stream/connection.

Xray's `command=0x03` hands the body to **Mux.Cool**, which is a separate
multiplexing protocol. XUDP can also ride that path. When diagnosing a trace,
keep the layers distinct:

```text
VMess AEAD authentication / encryption
        |
        `-- command 0x03
              |
              v
          Mux.Cool
              |
              +-- logical stream A
              +-- logical stream B
              `-- XUDP packets ...
```

VMess itself has record sizes, masking, padding, and AEAD counters but no
independent per-logical-stream flow-control window. Mux flow control, HTTP/2 or
QUIC stream flow control in an outer transport, and TCP congestion control are
separate mechanisms.

## Packet-Capture View

### VMess directly on a clear outer byte stream

A current VMess AEAD request does **not** begin with a plaintext UUID, command,
or destination. A dissector sees approximately:

```text
16 bytes  AuthID ciphertext
18 bytes  AES-GCM-protected header length
 8 bytes  connection nonce
L+16       AES-GCM-protected logical request header
...        masked/padded AEAD body records
```

The first 16 bytes are deliberately not a stable user identifier. Because the
AuthID contains the current timestamp plus random data before block encryption,
two connections from the same user do not begin with the same 16-byte prefix.

The destination, TCP/UDP command, body IV/key, and selected body cipher are all
inside the encrypted request-header payload.

### VMess inside TLS/WebSocket/HTTP transports

With an outer encrypted transport, the passive capture first exposes that layer:

```text
TCP/UDP
  -> TLS / QUIC / HTTP transport framing
       -> VMess AEAD AuthID + header
            -> VMess encrypted records
                 -> application bytes
```

Without outer decryption keys or endpoint instrumentation, VMess fields cannot
be located simply by packet offsets. With decryption, remember that WebSocket,
HTTP, or QUIC frame boundaries still do not define VMess record boundaries.

### Useful endpoint-side anchors

For an instrumented implementation, useful checkpoints are:

- first 16 bytes accepted as AuthID and mapped to a user;
- decrypted big-endian logical header length from the next 18 bytes;
- logical header version `0x01`;
- command and `PORT | ATYP | ADDR` after opening the header;
- option/security byte and body IV/key;
- two-byte masked lengths or 18-byte authenticated lengths in the body;
- 16-byte AEAD tags per encrypted body record;
- 18-byte AEAD response-header length followed by the protected response header.

## SOCKS5 Comparison by Stage

| Stage / concept | SOCKS5 RFC 1928/1929 | Current VMess AEAD |
| --- | --- | --- |
| Outer connection | TCP control connection | Selected ordered Xray transport; commonly backed by TCP, possibly with additional framing/security |
| Method negotiation | `VER/NMETHODS/METHODS` | none; client/server configuration already selects VMess and body security |
| Authentication | optional method, e.g. RFC 1929 username/password | 16-byte encrypted AuthID derived from user command key, timestamp and randomness |
| Replay protection | not defined by RFC 1928/1929 | timestamp window + AuthID replay filter + request body key/IV session history |
| Authentication round trip | explicit method/auth response | no separate auth reply; request header follows AuthID immediately |
| Proxy command | `CMD` after negotiation | encrypted logical command byte (`0x01` TCP, `0x02` UDP, `0x03` Mux) |
| Destination order | `ATYP | ADDR | PORT` | `PORT | ATYP | ADDR` inside AEAD request header |
| Domain encoding | one-byte length + domain | one-byte length + domain |
| Success reply | `REP=0x00` plus bound address | no SOCKS-equivalent status; authenticated response header carries `response_v`, options, optional command |
| Failure reply | standardized `REP` values | mostly close/error behavior; no portable destination-error code table |
| TCP payload | raw bytes after successful reply | masked/padded AEAD body records |
| Payload confidentiality | none in base SOCKS5 | AES-128-GCM or ChaCha20-Poly1305 body encryption in current Xray |
| UDP setup | `UDP ASSOCIATE` on TCP control connection | VMess `command=0x02` names a fixed UDP destination in the encrypted request |
| UDP carrier | separate native UDP relay with SOCKS UDP header | encrypted VMess body records on the selected VMess stream; XUDP/Mux may add another model |
| UDP per-packet destination | present in every SOCKS UDP datagram | not present in base VMess UDP body; destination comes from request header |
| UDP fragmentation field | SOCKS `FRAG` | no base VMess fragment ID/count field |
| Multiplexing | not defined in base SOCKS5 | extra `command=0x03` Mux.Cool layer can multiplex logical streams |
| Flow control | inherited from TCP / UDP behavior | inherited from outer transport plus destination; Mux/HTTP/QUIC layers may add their own flow control |
| End of stream | TCP FIN/close anchors association | VMess termination record and/or outer EOF depending on current behavior |

The most important conceptual difference is that SOCKS5 separates negotiation,
authentication, command, reply, and then raw relay into visible phases. VMess
compresses user authentication and proxy dispatch into a protected first-flight
request and continues with authenticated record framing. Mux.Cool, XUDP,
WebSocket, TLS, and other transports are additional layers rather than
substitutes for that VMess request.

## Boundary Conditions and Defensive Parsing

A compatible implementation should explicitly guard these cases:

- partial reads at every fixed or variable-length AEAD field;
- request-header length that exceeds a practical implementation bound;
- stale or future AuthID timestamps outside the accepted 120-second window;
- repeated AuthIDs;
- repeated body key/IV session tuples;
- unsupported logical header version;
- invalid security nibble;
- truncated IPv4/IPv6/domain addresses;
- zero-length or overlong domain fields according to the current address parser;
- odd behavior where a Mux command incorrectly includes ordinary destination
  bytes;
- padding length larger than remaining logical header bytes;
- FNV checksum mismatch;
- chunk-size decode underflow/overflow after masking/padding;
- failed AEAD tags;
- counter/nonce exhaustion;
- clean termination record versus abrupt outer EOF;
- slow readers that create unbounded buffering in outer transport or Mux layers.

Do not allocate directly from an untrusted encrypted-length value until the
length AEAD tag has been verified and a local upper bound has been applied.
Likewise, do not dispatch the destination until the complete logical header,
padding, and checksum have been validated.

## Security Notes

- Synchronize client and server UTC clocks. Current VMess AuthID validation uses
  a 120-second freshness window.
- Use high-entropy VMess user IDs and rotate credentials when clients are
  retired.
- Do not publish UUIDs merely because the on-wire AuthID is encrypted; the UUID
  is still shared authentication material.
- Prefer current VMess AEAD. Do not build new deployments around `alterId` or
  legacy non-AEAD sharing formats.
- Current Xray no longer offers VMess `none/zero/plain` body security; do not
  write compatibility documentation that suggests those are current choices.
- VMess protocol encryption does not automatically make traffic look like
  ordinary HTTPS. If censorship resistance or normal TLS server identity is a
  deployment requirement, evaluate the appropriate outer transport/security
  layer separately.
- Bound invalid-request drain behavior, replay caches, body buffering, and Mux
  state to avoid turning defensive behavior into a resource-exhaustion surface.
- Logs may identify whether AuthID, header AEAD, checksum, body AEAD, or dispatch
  failed, but remote error behavior should not reveal unnecessary user/account
  information.

## Minimal Current Xray-Style Configuration

A current outbound conceptually looks like:

```json
{
  "protocol": "vmess",
  "settings": {
    "address": "proxy.example.com",
    "port": 443,
    "id": "5783a3e7-e373-51cd-8642-c83782b807c5",
    "security": "auto"
  }
}
```

`security: "auto"` is a client-side selection convenience. It resolves to an
actual supported body cipher; the server learns the selected cipher from the
protected logical VMess header. Current Project X documentation lists
AES-128-GCM and ChaCha20-Poly1305 as the explicit choices.

Transport settings belong outside this VMess account object and should be tested
independently from VMess AEAD correctness.

## Chimera Status

### Chimera_Client

The current Proxy Wiki capability page lists VMess under **Planned or Targeted
Support**, not under the client's currently available protocol set. Treat VMess
client configuration as a target capability until the corresponding client
implementation is present and verified.

### Chimera GUI

Chimera can eventually expose/store VMess profile fields without implementing
the VMess cryptography itself. UI/profile support and runtime protocol support
should be tracked independently.

### Chimera_Server

The current server capability map explicitly lists VMess inbound work. Validate
that implementation against the current AEAD-only Xray behavior described here,
including AuthID time/replay checks, current body-security choices, TCP, UDP,
and any Mux/XUDP behavior it claims to support.

## Troubleshooting

### Immediate rejection

1. Verify the user ID on both peers.
2. Check actual UTC time and keep skew well below 120 seconds.
3. Confirm both peers implement current VMess AEAD rather than an incompatible
   legacy/alterId mode.
4. Check whether the outer transport is delivering a clean ordered byte stream.
5. Distinguish AuthID rejection from request-header AEAD/checksum rejection in
   endpoint logs.

### Header succeeds but data fails

1. Confirm the body security selected by the client is AES-128-GCM or
   ChaCha20-Poly1305 and is decoded as that exact security nibble.
2. Verify request body key/IV extraction and response key/IV derivation.
3. Check chunk masking and global-padding state in both directions.
4. If `AuthenticatedLength` is enabled, ensure both peers implement the same
   experiment behavior.
5. Check AEAD nonce counters and packet/stream transfer mode.

### TCP works but UDP fails

1. Determine whether the flow is base VMess UDP or Mux/XUDP.
2. For base VMess UDP, confirm `command=0x02` and the fixed destination in the
   request header.
3. Preserve packet boundaries through the VMess body reader/writer.
4. Do not expect SOCKS5-style per-datagram destination headers or `FRAG`.
5. Check outer transport buffering and any MTU/datagram constraints in the
   layers surrounding VMess.

## References

- Project X VMess protocol description:
  <https://xtls.github.io/en/development/protocols/vmess.html>
- Project X current VMess inbound configuration:
  <https://xtls.github.io/en/config/inbounds/vmess.html>
- Project X current VMess outbound configuration:
  <https://xtls.github.io/en/config/outbounds/vmess.html>
- Xray-core VMess AEAD header implementation:
  <https://github.com/XTLS/Xray-core/blob/main/proxy/vmess/aead/encrypt.go>
- Xray-core VMess AuthID implementation:
  <https://github.com/XTLS/Xray-core/blob/main/proxy/vmess/aead/authid.go>
- Xray-core VMess client encoding:
  <https://github.com/XTLS/Xray-core/blob/main/proxy/vmess/encoding/client.go>
- Xray-core VMess server encoding:
  <https://github.com/XTLS/Xray-core/blob/main/proxy/vmess/encoding/server.go>
- Xray-core common request/security definitions:
  <https://github.com/XTLS/Xray-core/blob/main/common/protocol/headers.go>
