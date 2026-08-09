# XHTTP Transport

## Positioning

XHTTP is an Xray transport method used to carry proxy traffic through
HTTP-shaped request/response flows. It belongs to the transport layer, not the
proxy-protocol layer.

A typical deployment combines:

```text
VLESS                 -> proxy protocol
XHTTP                 -> transport method
TLS or REALITY        -> transport security
```

Current Xray transport documentation allows XHTTP to be combined with ordinary
TLS or REALITY. The exact HTTP behavior and tuning options have evolved over
time, so the selected core version should be treated as the source of truth.

## Why XHTTP Exists

Long-lived raw TCP, WebSocket, and gRPC connections have different network
signatures and operational constraints. XHTTP provides another way to express
uplink and downlink traffic using HTTP-like exchanges and connection reuse.

Typical reasons to evaluate XHTTP include:

- deployment behind HTTP-aware infrastructure,
- environments where WebSocket/gRPC behavior is unreliable,
- separate control over upload/download request patterns,
- and compatibility with Xray's TLS/REALITY transport-security layer.

It should not be described simply as "HTTP proxying". A local HTTP proxy and an
XHTTP transport solve different problems.

## Layer Model

```text
Local application
      │
      ▼
Client proxy protocol (for example VLESS)
      │
      ▼
XHTTP transport
      │
      ▼
TLS or REALITY
      │
      ▼
HTTP-capable path / reverse proxy / direct server
      │
      ▼
XHTTP server transport
      │
      ▼
Server proxy protocol
```

Both endpoints must agree on the XHTTP transport settings that affect request
routing and stream interpretation.

## Core Fields

The current Xray implementation exposes a broad XHTTP configuration surface.
For documentation and initial deployment, focus on the small set of fields that
are essential to establish a connection:

| Field | Purpose |
| --- | --- |
| `path` | HTTP request path used by the XHTTP endpoint |
| `host` | Optional HTTP Host value / virtual-host selection |
| `mode` | XHTTP upload/download behavior; `auto` is a common starting point |
| `headers` / extra headers | Optional HTTP metadata depending on implementation/version |
| `xmux` | Connection/request reuse and concurrency tuning |
| `downloadSettings` | Advanced split upload/download routing in newer Xray versions |

Advanced fields controlling padding, request chunking, session placement, and
connection reuse exist in current Xray code. Avoid copying large tuning blocks
from random examples before the minimal path works.

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
        "network": "xhttp",
        "security": "tls",
        "tlsSettings": {
          "serverName": "proxy.example.com",
          "certificates": [
            {
              "certificateFile": "/etc/ssl/fullchain.pem",
              "keyFile": "/etc/ssl/privkey.pem"
            }
          ]
        },
        "xhttpSettings": {
          "path": "/api/sync",
          "mode": "auto"
        }
      }
    }
  ]
}
```

For REALITY, replace the TLS security block with a compatible REALITY block and
ensure the selected Xray/core version supports that transport/security
combination.

## Conceptual Clash-Family Client Example

```yaml
proxies:
  - name: vless-xhttp
    type: vless
    server: proxy.example.com
    port: 443
    uuid: 11111111-2222-3333-4444-555555555555
    network: xhttp
    tls: true
    servername: proxy.example.com
    xhttp-opts:
      path: /api/sync
      mode: auto
