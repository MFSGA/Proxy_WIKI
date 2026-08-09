# REALITY

## Positioning

REALITY is an Xray transport-security mechanism. It is not a standalone proxy
protocol: it protects and camouflages a supported transport while the actual
proxy protocol can be VLESS, Trojan, or another compatible Xray inbound/outbound
combination.

Current Xray documentation describes REALITY as a modified TLS design that
borrows the appearance and handshake characteristics of a target site. In the
current Xray transport matrix, REALITY is used with `RAW`, XHTTP, or gRPC.

A useful mental model is:

```text
VLESS / Trojan / ...   -> proxy protocol
RAW / XHTTP / gRPC     -> transport method
REALITY                 -> transport security
```

## Main Configuration Concepts

A REALITY deployment commonly includes:

- a server-side X25519 private key,
- the corresponding client-side X25519 public value, called `password` in
  current Xray configuration (`publicKey` is the older field name),
- one or more short IDs,
- one or more permitted server names,
- a target site/address used for handshake appearance and fallback behavior,
- and a client TLS fingerprint setting in implementations that expose uTLS-like
  fingerprint controls.

Current Xray can additionally configure an ML-DSA-65 signing key on the server
and verification key on the client. This is an optional extra certificate
verification layer; it does not replace the base REALITY X25519 key relation or
the ClientHello authentication described below.

These pieces belong to the same security configuration and must be kept
consistent.

## Connection Flow

At a high level:

1. The client connects to the REALITY-enabled endpoint.
2. The client begins a TLS-like handshake using the configured server name and
   client fingerprint behavior.
3. The REALITY endpoint validates the handshake using its key material and the
   supplied short ID/security parameters.
4. If validation succeeds, the underlying proxy transport proceeds.
5. If traffic is not accepted as a valid REALITY session, Xray can forward it
   toward the configured target instead of returning a proxy-specific response.

The target therefore participates in both camouflage and fallback behavior and
must be chosen deliberately.

## Handshake Internals and On-Wire Authentication

REALITY deliberately keeps its authentication inside a TLS-looking ClientHello
instead of adding a SOCKS-like method negotiation or a VLESS-like plaintext
identity header before TLS. This means the first bytes visible to a passive
observer are ordinary TLS record/handshake bytes; the REALITY-specific
credentials are embedded into fields of the generated ClientHello and protected
with keys derived for that handshake.

A useful client-side state machine is:

```text
TCP connection
    |
    v
Build uTLS ClientHello from selected fingerprint
    |
    +-- choose SNI/serverName
    +-- create TLS 1.3 ephemeral key share
    +-- allocate 32-byte legacy Session ID
    |
    v
Derive REALITY authentication key
    |
    v
Encode + protect REALITY metadata in ClientHello Session ID
    |
    v
Send TLS ClientHello
    |
    v
Receive TLS-looking ServerHello / certificate flight
    |
    +-- REALITY temporary certificate verifies -> proxy transport continues
    +-- genuine target certificate -> not an authenticated REALITY session
    +-- invalid certificate/authentication -> abort
```

The current Xray-core client constructs a 32-byte ClientHello legacy Session ID.
Before protection, the first 16 bytes carry REALITY metadata with this logical
layout:

```text
byte 0       client major version
byte 1       client minor version
byte 2       client patch version
byte 3       reserved (0)
bytes 4..7   Unix timestamp, uint32 big-endian
bytes 8..15  short ID, padded to 8 bytes when shorter
```

The remaining 16 bytes of the 32-byte Session ID are used by the AEAD result.
This is an implementation-level wire detail, not a new TLS extension: REALITY
reuses the TLS ClientHello Session ID field so that the outer message still has
the shape of a normal TLS handshake.

### Key derivation

The client already has the server REALITY public key. During construction of the
TLS 1.3 ClientHello it also owns the private side of its ephemeral key share.
Current Xray-core computes an X25519 ECDH result between that ephemeral key and
the configured REALITY public key, then expands it with HKDF-SHA256 using:

```text
IKM  = ECDH(client ephemeral private key, REALITY server public key)
salt = ClientHello.random[0..20]
info = "REALITY"
```

The resulting authentication key is used with an AEAD cipher. Current code uses
the last 12 bytes of the ClientHello random (`random[20..32]`) as the nonce and
the serialized ClientHello as associated data while sealing the first 16 bytes
of REALITY Session-ID metadata. The protected 32-byte value is then written back
into the fixed Session ID location of the ClientHello.

This explains why REALITY authentication is bound to the concrete TLS handshake:
a copied Session ID is not an independently reusable password token. The
ClientHello random, ephemeral key share, serialized hello, server key, timestamp,
and short ID all participate directly or indirectly in validation.

