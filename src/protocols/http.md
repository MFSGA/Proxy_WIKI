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

### HTTP/2 and HTTP/3 are framed differently

CONNECT is an HTTP semantic, not an HTTP/1.1 text-format feature. With HTTP/2
or HTTP/3, the request is represented by protocol frames and pseudo-header
fields rather than an ASCII request line. For HTTP/3, for example, `:method` is
`CONNECT`, `:authority` carries the destination host and port, and the request
stream remains open to carry tunnel data after a successful response.

This distinction matters in packet analysis: searching a capture for the ASCII
word `CONNECT` works for clear-text HTTP/1.1, but not as a general detector for
all HTTP versions.

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
| Proxy transport | TCP | Usually TCP; HTTP/2/3 can use their own mapped transport |
| Initial negotiation | `VER/NMETHODS/METHODS` binary exchange | No equivalent mandatory phase |
| Authentication | Selected SOCKS method, e.g. RFC 1929 | HTTP challenge/response such as `407` + `Proxy-Authorization` |
| TCP command | `CMD=0x01` (`CONNECT`) | HTTP method `CONNECT` |
| Destination type | Explicit `ATYP` for IPv4/domain/IPv6 | Textual authority `host:port` at the semantic layer |
| Destination port | 2-byte network-order integer | Decimal text in HTTP/1.1 authority form |
| Success | `REP=0x00` plus bound address/port | Any HTTP 2xx response |
| Failure | SOCKS `REP` byte | HTTP non-2xx status, often with headers/body |
| Post-success data | Raw TCP byte stream | Tunnel bytes after response headers / stream response |
| General UDP relay | `UDP ASSOCIATE` is standardized | Basic CONNECT does not provide SOCKS-style UDP relay |
| Control encoding | Compact binary | HTTP semantics; HTTP/1.1 is textual, HTTP/2/3 framed |

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
- Xray HTTP inbound reference: <https://xtls.github.io/en/config/inbounds/http.html>
