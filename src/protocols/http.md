# HTTP Proxy

## Positioning

An HTTP proxy is an application-level proxy used by browsers, command-line
tools, package managers, and operating-system proxy settings. For ordinary
HTTP requests, the client sends the request through the proxy. For HTTPS and
other TCP destinations, the client normally asks the proxy to create a tunnel
with the HTTP `CONNECT` method.

HTTP proxying should not be confused with XHTTP. An HTTP proxy is an inbound
proxy protocol used by local applications; [XHTTP](./xhttp.md) is an Xray
transport used between compatible proxy endpoints.

## Protocol Flow

### Plain HTTP request

1. The client connects to the HTTP proxy.
2. The client sends a normal HTTP request using an absolute target URI.
3. The proxy applies authentication and routing policy.
4. The proxy sends the request to the origin server and relays the response.

### `CONNECT` tunnel

1. The client connects to the HTTP proxy.
2. The client sends a request such as `CONNECT example.com:443 HTTP/1.1`.
3. The proxy validates the target and access policy.
4. The proxy establishes a TCP connection to the requested destination.
5. After a successful response, the proxy relays bytes in both directions.
6. For HTTPS, the end-to-end TLS handshake happens inside that tunnel.

The `CONNECT` method creates a TCP-oriented tunnel. It does not by itself add
UDP proxying.

## CONNECT on the Wire

HTTP CONNECT is useful as the next comparison point after SOCKS5 because it
solves nearly the same TCP-tunneling problem with a very different control
encoding. SOCKS5 uses compact binary fields; HTTP/1.1 CONNECT uses an HTTP
request and status response.

### HTTP/1.1 request

A minimal request is:

```text
CONNECT example.com:443 HTTP/1.1\r\n
Host: example.com:443\r\n
\r\n
```

The request target is the destination authority: `host:port`. RFC 9110 requires
an explicit port; CONNECT has no implicit default port. Unlike a SOCKS5 request,
there is no `ATYP` byte. The host is represented textually and the HTTP parser
separates the host and port according to CONNECT's authority-form semantics.

At the byte level the HTTP/1.1 control phase is therefore variable length:

```text
43 4f 4e 4e 45 43 54 20 ...
 C  O  N  N  E  C  T  SP

request-line CRLF
header-field CRLF
header-field CRLF
CRLF
```

The empty line terminates the HTTP header section. Bytes after the successful
CONNECT response are no longer ordinary HTTP/1.1 proxy-control messages; they
belong to the tunneled protocol.

### Successful response and protocol switch

A proxy normally replies with a response such as:

```text
HTTP/1.1 200 Connection Established\r\n
\r\n
```

RFC 9110 defines **any 2xx response** to CONNECT as success. Immediately after
the response header section, both sides switch to tunnel mode. A successful
CONNECT response must not define a message body with `Content-Length` or
`Transfer-Encoding`; clients ignore those fields if a non-conforming proxy
sends them.

This creates a sharp state boundary:

```text
TCP established
      |
      v
HTTP request parsing
      |
      +---- 407/auth challenge ----> retry CONNECT
      |
      +---- non-2xx ---------------> tunnel not created
      |
      `---- 2xx -------------------> opaque byte tunnel
                                        |
                                        v
                              TLS / SSH / other TCP data
```

For HTTPS, the first bytes after the 2xx response are normally a TLS
`ClientHello` from the application. The proxy does not need to understand that
TLS handshake when it is operating as a blind tunnel.

### Proxy authentication exchange

Proxy authentication is not a fixed pre-request negotiation like SOCKS5 method
selection. An HTTP proxy can challenge a request with `407 Proxy Authentication
Required` and at least one `Proxy-Authenticate` challenge. The client can then
repeat CONNECT with `Proxy-Authorization` credentials.

Conceptually:

```text
Client -> Proxy
CONNECT example.com:443 HTTP/1.1

Proxy -> Client
HTTP/1.1 407 Proxy Authentication Required
Proxy-Authenticate: Basic realm="proxy"

Client -> Proxy
CONNECT example.com:443 HTTP/1.1
Proxy-Authorization: Basic <credentials>