```

Field names such as `xhttp-opts` are frontend/core specific. Native Xray JSON,
Mihomo, ClashRS, and `chimera_client` may expose different schemas.

## `path`

The path is one of the most important interoperability fields.

Client and server need compatible path handling. If a reverse proxy is present,
it must route that path to the XHTTP backend without accidentally serving a
normal website response instead.

Use a deliberate path and document it. Do not reuse a sensitive application
endpoint merely to make the traffic appear more realistic.

## `host`

`host` can participate in virtual-host routing through Nginx, Caddy, a CDN, or
another HTTP-aware frontend.

When a reverse proxy chooses an upstream based on `Host`, a missing or
mismatched value can produce a perfectly valid HTTP response from the wrong
virtual host, which may look like a proxy protocol failure.

## `mode`

XHTTP has multiple transport modes in current Xray implementations. `auto` is a
reasonable baseline because it allows the core to choose compatible behavior
without forcing a specialized upload strategy.

Only force a specific mode when:

- both client and server versions support it,
- the HTTP version/path is understood,
- and you have a concrete reason such as CDN behavior or upstream limitations.

Mode tuning should come after basic connectivity.

## Wire-Level Session Model

XHTTP is unusual compared with SOCKS5 because the transport itself does not
carry a single fixed binary `CONNECT` request. The proxy protocol (for example
VLESS) produces an ordered byte stream, and XHTTP maps that byte stream onto
one or more HTTP requests and responses.

At the server, current Xray-core reconstructs a connection roughly as follows:

```text
HTTP request metadata
        │
        ├── path / Host validation
        ├── optional Session ID
        └── optional upload sequence number
                │
                ▼
        per-session upload queue
                │
                ▼
        reconstructed byte stream
                │
                ▼
        VLESS / Trojan / other proxy parser
```

This distinction is fundamental: a VLESS request header can be split across
multiple XHTTP upload requests. Conversely, one HTTP upload request can contain
the VLESS header plus application payload. The proxy parser therefore must not
use HTTP request boundaries as proxy-message boundaries.

### Session creation and lifetime

For split modes, current Xray-core indexes server-side state by a Session ID.
The first request that references an unknown Session ID creates an
`httpSession` containing an upload queue. A newly created session has a
30-second provisional lifetime while the downlink side has not connected. Once
the downlink GET is established, that provisional reap is cancelled; the
session then lives with the downlink request and is deleted when that request
finishes.

Conceptually:

```text
unknown Session ID
       │
       ▼
create upload queue
       │
       ├── no downlink within provisional TTL -> delete session
       │
       └── downlink attached
                 │
                 ▼
          full duplex logical stream
                 │
                 ▼
          downlink ends -> delete session
```

The Session ID is therefore an XHTTP transport identifier. It is not the VLESS
UUID, not a SOCKS5 authentication identity, and not the destination address.

## Current Transport Modes

Current Xray-core distinguishes three important data-shaping models.

### `stream-one`

`stream-one` keeps uplink and downlink on one HTTP exchange. There is no split
Session ID in the normal path: the request body is the reconstructed upstream
reader and the response body is the downstream writer.

```text
client                           server
  |                                |
  | HTTP request body -----------> | upstream bytes
  | <----------- HTTP response body| downstream bytes
  |                                |
```

This is the closest XHTTP mode to a conventional full-duplex stream, although
actual duplex behavior still depends on the HTTP version and intermediaries.

### `stream-up`

`stream-up` separates a long-lived upload request from the downlink request.
The upload request body is pushed into the session's upload queue as a reader,
while a GET-like downlink response carries server-to-client bytes.

```text
                 Session ID = S
client                                 server
  |                                      |
  | upload request(S), streaming body -> |--+
  |                                      |  | upload queue
  | GET/downlink(S) -------------------> |<-+
  | <=========== response body ==========|
```

The server currently rejects a split streaming upload when an explicitly
configured mode does not permit `stream-up`.

### `packet-up`

`packet-up` slices upstream bytes into independently delivered HTTP requests.
Each upload carries the Session ID plus a sequence number. The server parses the
sequence number as an unsigned integer and inserts the payload into the
session's upload queue, which is responsible for restoring byte-stream order.

```text
logical upstream bytes:

AAAA BBBB CCCC DDDD

HTTP transport:

request(S, seq=0, AAAA)
request(S, seq=1, BBBB)
request(S, seq=2, CCCC)
request(S, seq=3, DDDD)

server upload queue:

seq 0 -> seq 1 -> seq 2 -> seq 3 -> reconstructed stream
```

The important implementation consequence is that HTTP request completion order
need not be the proxy-stream order. Sequence metadata, not arrival order, is
the ordering authority.

## Upload Data Placement

In current Xray-core, packet-style uplink data can be transported in the HTTP
body, encoded into numbered HTTP headers, encoded into numbered cookies, or
combined according to the configured automatic placement behavior.

Header and cookie forms use unpadded URL-safe Base64 before the server restores
the original bytes. Body payload is binary data and does not require that
Base64 step.

This means a packet capture may show an apparently empty POST while the actual
proxy bytes are carried in headers or cookies. Troubleshooting should therefore
inspect the configured `uplinkDataPlacement` rather than assuming that all
upstream data is in the HTTP body.

The server also enforces a configured maximum upload size. Oversized request
bodies are rejected with HTTP `413 Request Entity Too Large`; malformed encoded
header/cookie data is rejected as a bad request.

## Server Request State Machine

A useful implementation-oriented server state machine is:

```text
HTTP request arrives
       │
       ▼
validate Host / path
       │ failure -> HTTP 404
       ▼
validate padding / transport metadata
       │ failure -> HTTP 400
       ▼
extract Session ID + sequence
       │
       ├── split streaming upload
       │      -> attach request body to upload queue
       │
       ├── packet upload
       │      -> decode placement
       │      -> validate size
       │      -> parse sequence
       │      -> enqueue payload
       │      -> HTTP 200
       │
       └── downlink or stream-one
              -> HTTP 200 + flush
              -> expose reconstructed connection
              -> proxy-protocol parser consumes bytes
```

A `404`, `400`, `409`, `413`, or `405` seen at this layer is therefore an XHTTP
transport/routing failure and should be diagnosed before changing the VLESS
UUID or destination command.

## Downlink Flow and Buffering

For the downlink response, current Xray-core writes `200 OK`, flushes the
response, and then writes proxy bytes to the HTTP response body. It also sets
`Cache-Control: no-store` and `X-Accel-Buffering: no`; unless disabled, it uses
an SSE-like `Content-Type` to discourage HTTP middleboxes from buffering the
stream.

This is operationally important. A reverse proxy can accept every request and
still break XHTTP if it buffers the response body instead of forwarding chunks
promptly. In that case authentication and routing may be correct while latency
or apparent stalls occur at the HTTP transport layer.

## HTTP/1.1, HTTP/2, and HTTP/3 Boundaries

XHTTP's logical session is above the HTTP transport version:

```text
HTTP/1.1 -> TCP connection(s) -> HTTP requests
HTTP/2   -> TCP connection -> multiplexed HTTP streams
HTTP/3   -> QUIC connection -> multiplexed HTTP streams
```

The current server supports HTTP/1.1 and unencrypted HTTP/2 on its TCP-side HTTP
server; when configured for HTTP/3 it listens on UDP/QUIC and serves HTTP/3.
TLS or REALITY can wrap the TCP-side listener according to stream settings.

Do not confuse HTTP multiplexing with XHTTP/XMUX logical multiplexing. HTTP/2
and HTTP/3 can multiplex HTTP requests on one underlying connection; XHTTP
still has to correlate those requests into the correct reconstructed proxy
stream.

## Packet-Capture View

With TLS, a normal capture primarily exposes:

```text
TCP/IP
  -> TLS records
       -> encrypted HTTP/1.1 or HTTP/2
            -> XHTTP metadata/data
                 -> VLESS bytes
```

For HTTP/3:

```text
UDP/IP
  -> QUIC Initial / Handshake
  -> protected QUIC 1-RTT
       -> HTTP/3 request streams
            -> XHTTP session/sequence metadata
                 -> proxy bytes
