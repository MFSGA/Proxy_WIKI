# Shadowsocks

Shadowsocks is an encrypted proxy protocol rather than a SOCKS5 session carried over an encrypted channel. Applications may enter `Chimera_Client` through SOCKS/HTTP/TUN, but the remote Shadowsocks connection has its own address header, key derivation, record framing, authentication tags, and UDP packet format.

This chapter separates two protocol families that must not be conflated:

- classic Shadowsocks AEAD, commonly using AES-GCM or ChaCha20-Poly1305;
- Shadowsocks 2022 AEAD, which changes key material, replay protection, TCP headers, UDP session identifiers, and multi-user identity handling.

The implementation notes below were checked against the current `Chimera_Client` and `Chimera_Server` source trees. Upstream Shadowsocks specifications remain the authority for portable wire behavior; Chimera-specific limitations are called out explicitly.

## Position in the Stack

```text
Application
   │
   ▼
SOCKS / HTTP / TUN                 local ingress, optional
   │
   ▼
Shadowsocks address + data         remote proxy protocol
   │
   ▼
AEAD encryption/authentication     built into Shadowsocks
   │
   ▼
TCP or UDP
   │
   ▼
Shadowsocks server
   │
   ▼
Target
```

Unlike Trojan or VLESS + TLS, classic Shadowsocks AEAD does not first establish a TLS session. Encryption and integrity are part of the Shadowsocks record format itself. SIP003 plugins can add an outer transport/camouflage layer, but that layer is separate from the Shadowsocks cryptographic stream.

## Address Encoding

The destination encoding uses the familiar SOCKS-style address tuple but without SOCKS5's `VER`, `CMD`, `RSV`, or reply fields.

| Address type | Wire value | Remaining fields |
| --- | ---: | --- |
| IPv4 | `0x01` | 4-byte IPv4 + 2-byte big-endian port |
| Domain | `0x03` | 1-byte domain length + domain bytes + 2-byte big-endian port |
| IPv6 | `0x04` | 16-byte IPv6 + 2-byte big-endian port |

So a domain destination such as `example.com:443` begins conceptually as:

```text
03 0b 65 78 61 6d 70 6c 65 2e 63 6f 6d 01 bb
│  │  └──────────── "example.com" ───────────┘ │
│  domain length = 11                           port 443
└─ ATYP = domain
```

This address format is reused inside TCP and UDP plaintext structures before encryption.

## Classic AEAD Methods

The current `Chimera_Server` classic AEAD path accepts these methods:

| Method | Key length | Salt length | AEAD tag |
| --- | ---: | ---: | ---: |
| `aes-128-gcm` | 16 bytes | 16 bytes | 16 bytes |
| `aes-256-gcm` | 32 bytes | 32 bytes | 16 bytes |
| `chacha20-ietf-poly1305` | 32 bytes | 32 bytes | 16 bytes |

`Chimera_Client` maps a wider set through the Rust `shadowsocks` crate, including `xchacha20-ietf-poly1305`, AEAD-2022 method names, and `rc4-md5`. Do not infer Server interoperability from the Client parser alone: the current Server explicitly rejects classic `xchacha20-poly1305` and does not expose `rc4-md5` in its inbound cipher parser.

## Classic AEAD Key Derivation

For the current Server legacy/classic path:

1. the textual password is converted into a master key using the traditional iterative MD5-compatible derivation;
2. each TCP direction or UDP packet uses a random salt whose length equals the cipher key length;
3. HKDF-SHA1 with info string `ss-subkey` derives the per-session subkey from `master_key` and `salt`;
4. the AEAD nonce starts at zero and increments for each protected item in the stream direction.

The salt is therefore not merely decorative randomness: repeating it with the same master key would repeat the derived session key. The Server keeps a timed salt cache and rejects recently replayed salts.

## Classic AEAD TCP Wire Format

The encrypted TCP direction starts with one salt followed by independently authenticated length and payload records:

```text
+----------------------+  salt_len
| random salt          |
+----------------------+
| ENC(length: u16)     |  2 bytes ciphertext
| TAG                   |  16 bytes
+----------------------+
| ENC(payload)          |  length bytes ciphertext
| TAG                   |  16 bytes
+----------------------+
| ENC(next length)      |
| TAG                   |
+----------------------+
| ENC(next payload)     |
| TAG                   |
+----------------------+
             ...
```

The current Server caps a classic plaintext record at `0x3fff` bytes. The first decrypted plaintext bytes of a client-to-server stream are the Shadowsocks destination address; application bytes follow immediately after it.