Proxy -> Client
HTTP/1.1 200 Connection Established

Client <=============================> Destination
              opaque tunnel bytes
```

The exact credential bytes depend on the selected HTTP authentication scheme.
Basic authentication, for example, is not encryption and should not be exposed
on an untrusted clear-text proxy connection.

### HTTP/2 CONNECT: one tunnel per HTTP/2 stream

CONNECT is an HTTP semantic, not an HTTP/1.1 text-format feature. HTTP/2 keeps
the proxy connection as an ordinary multiplexed HTTP/2 connection and converts
only the request stream into a tunnel. This is a fundamental difference from
HTTP/1.1 CONNECT, where the entire client-to-proxy TCP connection changes into
tunnel mode.

The request header section has these required pseudo-header semantics:

```text
:method    = CONNECT
:authority = example.com:443
:scheme    = omitted
:path      = omitted
```

The header block is HPACK-compressed inside a `HEADERS` frame, so those strings
are semantic fields rather than a fixed byte prefix. A simplified HTTP/2 frame
header is:

```text
0                   1                   2                   3
0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                 Length (24)                   |
+---------------+---------------+---------------+
|   Type (8)    |   Flags (8)   |
+-+-------------+---------------+-------------------------------+
|R|                 Stream Identifier (31)                      |
+=+=============================================================+
|                       Frame Payload (*)                       |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

For the CONNECT request, `Type=0x01` denotes `HEADERS`. On success, the proxy
returns response `HEADERS` carrying a `:status` in the 2xx range. After the
initial request and response header sections, tunnel octets are carried in
HTTP/2 `DATA` frames (`Type=0x00`) on that same stream:

```text
client                         proxy                         target
  | HEADERS stream 1            |                             |
  | :method=CONNECT              |                             |
  | :authority=host:443 -------->| TCP connect -------------->|
  |                              |<----------------------------|
  |<----- HEADERS :status=200    |                             |
  | DATA(stream 1, TLS bytes) -->|---------------------------->|
  |<---- DATA(stream 1, bytes)   |<----------------------------|
  |
  | HEADERS stream 3 CONNECT --->| ... another target ...      |
```

Multiple CONNECT tunnels can therefore coexist on one HTTP/2 connection. Their
`DATA` frames can be interleaved, but the Stream Identifier keeps tunnel bytes
separate. This multiplexing is an extra transport layer that standard SOCKS5
does not define.

HTTP/2 `DATA` is subject to both connection-level and stream-level HTTP/2 flow
control. A CONNECT tunnel can therefore stop making progress even when its
upstream TCP socket is writable if the peer has not supplied enough
`WINDOW_UPDATE` credit. Conversely, one blocked stream does not require the
other CONNECT streams to stop, provided connection-level credit remains.

After CONNECT succeeds, ordinary tunnel bytes are not additional HTTP messages.
RFC 9113 permits `DATA` plus stream-management frames on the connected stream;
a protocol implementation must not try to parse a TLS `ClientHello` inside a
`DATA` payload as another HTTP request.

#### HTTP/2 half-close and reset mapping

HTTP/2 maps the lifetime of the tunneled TCP connection onto the CONNECT stream:

- `END_STREAM` in the client-to-proxy direction corresponds to TCP FIN toward
  the destination after any accompanying DATA bytes are forwarded;
- a destination TCP FIN causes the proxy to finish its sending direction with
  `END_STREAM`;
- a TCP reset or other TCP connection error is represented as `RST_STREAM` with
  `CONNECT_ERROR`;
- a stream error detected by the proxy requires the corresponding target TCP
  connection to be aborted rather than silently reused.

This is more precise than saying that a tunnel simply "closes" when one side
finishes. HTTP/2, like TCP, can represent a half-closed direction, and the other
direction can still contain bytes that need to drain.

### HTTP/3 CONNECT: the same semantics over a QUIC request stream

HTTP/3 retains the same CONNECT pseudo-header rules but maps each request onto a
client-initiated bidirectional QUIC stream. The request begins with HTTP/3
`HEADERS`, the proxy responds with `HEADERS` containing a 2xx `:status`, and
subsequent HTTP/3 `DATA` frames on that request stream carry the TCP tunnel.
The request stream deliberately remains open after the request header section.