### Server-side decision path

Conceptually the REALITY listener has to make a decision before handing the
connection to the proxy protocol:

```text
read TLS ClientHello
      |
      v
obtain client key share + ClientHello random
      |
      v
ECDH with REALITY server private key
      |
      v
HKDF -> authentication key
      |
      v
open protected Session-ID metadata
      |
      +-- version/time/short-ID/serverName accepted?
      |       |
      |       +-- yes -> complete authenticated REALITY TLS path
      |       |          -> expose decrypted transport to VLESS/Trojan/...
      |       |
      |       +-- no ----+
      |
      v
forward/fallback toward configured target according to implementation policy
```

`serverNames` and short IDs are therefore authentication/selection inputs at the
REALITY layer. A VLESS UUID is checked later, by VLESS, after REALITY has
successfully produced the protected transport. Keeping these checks separate is
important when diagnosing failures.

### Certificate result and client verification state machine

The protected Session ID authenticates the ClientHello to the REALITY server,
but the client also has to authenticate the server-side REALITY result. Current
Xray does that through the certificate flight rather than by expecting an
ordinary CA-issued certificate for the REALITY endpoint.

The client can conceptually reach three certificate outcomes:

```text
receive certificate flight
        |
        +-- REALITY temporary certificate
        |      |
        |      +-- HMAC/auth-key check succeeds
        |      +-- optional ML-DSA-65 verification succeeds
        |      `--> Verified=true -> continue proxy transport
        |
        +-- genuine target certificate
        |      |
        |      +-- normal X.509 verification for serverName succeeds
        |      `--> not REALITY-authenticated -> crawler/spider path
        |
        `-- neither verification path succeeds
               `--> TLS verification error / alert / disconnect
```

In the current Xray client implementation, a REALITY temporary certificate is
recognized through an Ed25519 public key and an HMAC-SHA512 value derived from
the connection's REALITY `AuthKey`. When configured, `mldsa65Verify` adds an
ML-DSA-65 verification step tied to the handshake transcript before the client
sets its internal `Verified` flag. This certificate is therefore bound to the
same handshake-derived authentication material as the protected ClientHello; it
is not a reusable conventional server certificate.

If the certificate instead validates as the genuine target site's normal X.509
certificate, the TLS certificate itself can be valid while REALITY
`Verified=false`. That state means the client reached the target/fallback path
(or was redirected there) rather than the authenticated proxy path. Current
REALITY documentation describes this as entering the crawler/spider behavior.
An invalid certificate that satisfies neither path terminates the handshake.

This three-way distinction is useful during packet-level debugging: "valid TLS
certificate" and "valid REALITY connection" are not equivalent states.

## Packet-Capture View

Without TLS key material, a normal capture should look approximately like:

```text
TCP SYN / SYN-ACK / ACK
TLS record: ClientHello
  SNI = configured serverName
  fingerprint-dependent cipher/extensions/key_share
  legacy_session_id = 32 bytes (contains protected REALITY metadata)
TLS-looking server handshake records
TLS application-data records
```

A packet capture cannot identify the VLESS UUID or VLESS destination merely by
seeing the REALITY ClientHello. Those values are inside the protected transport
and belong to the next protocol layer.

Do not assume one TCP segment contains one ClientHello. TLS handshake bytes may
span TCP segments, and newer fingerprints can produce larger ClientHello
messages. A server implementation must parse a byte stream and TLS lengths,
not depend on packet boundaries or a single `read()` call.

## REALITY vs SOCKS5: Layer-by-Layer Comparison

SOCKS5 and REALITY are intentionally different layers. The comparison is useful
mainly to show which SOCKS5 responsibilities REALITY does **not** replace:

| Stage / responsibility | SOCKS5 | REALITY |
| --- | --- | --- |
| Underlying connection | TCP to SOCKS server | Usually TCP to Xray/REALITY listener |
| First protocol message | SOCKS method list | TLS/uTLS ClientHello |
| Authentication placement | Separate METHOD/auth sub-protocol | Protected metadata inside TLS-looking ClientHello |
| Credential form | Method-specific; e.g. username/password | Server public/private key relation + short ID + handshake-derived authentication |
| Target proxy address | `CMD + ATYP + DST.ADDR + DST.PORT` | **Not carried by REALITY**; supplied later by VLESS/Trojan/etc. |
| Proxy success reply | SOCKS `REP` | No SOCKS-equivalent proxy reply; REALITY establishes/rejects the security layer |
| TCP relay framing | Raw stream after `REP=0x00` | Defined by the underlying proxy/transport after REALITY succeeds |
| UDP association | RFC 1928 `UDP ASSOCIATE` | Not defined by REALITY |
| Encryption | None in base SOCKS5 | TLS-shaped encrypted transport/security layer |
| Camouflage/fallback | None in base SOCKS5 | Invalid/non-REALITY traffic can be directed toward the configured target |