This means the target is authenticated by the same AEAD stream as the application data. There is no separate SOCKS-style request/reply exchange.

### Client-to-server example shape

```text
TCP connect to SS server
  ↓
salt
  ↓
AEAD record containing:
    ATYP | DST.ADDR | DST.PORT | early application bytes ...
  ↓
more AEAD records
```

### Server-to-client direction

The response direction creates its own random salt and its own nonce sequence. It carries only relayed application bytes; there is no success reply containing a bound address.

## Classic AEAD UDP Wire Format

Each UDP datagram is independently encrypted:

```text
+----------------------+  salt_len
| random salt          |
+----------------------+
| encrypted plaintext  |
|   ATYP                |
|   DST.ADDR            |
|   DST.PORT            |
|   UDP payload         |
+----------------------+
| AEAD tag              | 16 bytes
+----------------------+
```

The server response uses the same structure, but the address identifies the remote source endpoint corresponding to the returned payload.

Because each packet contains a fresh salt and complete destination tuple, classic Shadowsocks UDP is packet-oriented. It does not use SOCKS5's UDP `RSV | FRAG | ATYP ...` header and has no SOCKS5 `FRAG` semantics.

The current Server also rejects a recently reused classic UDP salt, providing a bounded replay check.

## Shadowsocks 2022 Key Material

A Shadowsocks 2022 method name begins with `2022-blake3-`. In the current Server, the configured password field for such a user is interpreted as a Base64-encoded raw pre-shared key rather than an arbitrary password phrase.

The decoded key length must exactly match the selected cipher key size.

Current Server method paths include:

- `2022-blake3-aes-128-gcm`;
- `2022-blake3-aes-256-gcm`;
- `2022-blake3-chacha20-ietf-poly1305`.

Session subkeys are derived with BLAKE3's derive-key mode using the context string `shadowsocks 2022 session subkey` over `PSK || salt/session-id material`.

## Shadowsocks 2022 TCP Request

The current Server decodes the client direction in these stages:

```text
salt
  ↓
AEAD fixed request header
  type      : u8 = 0
  timestamp : u64 BE
  var_len   : u16 BE
  + 16-byte tag
  ↓
AEAD variable request header[var_len]
  + 16-byte tag
  ↓
AEAD length/payload records ...
```

The variable request header is emitted into the plaintext stream and begins with the destination address. Chimera then reads:

```text
ATYP | DST.ADDR | DST.PORT | padding_len:u16 | padding | optional early data
```

The current Server allows at most 900 bytes of this post-address padding and rejects invalid or truncated values.

The variable-header ciphertext length itself is bounded to 18 KiB by the current implementation.

### Timestamp and replay checks

The Server validates the 2022 timestamp against its local clock and keeps a timed salt replay cache. A valid AEAD tag is therefore insufficient on its own: stale/future timestamps or recently reused salts can still cause the request to be rejected.

Clock synchronization matters more for Shadowsocks 2022 than for classic AEAD.

## Shadowsocks 2022 TCP Response

After validating the request salt, the Server creates a distinct response salt. Its first protected response header contains:

```text
type         : u8 = 1
timestamp    : u64 BE
request_salt : original client request salt
first_len    : u16 BE
```

That header is AEAD-protected, followed by the separately protected first response payload. Later application bytes use the normal encrypted length + payload record sequence.

Binding the original request salt into the response header lets the client associate the response with the validated request direction.

The current 2022 stream path allows payload records up to `0xffff` bytes.

## AEAD-2022 Multi-user Identity / EIH

The current Server supports an identity-header path for multi-user Shadowsocks 2022 with AES methods.

Important constraints in the current implementation are:

- the identity method must be `2022-blake3-aes-128-gcm` or `2022-blake3-aes-256-gcm`;
- users behind an identity must use the same AES method;
- multi-user AEAD-2022 without an identity is rejected;
- the identity layer derives a BLAKE3 identity subkey and decrypts a 16-byte user hash to select the actual user PSK.

Conceptually, EIH adds a user-selection layer before the selected user's normal 2022 session keys are used. It should not be described as a SOCKS username/password negotiation.

## Shadowsocks 2022 UDP: AES Variant

For the current Server AES-2022 path, the datagram starts with a 16-byte separately encrypted header:

```text
AES block under PSK:
    session_id : 8 bytes
    packet_id  : u64 BE
```

The decrypted values are then used to derive the UDP session key. The remaining AEAD body contains, for a client request:

```text
type        : u8 = 0
timestamp   : u64 BE
padding_len : u16 BE
padding
ATYP | DST.ADDR | DST.PORT
payload
TAG : 16 bytes
```