```

After TLS/QUIC decryption, debugging proceeds from the outside inward:

1. identify the HTTP request and path,
2. identify Session ID and sequence metadata,
3. determine whether data is in body/header/cookie,
4. reconstruct XHTTP upload ordering,
5. only then parse the inner VLESS/Trojan bytes.

A single HTTP request is not necessarily a single proxy request, and a single
proxy request is not necessarily contained in one HTTP request.

## XHTTP Compared with SOCKS5

The most useful comparison is layer-by-layer rather than treating XHTTP as a
replacement SOCKS protocol.

| Stage | SOCKS5 | VLESS over XHTTP |
| --- | --- | --- |
| Client identity | METHOD/RFC 1929 exchange | VLESS UUID inside reconstructed stream |
| Proxy command | SOCKS `CONNECT` / `UDP ASSOCIATE` | VLESS command inside reconstructed stream |
| Destination | `ATYP + DST.ADDR + DST.PORT` | VLESS `PORT + ATYP + ADDRESS` |
| Transport request | Same SOCKS TCP control connection | One or more HTTP requests |
| Transport session ID | None | XHTTP Session ID in split modes |
| Ordering | TCP byte order | XHTTP sequence metadata + upload queue, then byte order |
| Success at transport layer | SOCKS `REP` | HTTP status such as `200` |
| Proxy-protocol success | SOCKS `REP` | VLESS response header / stream behavior |
| Downlink | Same TCP stream | HTTP response body |
| Multiplexing | Not in base SOCKS5 | HTTP/2/3 plus optional XMUX/XHTTP reuse |
| Encryption | Not provided | TLS or REALITY can protect XHTTP |

The two important separations are:

```text
SOCKS5:
authentication + destination command + relay framing
are one protocol.