For `VLESS + REALITY + RAW`, the closest functional mapping is therefore:

```text
SOCKS5 METHOD/auth       ~= REALITY handshake authentication
SOCKS5 CONNECT request   ~= VLESS request header (not REALITY)
SOCKS5 REP               ~= VLESS/transport success or failure behavior
SOCKS5 raw relay         ~= VLESS body over the REALITY-protected connection
```

This layered mapping prevents a common documentation error: describing the
REALITY short ID as if it were a replacement for a VLESS UUID, or describing
REALITY as if it encoded the destination address. It does neither.

## Parser, Timing, and Boundary Conditions

- Treat ClientHello as a length-delimited TLS handshake carried over a TCP byte
  stream; never assume TCP packet boundaries are message boundaries.
- Validate timestamp freshness with the implementation's accepted clock window.
  `maxTimeDiff` is expressed in milliseconds; large client/server clock skew can
  make otherwise correct key material fail when a non-zero limit is enforced.
- The 8-byte short-ID slot is configured as hexadecimal text. Current Xray
  accepts at most 16 hex characters, requires an even number of characters, and
  pads shorter values with trailing zero bytes. An empty client short ID is only
  valid when the server explicitly accepts an empty entry.
- `minClientVer` and `maxClientVer`, when configured, add version checks to the
  REALITY authentication decision. They are separate from the inner VLESS
  protocol version byte.
- A fingerprint must provide a TLS 1.3-capable key share. Current Xray-core
  rejects fingerprints that cannot supply the required ephemeral ECDH material.
- Authentication failure and target fallback are not equivalent to successful
  proxy authentication. Seeing the target site's genuine certificate is a
  strong clue that the connection did not enter the authenticated REALITY path.
- A server can accept a no-SNI ClientHello by including an empty string in
  `serverNames`. Current Xray's client-side configuration uses a valid IP string
  as the `serverName` placeholder to request this mode; packet analysis should
  therefore not assume an SNI extension is always present.
- The TLS/uTLS implementation, REALITY implementation, target behavior, and peer
  version form one interoperability surface. Changes to ClientHello construction
  or the target site's TLS behavior can affect REALITY even when VLESS
  configuration is unchanged.

### Post-quantum additions in current Xray

Current Xray can use the hybrid `X25519MLKEM768` TLS key-exchange group when the
selected target supports it. This belongs to the TLS key-exchange portion of the
REALITY handshake and is negotiated based on current client/target capability;
it does not add a SOCKS-like command or a new proxy destination field.

Separately, `mldsa65Seed` on the server and `mldsa65Verify` on the client add an
ML-DSA-65 signature check to the temporary REALITY certificate. Because the
post-quantum signature enlarges that certificate, the official configuration
guidance warns that the selected target should itself return a sufficiently
large certificate so the REALITY certificate flight does not become an obvious
size fingerprint.

These are optional hardening/interoperability features. A parser or diagnostic
tool should report whether hybrid key exchange and ML-DSA verification were
actually negotiated rather than assuming their presence from the word
"REALITY" alone.

## Key Material

REALITY uses an X25519 server private key and the corresponding public value on
the client. Current Xray names that client field `password`; `publicKey` is the
older alias. The rename is operationally important: although the value is an
X25519 public key mathematically, REALITY treats it as client-held connection
credential material rather than as something to publish indiscriminately.

Do not place a server private key in client profiles, screenshots, issue
reports, or public documentation examples. Treat the client `password` value as
sensitive deployment material as well, even though it is derived from the
server's public key.

For Chimera_Server, the current Wiki documents an `x25519` helper in
`chimera_cli` for generating compatible key material.

## Short IDs

Short IDs add another server-validated value to REALITY sessions. A server can
accept one or more values, while a client selects a matching value.

At the current Xray configuration boundary a short ID is 0 to 8 bytes, encoded
as 0 to 16 hexadecimal characters. Its textual length must be even; shorter
values are padded with zero bytes to fill the 8-byte Session-ID metadata slot.
This is why a value such as `aa1234` is valid while an odd-length hexadecimal
string is rejected.

Treat short IDs as configuration/security material rather than decorative
labels. Client and server must use compatible values and formatting.

## Target and Server Names

The server-side `target` identifies the service whose TLS-facing behavior is
used as part of the REALITY design and also receives traffic that does not pass
REALITY authentication in the current Xray model.

`serverNames` restrict which client server-name values are accepted.

A practical target should:

- be reachable reliably from the server,
- provide a TLS behavior compatible with the intended setup,
- not expose sensitive internal infrastructure,
- and not create an undesirable open-forwarding path.