A server response uses its own server session ID and packet ID and includes the client session ID in the protected body so the peer can correlate the direction.

## Shadowsocks 2022 UDP: ChaCha Variant

The current Server's 2022 ChaCha UDP path uses a 24-byte XChaCha20-Poly1305 nonce prefix. The protected client body contains:

```text
client_session_id : 8 bytes
packet_id         : u64 BE
type              : u8 = 0
timestamp         : u64 BE
padding_len       : u16 BE
padding
ATYP | DST.ADDR | DST.PORT
payload
TAG
```

The response body carries the server session ID and packet ID, response type, timestamp, client session ID, padding length, source address, and payload.

This is one reason not to document “Shadowsocks UDP” as one universal packet layout: classic AEAD and AEAD-2022, and even the AES/ChaCha 2022 paths, differ materially.

## UDP Replay Window in Current Chimera_Server

The Server tracks AEAD-2022 UDP packets by session ID and packet ID. The current replay state:

- rejects an already-seen packet ID;
- rejects packet IDs that fall more than 1024 behind the highest accepted ID;
- expires inactive replay sessions on the same roughly one-minute time scale used by the current salt cache.

This is protocol-level anti-replay state. It is separate from operating-system UDP NAT/session timeouts.

## TCP Close and Error Behavior

Shadowsocks does not define a SOCKS5-style `REP` status byte after the destination request. Errors therefore surface differently:

- invalid password/key material usually manifests as AEAD authentication failure;
- a replayed salt/session packet is rejected locally;
- malformed address or length fields terminate the affected stream/datagram;
- target connection failure closes the relayed stream rather than returning a SOCKS5 connection-status frame;
- normal TCP EOF propagates through the encrypted stream shutdown.

Applications using a local SOCKS5 listener may still receive a SOCKS-layer failure from `Chimera_Client`, but that is generated by the local inbound and is not a Shadowsocks wire reply from the remote server.

## State Machine

A simplified classic TCP state machine is:

```text
TCP_CONNECTED
    |
    v
READ_SALT
    |
    v
DERIVE_SESSION_KEY
    |
    v
DECRYPT_RECORD_LENGTH
    |
    v
DECRYPT_FIRST_PAYLOAD
    |
    +--> parse destination
    |
    v
CONNECT_TARGET
    |
    v
RELAY_AEAD_RECORDS
    |
    v
EOF / ERROR
```

For Shadowsocks 2022, insert `VALIDATE_TIMESTAMP`, `CHECK_REPLAY`, and request-header parsing before destination dispatch.

## Packet-capture Anchors

Without keys, an on-path capture normally exposes only outer transport metadata:

- TCP or UDP server endpoint;
- direction, timing, and encrypted record/datagram sizes;
- random-looking salt/nonce prefixes;
- plugin/TLS/WebSocket metadata if an optional outer plugin is used.

With keys and an implementation-aware decoder, useful anchors are:

- classic TCP: `salt | encrypted length+tag | encrypted payload+tag`;
- classic UDP: `salt | encrypted address+payload+tag`;
- 2022 TCP: salt followed by fixed/variable authenticated headers;
- 2022 UDP: session ID / packet ID / timestamp and address fields after successful decryption.

A capture cannot identify the target address from ciphertext alone under a working AEAD cipher.

## SIP003 Plugins

`Chimera_Client` supports a plugin hook around the raw stream before the Shadowsocks protocol stream is created. The repository contains paths for plugin-style transports such as simple-obfs and v2ray-plugin/WebSocket when the needed build features are present.

Layering is conceptually:

```text
TCP
  ↓
optional SIP003 plugin transport
  ↓
Shadowsocks encrypted stream
  ↓
destination + payload
```

The remote side must run the matching plugin layer. Pointing a plugin-wrapped client directly at a plain Shadowsocks server makes the server see plugin bytes where it expects a Shadowsocks salt/record.

## Current Chimera_Client Implementation

The Client implementation is behind the `shadowsocks` Cargo feature and currently has:

- outbound TCP through `ProxyClientStream`;
- outbound UDP through `ProxySocket`;
- Shadowsocks inbound TCP/UDP modules;
- configurable `cipher`, `password`, `udp`, `plugin`, and `plugin-opts`;
- integration tests for TCP, UDP, multi-target UDP, and UDP session isolation.

The current outbound cipher mapper accepts:

```text
aes-128-gcm
aes-256-gcm
chacha20-ietf-poly1305
xchacha20-ietf-poly1305
2022-blake3-aes-128-gcm
2022-blake3-aes-256-gcm
2022-blake3-chacha20-ietf-poly1305
rc4-md5
```

That list is a Client implementation fact, not a promise that every method is accepted by `Chimera_Server`.

## Current Chimera_Server Implementation

The Server has inbound TCP and UDP Shadowsocks paths behind its `shadowsocks` feature, which is included in the current default `full` build.

Notable current boundaries include:

- at least one user is required for TCP;
- classic AES-128-GCM, AES-256-GCM, and ChaCha20-Poly1305 are implemented;
- AEAD-2022 AES and ChaCha paths are implemented;
- classic `xchacha20-poly1305` is explicitly rejected;
- AEAD-2022 multi-user requires the AES EIH identity path;
- user `level` compatibility fields are not treated as implemented runtime policy;
- replay caches and timestamp validation are active security behavior, not parser-only fields.

See [Implementation Status and Source Evidence](../implementation-status.md) for the cross-project matrix.

## SOCKS5 Phase-by-phase Comparison

| Phase | SOCKS5 | Shadowsocks | Relationship |
| --- | --- | --- | --- |
| Transport connect | TCP to SOCKS server | TCP or UDP to SS server | Conceptually same lower-layer reachability step |
| Method negotiation | `VER, NMETHODS, METHODS` | None | Replaced by preconfigured cipher/key |
| Username/password auth | Optional RFC 1929 exchange | No username/password subnegotiation; key possession authenticates/decrypts | Replaced |
| Destination request | `VER, CMD, RSV, ATYP, DST` | Address tuple embedded in decrypted plaintext | Same destination concept, different framing |
| Success reply | `VER, REP, RSV, BND` | No equivalent protocol reply | Removed |
| TCP data | Plain bytes after SOCKS handshake | AEAD length/payload records | Extra encryption/record layer |
| UDP control | `UDP ASSOCIATE` over TCP | No equivalent control negotiation in classic SS | Replaced |
| UDP packet | `RSV, FRAG, ATYP, DST, DATA` | Encrypted address + payload; AEAD-2022 adds session/packet metadata | Same routing purpose, different wire format |
| Fragmentation | SOCKS5 `FRAG` field exists | No SOCKS5-style fragmentation field | Removed |
| Replay defense | Not provided by SOCKS5 | Salt/session/timestamp replay checks depending on SS generation | Extra security layer |
| Close/error | SOCKS `REP` during setup, then TCP/UDP semantics | AEAD/parser/target failure usually closes or drops affected traffic | Replaced |

## Security Notes

- Prefer modern AEAD or AEAD-2022 methods; legacy ciphers exist for compatibility and should not be treated as equivalent security choices.
- Protect Shadowsocks passwords/PSKs as credentials. For AEAD-2022 the Base64 string represents raw key material in the current Server configuration path.
- Reusing salts/nonces or disabling replay checks can destroy the assumptions of the AEAD construction.
- Keep system clocks reasonably synchronized for AEAD-2022 timestamp validation.
- A plugin can camouflage or reshape transport traffic, but it does not replace correct Shadowsocks authentication and AEAD validation.
- Do not expose Client-only cipher support as a Server compatibility claim.

## Troubleshooting

When a Shadowsocks connection fails, check in this order:

1. confirm the client and server agree on classic AEAD versus `2022-blake3-*`;
2. confirm the exact cipher name and key length;
3. for 2022, confirm the configured value is the expected Base64 raw key and clocks are synchronized;
4. confirm any SIP003 plugin exists on both sides with matching options;
5. verify TCP versus UDP is enabled in the actual Client build/config;
6. inspect logs for tag failure, replay rejection, timestamp failure, unknown EIH user, or unsupported cipher;
7. only after the cryptographic layer succeeds, debug destination DNS/routing/target reachability.

## Source Anchors

Current Chimera implementation details in this chapter are grounded in:

- `Chimera_Client/clash-lib/src/proxy/shadowsocks/`;
- `Chimera_Client/clash-lib/src/config/internal/proxy.rs`;
- `Chimera_Client/clash-lib/tests/shadowsocks_integration_tests.rs`;
- `Chimera_Server/chimera_server_lib/src/handler/shadowsocks.rs`;
- `Chimera_Server/chimera_server_lib/src/beginning/udp.rs`;
- `Chimera_Server/chimera_server_lib/src/config/server_config/`.

For portable protocol behavior, compare the relevant Shadowsocks specification/SIP with the version implemented by the selected peer rather than assuming all Shadowsocks generations share one wire format.