At the HTTP/3 framing layer, both frame type and frame length are QUIC
variable-length integers:

```text
HTTP/3 frame
+----------------------+----------------------------------+
| varint Frame Type    | HEADERS=0x01, DATA=0x00, ...     |
| varint Frame Length  | payload byte count               |
| Frame Length bytes   | frame payload                    |
+----------------------+----------------------------------+
```

The HTTP/3 `HEADERS` payload is QPACK-encoded, so a passive capture cannot treat
`:method=CONNECT` or `:authority` as literal wire strings. After the CONNECT
exchange completes, ordinary tunnel octets reside in HTTP/3 DATA payloads, and
those HTTP/3 frames themselves are carried as QUIC STREAM data. TCP segment
boundaries at the target, HTTP/3 DATA frame boundaries, QUIC STREAM frame
boundaries, and UDP packet boundaries are all independent.

HTTP/3 closes a normal tunnel direction using QUIC stream completion. If the
client finishes its sending direction, the proxy maps that completion to a TCP
FIN toward the target. A TCP reset or abnormal target close is represented as a
stream error with `H3_CONNECT_ERROR (0x010f)`. Resetting or aborting one request
stream does not inherently close unrelated CONNECT streams, but a QUIC
connection-level failure destroys every tunnel multiplexed on that connection.

HTTP/3 flow control is provided by QUIC rather than HTTP/2 `WINDOW_UPDATE`
frames. The CONNECT request stream consumes QUIC stream and connection
flow-control credit, and all CONNECT streams on the connection also share the QUIC
congestion controller and path capacity. Thus "many tunnels on one connection"
does not mean each tunnel has independent physical bandwidth.

### Ordinary CONNECT versus Extended CONNECT

Do not confuse basic proxy CONNECT with **Extended CONNECT**. RFC 8441 adds the
`:protocol` pseudo-header after explicit capability negotiation for uses such as
bootstrapping WebSocket over HTTP/2. Extended CONNECT changes the request shape:
it can include `:protocol` and, in that mode, `:scheme` and `:path` are present.
A normal forward proxy tunnel to `example.com:443` uses the ordinary CONNECT
form described above and does not need `:protocol`.

This distinction is particularly useful when reading captures or XHTTP-related
documentation: seeing CONNECT on an HTTP/2 or HTTP/3 stream does not by itself
mean that the stream is a classic forward-proxy TCP tunnel.

### Version-specific packet-capture anchors

The useful capture anchors differ by HTTP version:

```text
HTTP/1.1 clear text
  TCP -> "CONNECT host:port HTTP/1.1\r\n" -> 2xx -> opaque tunnel bytes

HTTP/2
  TCP/TLS -> HTTP/2 stream N
             HEADERS(:method CONNECT, :authority ...)
             HEADERS(:status 2xx)
             DATA / DATA / ... / END_STREAM or RST_STREAM

HTTP/3
  UDP -> QUIC -> request stream N
                HEADERS(:method CONNECT, :authority ...)
                HEADERS(:status 2xx)
                DATA / DATA / ... / QUIC FIN or stream reset
```

Without the TLS/QUIC decryption material, encrypted HTTP/2 and HTTP/3 captures
usually expose transport behavior rather than the target authority or tunnel
contents. With decryption, a dissector should follow the request stream and its
header compression context instead of searching raw packets for the ASCII word
`CONNECT`.

## Client and Proxy State Machines

A useful client-side model is:

```text
DISCONNECTED
   |
   | TCP connect to proxy
   v
HTTP_READY
   |
   | send CONNECT
   v
WAIT_RESPONSE
   |\
   | \-- 407 --> AUTH_RETRY -- send CONNECT --> WAIT_RESPONSE
   |
   |---- 2xx --> TUNNEL
   |
   `---- other/error --> FAILED

TUNNEL -- EOF/error --> CLOSED
```

The proxy has a corresponding model:

```text
ACCEPT
  |
  v