Current Xray documentation explicitly warns that a poorly chosen target can
turn the REALITY server into an unintended forwarder for traffic that fails
authentication. Current releases provide optional `limitFallbackUpload` and
`limitFallbackDownload` token-bucket controls for unauthenticated fallback
traffic, but the official guidance also notes that deterministic fallback rate
limits can themselves become a fingerprint. They are an abuse-control tradeoff,
not part of REALITY authentication.

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
          { "id": "11111111-2222-3333-4444-555555555555" }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "raw",
        "security": "reality",
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

The example is intentionally minimal. Use real generated key material and a
server/target combination appropriate for the deployment.

## Conceptual Client Example

```yaml
proxies:
  - name: reality-example
    type: vless
    server: proxy.example.com
    port: 443
    uuid: 11111111-2222-3333-4444-555555555555
    network: tcp
    tls: true
    servername: example.com
    reality-opts:
      public-key: CLIENT-PUBLIC-KEY
      short-id: 0123456789abcdef
```

Clash-family names are not the same as native Xray JSON field names. The
selected core's schema is authoritative.

## REALITY vs TLS

Both REALITY and ordinary TLS occupy the transport-security layer, but their
operational models differ.

### Ordinary TLS

- Uses a certificate chain presented by the server.
- Normally requires certificate issuance/renewal.
- Client trust follows normal TLS certificate verification.

### REALITY

- Uses REALITY key material and target-site handshake behavior.
- Does not use the deployment's own conventional public certificate in the same
  way as a normal TLS server.
- Relies on client/server REALITY compatibility and correct fingerprint/target
  behavior.

Do not describe REALITY simply as "TLS without a certificate"; that hides the
key validation, target forwarding, and implementation-specific handshake logic
that actually define the deployment.

## Strengths

- Avoids operating a conventional certificate for the REALITY endpoint itself.
- Integrates with Xray's supported proxy and transport combinations.
- Unauthenticated traffic can follow a normal target-service path instead of a
  bespoke proxy response.
- Commonly paired with VLESS and XTLS Vision in modern Xray deployments.

## Limitations

- Primarily an Xray-ecosystem mechanism rather than a general Internet standard.
- Client fingerprint and server target behavior must be compatible.
- A bad target choice can create reliability or abuse problems.
- Configuration has more moving parts than normal certificate-based TLS.
- Transport support is constrained by the selected Xray/core version.

## Security Notes

- Never expose the REALITY server private key.
- Keep public/private key pairs synchronized during rotation.
- Use controlled short IDs and remove values no longer needed.
- Do not set a sensitive private endpoint as the fallback target.
- Treat `allowInsecure`/certificate-style bypass options in surrounding
  transports as debugging tools, not production defaults.
- Keep client fingerprint selection realistic and supported by the actual core.

## Chimera Status

### Chimera_Client

The current client overview lists **Reality + TCP** as a supported combination.
In current upstream Xray terminology, the corresponding base transport is often
called `RAW`; Clash-family configurations may still expose it as `tcp`. This is
a naming difference that should be accounted for when translating profiles.

The exact supported proxy protocol underneath REALITY should be verified in the
current `Chimera_Client` implementation instead of assuming complete Xray
compatibility from the transport alone.

### Chimera GUI

Chimera manages the profile and selected core. REALITY key/fingerprint fields
must be emitted in the schema expected by that core.

### Chimera_Server

The server documentation includes a VLESS + REALITY example and an X25519 key
helper. This makes REALITY an important server target, but transport combinations
and Xray-version compatibility should still be tested explicitly.

## Troubleshooting

### Immediate handshake failure

1. Verify server public/private key pairing.
2. Check the short ID.
3. Verify the client server name is permitted by `serverNames`.
4. Confirm the target is reachable from the server.
5. Check client fingerprint support.

### Target site works but proxy does not

This often means the public listener and fallback path are reachable while the
REALITY authentication path is failing. Re-check keys, short ID, server name,
proxy user identity, and transport method.

### Works in Xray but not another core

1. Compare accepted field names.
2. Confirm the core supports the same proxy + transport + REALITY combination.
3. Check whether `tcp` and `raw` are translated correctly.
4. Remove optional Vision/XMUX/XHTTP tuning until the base handshake works.

## References

- Xray REALITY configuration:
  <https://xtls.github.io/en/config/transports/reality.html>
- Xray-core REALITY client implementation:
  <https://github.com/XTLS/Xray-core/blob/main/transport/internet/reality/reality.go>
- XTLS/REALITY server implementation and protocol notes:
  <https://github.com/XTLS/REALITY>
- Xray transport compatibility:
  <https://xtls.github.io/en/config/transport.html>