VLESS + XHTTP + REALITY:
VLESS   = identity + destination command + proxy semantics
XHTTP   = mapping of proxy bytes onto HTTP requests/responses
REALITY = transport-security authentication/camouflage
```

Therefore an HTTP `200` from XHTTP does **not** mean the requested destination
was accepted in the same sense as SOCKS5 `REP=0x00`. It only means the HTTP
transport request was accepted. The inner proxy protocol can still fail later.

## Ordering, Flow Control, and Backpressure

There are several independent flow-control domains:

1. the application/proxy byte stream,
2. the XHTTP per-session upload queue,
3. HTTP request/stream flow control,
4. TCP flow control for HTTP/1.1 or HTTP/2,
5. QUIC stream/connection flow control for HTTP/3,
6. reverse-proxy/CDN buffering and request limits.

A stall can occur in any one of these domains. Increasing XMUX concurrency does
not fix a full server upload queue, and increasing HTTP/2 stream concurrency
does not fix a reverse proxy that buffers the downlink.

For packet uploads, bound the number and total size of buffered out-of-order
requests. Otherwise a peer that sends high sequence numbers while withholding
earlier chunks can consume memory without allowing the reconstructed stream to
advance.

## Close and Error Semantics

XHTTP does not have one universal binary close command comparable to an
imaginary SOCKS `CLOSE` command (base SOCKS5 has none either). Lifetime is
expressed through the participating HTTP requests and underlying transport:

- ending the downlink request tears down the associated split session,
- cancelling a streaming upload ends that upload reader,
- HTTP error responses reject malformed or incompatible transport requests,
- TCP FIN/RST, HTTP/2 stream reset, or QUIC/HTTP/3 stream/connection errors can
  terminate individual transport paths,
- the inner proxy protocol may independently observe EOF/reset after XHTTP
  reconstruction.

When diagnosing closure, record **which layer closed first**. An HTTP `413` is
not a VLESS destination error; a QUIC connection close is not an XHTTP sequence
error; and a VLESS parser rejection is not necessarily an HTTP routing error.

## Implementation Checklist

A robust XHTTP implementation should explicitly test:

1. Host and path mismatch handling,
2. split Session ID creation and cleanup,
3. provisional sessions that never obtain a downlink,
4. duplicate, missing, delayed, and out-of-order packet sequence values,
5. body/header/cookie upload placement and Base64 decode failures,
6. configured maximum upload sizes,
7. partial inner-protocol headers spanning multiple HTTP uploads,
8. one upload containing multiple inner-protocol reads worth of data,
9. downlink flushing through direct and reverse-proxied paths,
10. HTTP/1.1, HTTP/2, and HTTP/3 connection-loss behavior,
11. queue/backpressure limits under a slow inner proxy consumer,
12. TLS and REALITY combinations independently from XHTTP session logic.

## XMUX and Connection Reuse

XHTTP can maintain pools of HTTP connections and reuse them for multiple proxy
requests. Current Xray code exposes settings such as maximum concurrency,
connection counts, request reuse limits, and connection lifetime controls.

Tuning these values changes server load and traffic shape. More concurrency is
not always faster: it can increase connection churn, memory usage, and pressure
on reverse proxies or CDNs.

Start with implementation defaults, collect latency/throughput data, and tune
one dimension at a time.

## Reverse Proxy and CDN Considerations

When placing XHTTP behind Nginx, Caddy, or a CDN, check:

- TLS termination location,
- HTTP/2 or HTTP/3 support,
- request and response buffering,
- maximum request body sizes,
- idle and upstream timeouts,
- path rewriting,
- Host/SNI routing,
- and whether the provider permits the connection pattern.

A connection that works directly against Xray but fails behind a reverse proxy
usually indicates an HTTP routing or timeout mismatch rather than a VLESS user
problem.

## XHTTP + REALITY

Current Xray transport documentation supports XHTTP with REALITY.

Keep the layers separate during diagnosis:

1. Is the TCP/QUIC path reachable?
2. Does REALITY authenticate correctly?
3. Does the XHTTP path/mode match?
4. Does the proxy protocol user identity match?
5. Does the reverse proxy/CDN route the request correctly?

Changing all of these at once makes failures difficult to localize.

## Strengths

- HTTP-oriented transport behavior suitable for HTTP-aware infrastructure.
- Can be combined with TLS or REALITY in current Xray versions.
- Supports connection reuse and multiplex-oriented tuning.
- Can be deployed directly or behind reverse-proxy/CDN layers when configured
  correctly.
- Gives operators more control over upload/download transport behavior than a
  single raw stream.

## Limitations

- More configuration surface than raw TCP.
- Path, Host, mode, reverse-proxy, and security settings must align.
- Advanced tuning changes between Xray versions and implementations.
- CDN/reverse-proxy policies can break otherwise valid direct connections.
- Incorrect multiplex tuning can reduce rather than improve performance.

## Security Notes

- Use TLS or REALITY on untrusted networks unless the selected architecture has
  another deliberate security layer.
- Keep TLS certificate verification enabled.
- Do not place authentication secrets in custom HTTP headers unless the protocol
  explicitly requires it and the operational implications are understood.
- Treat reverse-proxy access logs as potentially sensitive because paths,
  headers, and connection metadata may be recorded.
- Keep Xray/core versions patched; XHTTP evolves actively and old examples can
  become misleading.

## Chimera Status

### Chimera_Client

XHTTP is listed as a current client-core capability. The important compatibility
question is not only "does XHTTP exist?" but which proxy protocol, mode,
security layer, and option names are currently implemented. Validate the exact
combination before copying a Mihomo/Xray profile unchanged.

### Chimera GUI

Chimera can manage an XHTTP profile only through the schema accepted by the
selected core. A GUI field being present does not prove that every XHTTP mode or
XMUX option is supported by that core.

### Chimera_Server

The server capability map includes XHTTP-related parsing/transport work. Treat
basic XHTTP connectivity, TLS, REALITY, reverse-proxy behavior, and advanced
XMUX/download settings as separate compatibility dimensions.

## Troubleshooting

### Immediate EOF / disconnect

1. Verify proxy user identity first.
2. Check transport security (TLS/REALITY).
3. Verify `path` on both ends.
4. Check `mode` compatibility.
5. Remove custom headers and XMUX tuning.

### Works directly but not through Nginx/CDN

1. Check path rewriting.
2. Verify Host and SNI routing.
3. Increase/inspect upstream and idle timeouts.
4. Check request buffering/body-size limits.
5. Confirm HTTP/2 or HTTP/3 support on every hop.

### Handshake works but throughput is poor

1. Return XMUX/tuning to defaults.
2. Compare direct and reverse-proxied paths.
3. Measure RTT/loss to the actual CDN edge or server.
4. Check connection churn and upstream limits.
5. Tune only after identifying whether the bottleneck is transport, server, or
   provider policy.

## References

- Xray XHTTP transport page:
  <https://xtls.github.io/en/config/transports/xhttp.html>
- Xray transport compatibility:
  <https://xtls.github.io/en/config/transport.html>
- Xray current XHTTP configuration implementation:
  <https://github.com/XTLS/Xray-core/blob/main/infra/conf/transport_method.go>