PARSE_REQUEST
  |
  +-- auth required/invalid --> send 407 --> PARSE_REQUEST or close
  |
  +-- invalid target/policy --> send failure --> HTTP_READY or close
  |
  `-- accepted CONNECT --> CONNECT_UPSTREAM
                              |
                              +-- failure --> send non-2xx
                              |
                              `-- success --> send 2xx --> RELAY
                                                        |
                                                        v
                                                      CLOSED
```

A production implementation also needs limits for request-header size, parsing
time, authentication retries, upstream-connect timeout, idle tunnel lifetime,
and half-closed TCP connections.

## Capture-Level Walkthrough

For an HTTPS request through a clear-text HTTP/1.1 proxy, a packet capture can
look approximately like:

```text
Client             HTTP Proxy                TLS Origin
  | TCP SYN ---------->|                         |
  |<--------- SYN/ACK  |                         |
  | CONNECT host:443 ->|                         |
  |                    | TCP SYN -------------->|
  |                    |<------------- SYN/ACK  |
  |<------ HTTP 200 ---|                         |
  | TLS ClientHello ---------------------------->|
  |<--------------------------- TLS ServerHello  |
  |<============ encrypted TLS records =========>|
```

The final TLS arrows are logically end-to-end but their TCP bytes are relayed
through the proxy. If the proxy performs TLS interception instead, that is a
different architecture: two TLS sessions exist and the proxy is no longer a
blind CONNECT tunnel for that traffic.

## SOCKS5 Comparison

| Stage | SOCKS5 | HTTP CONNECT |
| --- | --- | --- |
| Proxy transport | TCP control connection | HTTP/1.1 over TCP; HTTP/2 commonly over TCP/TLS; HTTP/3 over QUIC/UDP |
| Initial negotiation | `VER/NMETHODS/METHODS` binary exchange | No equivalent mandatory proxy-method phase; HTTP version/transport negotiation belongs to the HTTP stack |
| Authentication | Selected SOCKS method, e.g. RFC 1929 | HTTP challenge/response such as `407` + `Proxy-Authorization` |
| TCP command | `CMD=0x01` (`CONNECT`) | HTTP method `CONNECT` |
| Destination type | Explicit `ATYP` for IPv4/domain/IPv6 | Textual authority `host:port` at the HTTP semantic layer |
| Destination port | 2-byte network-order integer | Decimal port inside authority text; explicit port required for CONNECT |
| Success | `REP=0x00` plus bound address/port | Any HTTP 2xx response |
| Failure | SOCKS `REP` byte | HTTP non-2xx before tunnel creation; H2/H3 can additionally signal stream-level CONNECT errors after creation |
| Post-success data | Raw TCP byte stream on the SOCKS connection | HTTP/1.1: raw bytes; H2/H3: tunnel octets inside DATA frames on one request stream |
| Multiplexing | Not defined by RFC 1928; normally one CONNECT per TCP control connection | H2/H3 can carry many independent CONNECT streams on one HTTP connection |
| Reliable flow control | TCP receive window of that SOCKS connection | H1 inherits TCP; H2 adds connection/stream HTTP flow control; H3 uses QUIC connection/stream flow control |
| Half-close | Inherited from the SOCKS TCP connection after reply | H1 inherits TCP; H2 maps FIN to `END_STREAM`; H3 maps direction completion to QUIC stream FIN |
| General UDP relay | `UDP ASSOCIATE` is standardized | Basic CONNECT does not provide SOCKS-style UDP relay |
| Control encoding | Compact binary | HTTP semantics; HTTP/1.1 text, H2 HPACK/framing, H3 QPACK/framing over QUIC |

The most important conceptual correspondence is:

```text
SOCKS5 CONNECT request  ~=  HTTP CONNECT request
SOCKS5 REP=success      ~=  HTTP CONNECT 2xx
SOCKS5 relay state      ~=  HTTP tunnel state
```

The important differences are authentication timing and representation. SOCKS5
negotiates an authentication method before its proxy command. HTTP authentication
is integrated into HTTP request/response semantics and can require replaying the
CONNECT request after a challenge.

## Edge Cases and Security Boundaries

- A proxy must validate the CONNECT target before dialing it. RFC 9110 warns
  specifically about unrestricted tunneling to arbitrary services; allowing
  destinations such as SMTP ports can turn a web proxy into an abuse relay.
- An empty or invalid CONNECT port is invalid. Policy should also restrict
  destination ports where appropriate.
- Do not parse tunneled bytes as another HTTP request merely because they arrive
  on the same client connection after a successful CONNECT. The connection has
  changed semantic state.
- Preserve bytes that arrive immediately after the CONNECT header boundary.
  Implementations that over-read while parsing must pass those bytes into the
  tunnel rather than discard them.
- Handle TCP half-close deliberately. When one side closes its sending direction,
  already-received bytes still need a chance to drain to the peer.
- Authentication headers are hop-specific. `Proxy-Authorization` authenticates
  to the relevant proxy, not to the final origin server.

## Minimal Client-Side Configuration

A Clash-style local listener commonly looks like:

```yaml
port: 7890
bind-address: 127.0.0.1
allow-lan: false
```

Applications can then use:

```text
http://127.0.0.1:7890
```

as their HTTP/HTTPS proxy endpoint.

The exact key names depend on the selected Chimera core. See
[Ports and Listeners](../chimera_client/ports.md) for the current
`chimera_client` mapping.

## Authentication

HTTP proxies may add an authentication layer, but authentication support varies
by implementation. Common deployments use proxy-specific credentials or place
the proxy behind another authenticated control plane.

Do not assume that authentication also encrypts the connection between the
application and the proxy. A plain local HTTP proxy has no transport encryption
unless TLS or another secure channel is explicitly added.

## Strengths

- Broad support in browsers, package managers, CLI tools, and operating systems.
- Simple to inspect and debug during local development.
- HTTPS traffic can be tunneled without terminating the application's TLS
  session at the proxy.
- Well suited to local or trusted-LAN ingress into a proxy core.

## Limitations

- Primarily TCP-oriented; standard HTTP proxy behavior does not provide general
  UDP relay.
- A clear-text proxy listener is unsuitable for direct exposure to the public
  internet.
- Applications that ignore operating-system proxy settings will bypass it.
- Authentication and header behavior vary across implementations.

## Security Notes

For a local desktop deployment, prefer binding the HTTP listener to
`127.0.0.1`. If LAN access is enabled, apply an explicit firewall policy and
understand which clients can reach the proxy.

Exposing an unauthenticated HTTP proxy publicly can turn the host into an open
proxy. Even when authentication is enabled, a plain HTTP connection can expose
credentials or metadata to observers on the local network.

## Chimera Status

### Chimera_Client

The current Wiki documents an HTTP listener as part of the client-core inbound
surface. Availability can still depend on the selected build, configuration,
and runtime path. Validate HTTP `CONNECT` behavior with a minimal profile before
combining it with TUN, DNS hijacking, or complex rules.

### Chimera GUI

Chimera itself does not implement HTTP proxying. It configures and manages the
selected core, so listener behavior follows that core.

### Chimera_Server

HTTP proxying is mainly relevant as a local/client-side inbound. Server-side
HTTP capabilities should be treated separately from remote encrypted proxy
protocols such as Trojan, Hysteria 2, or VLESS.

## Troubleshooting

If a browser or CLI tool cannot connect:

1. Verify the listener address and port.
2. Confirm the process is listening on the expected interface.
3. Test a simple HTTP request before testing HTTPS.
4. For HTTPS failures, confirm that `CONNECT` reaches the proxy and that the
   target host/port is allowed.
5. Check authentication separately from routing rules.
6. If only some applications fail, verify that those applications actually use
   the configured system proxy.

## References

- RFC 9110, HTTP Semantics: <https://www.rfc-editor.org/rfc/rfc9110>
- RFC 9112, HTTP/1.1: <https://www.rfc-editor.org/rfc/rfc9112>
- RFC 9113, HTTP/2: <https://www.rfc-editor.org/rfc/rfc9113>
- RFC 9114, HTTP/3: <https://www.rfc-editor.org/rfc/rfc9114>
- RFC 8441, Bootstrapping WebSockets with HTTP/2: <https://www.rfc-editor.org/rfc/rfc8441>
- Xray HTTP inbound reference: <https://xtls.github.io/en/config/inbounds/http.html>
