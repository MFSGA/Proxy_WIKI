# HTTPUpgrade Transport

HTTPUpgrade is an HTTP/1.1 transport wrapper implemented by `Chimera_Server`. It uses an HTTP Upgrade-looking handshake to switch from an HTTP request/response exchange into a raw bidirectional byte stream for an inner proxy protocol.

Despite the current header value `Upgrade: websocket`, this implementation is **not a WebSocket transport**: it does not perform the WebSocket key/accept handshake and it does not add WebSocket data frames after the `101 Switching Protocols` response.

The current `Chimera_Client` outbound transport tree does not contain a matching HTTPUpgrade module, so this page primarily documents Server-side behavior and compatibility boundaries.

## Position in the Stack

```text
TCP
  ↓
optional outer security configured by the server stack
  ↓
HTTP/1.1 GET upgrade request
  ↓
HTTP/1.1 101 Switching Protocols
  ↓
raw bidirectional byte stream
  ↓
inner proxy protocol
  ↓
target forwarding
```

The HTTP exchange is therefore a transport preface. Once the upgrade succeeds, subsequent bytes belong directly to the inner handler.

## Configuration Activation

The current Server activates this wrapper when:

```text
streamSettings.network = "httpupgrade"
```

and the binary was built with the `httpupgrade` Cargo feature.

`httpupgradeSettings` is required. The current parsed fields include:

- `host`;
- `path`;
- `header`;
- `acceptProxyProtocol`;
- `ed`.

Runtime support is intentionally narrower than the parsed structure.

## Current Configuration Semantics

### `path`

The Server normalizes the configured path:

- empty path becomes `/`;
- a path already beginning with `/` is kept;
- otherwise `/` is prepended.

For request matching, query and fragment text are stripped before comparison. For example, a configured path `/upgrade` accepts a request target such as:

```text
/upgrade?token=abc
```

because only `/upgrade` is compared.

### `host`

`host` is optional. When configured, it is trimmed and lowercased. The inbound validates the HTTP `Host` header against that value.

A normal `host:port` request header can match a configured bare hostname. Host validation is therefore about the host identity, not strict textual equality with a client-side port suffix.

### `header`

Custom header configuration is parsed but is not used by the current Server inbound matcher. The builder explicitly treats custom headers as a client-side request-construction concern rather than an inbound routing field.

Do not document arbitrary `header` entries as Server-side validation rules.

### Explicitly Rejected Fields

The current builder rejects:

```text
acceptProxyProtocol = true
ed != 0
```

with explicit configuration errors.

Therefore these fields are neither silently ignored nor partially implemented in the current Server path.

## Handshake Request

The current handler reads one HTTP header block terminated by:

```text
\r\n\r\n
```

and requires all of the following:

- request method `GET`;
- version exactly `HTTP/1.1`;
- request path matching the configured normalized path;
- optional `Host` matching when configured;
- `Connection: Upgrade`;
- `Upgrade: websocket`.

Conceptually:

```http
GET /upgrade HTTP/1.1
Host: example.com
Connection: Upgrade
Upgrade: websocket


```

Header names are normalized to lowercase during parsing; the relevant header values are compared case-insensitively after trimming.

## Response

A valid request receives:

```http
HTTP/1.1 101 Switching Protocols
Connection: Upgrade
Upgrade: websocket


```

Immediately after this response, the same underlying stream is handed to the inner proxy handler.

There is no WebSocket `Sec-WebSocket-Accept` computation in this HTTPUpgrade path.

## Why This Is Not WebSocket

A real WebSocket opening handshake normally has additional fields such as:

```text
Sec-WebSocket-Key
Sec-WebSocket-Version
Sec-WebSocket-Accept
```

and after the `101` response, application data is carried in WebSocket frames with FIN/opcode/mask/length fields.

Current Chimera HTTPUpgrade does neither of those things. Its post-upgrade layout is simply:

```text
HTTP request headers
HTTP 101 response headers
<raw inner-protocol bytes>
<raw inner-protocol bytes>
...
```

This distinction is essential in packet captures. Seeing `Upgrade: websocket` does not mean a WebSocket decoder should be applied to subsequent bytes.

## Preserving Early Inner-protocol Bytes

The current unit test deliberately sends bytes immediately after the HTTP header terminator:

```text
...\r\n\r\nprotocol
```

After the upgrade completes, the inner handler reads exactly those bytes as the beginning of its protocol stream.

That proves the wrapper must not discard or reinterpret bytes that arrive in the same TCP receive sequence after the HTTP headers.

For layered protocols, those first preserved bytes may be an authentication header, UUID/request header, or another transport/protocol preface.

## Header Size Limit

The current Server reads the HTTP header one byte at a time until either:

- `\r\n\r\n` is found; or
- the accumulated header reaches 12 KiB.

The hard limit is:

```text
12288 bytes
```

A larger header is rejected with an invalid-data error.

This is a runtime resource bound and should be considered when migrating configurations that add very large custom request headers on a compatible client.

## Handshake Timeout

The current HTTPUpgrade handshake must complete within:

```text
4 seconds
```

The timeout covers reading and validating the HTTP header preface. Once the `101` response is sent and the inner stream is handed off, normal inner-protocol and TCP timeouts apply instead.

The 4-second value is a current Chimera implementation policy, not an HTTPUpgrade wire field.

## Request Parsing Details

The request line must contain exactly three whitespace-separated components:

```text
METHOD TARGET VERSION
```

Missing components or extra request-line components are rejected.

Header lines without a colon are ignored by the current parser rather than causing the entire request to fail. Recognized headers are stored by lowercased name; later duplicate names overwrite earlier values in the current map-based representation.

The header block itself must be valid UTF-8 for the current parser.

## Host Matching

The current matcher accepts a bare configured hostname against an actual HTTP Host value containing a port:

```text
configured: example.com
actual:     example.com:443
```

Case is normalized before comparison.

IPv6 bracket handling has a dedicated path. Operators should still prefer using the same host form generated by the compatible client instead of relying on unusual textual variants.

## Inner Protocol Handoff

The wrapper implements `TcpServerHandler` and performs:

```text
HTTPUpgrade validation
     |
     v
send 101 response
     |
     v
inner.setup_server_stream_with_context(same_stream, same_context)
```

The forwarding context is preserved across the wrapper. HTTPUpgrade itself does not authenticate proxy users, parse target addresses, or decide TCP/UDP proxy semantics; those are responsibilities of the nested inner handler.

## Layering with Proxy Protocols

Conceptually, a VLESS deployment might look like:

```text
TCP
  ↓
HTTPUpgrade handshake
  ↓
raw VLESS request header
  ↓
VLESS application stream
```

A Trojan or other supported TCP inner handler can use the same transport wrapper when the Server configuration builder permits that combination.

Do not treat `HTTPUpgrade` as a standalone remote proxy protocol: it has no user identity field or destination request of its own.

## Vision Compatibility Boundary

The current `Chimera_Server` builder explicitly rejects configurations where `xtls-rprx-vision` is combined with `httpupgrade` or `grpc` transport in the relevant VLESS flow path.

That is an implementation-level compatibility restriction, not a statement that HTTP Upgrade can never coexist with similar flow designs in another implementation.

When documenting a VLESS transport combination, verify both the transport wrapper and the configured VLESS flow.

## Error and Close Behavior

The current handler can reject before upgrade for reasons including:

- timeout;
- header size limit;
- invalid UTF-8/header parsing;
- non-GET method;
- non-HTTP/1.1 version;
- path mismatch;
- host mismatch;
- missing/incorrect `Connection: Upgrade`;
- missing/incorrect `Upgrade: websocket`.

For these validation failures, the current handler returns an internal error to the server stack; it does not construct an HTTP error page or WebSocket close frame.

After a successful `101`, close/error semantics belong to the inner byte stream and underlying TCP connection. There is no HTTPUpgrade-specific record-level close message.

## Packet-capture View

Without an outer encryption layer, a capture can identify the HTTP preface directly:

```text
C → S: GET /path HTTP/1.1
       Host: ...
       Connection: Upgrade
       Upgrade: websocket
       

S → C: HTTP/1.1 101 Switching Protocols
       Connection: Upgrade
       Upgrade: websocket
       

C ↔ S: raw inner-protocol bytes
```

A WebSocket dissector may misinterpret the post-101 bytes because the handshake superficially advertises `websocket`. The correct interpretation for this transport is raw inner-protocol data.

If TLS or another outer security wrapper protects the connection, the HTTP preface is visible only after decrypting that outer layer.

## HTTPUpgrade vs WebSocket

| Property | HTTPUpgrade in current Chimera Server | WebSocket transport |
| --- | --- | --- |
| HTTP method | GET | GET |
| `Upgrade: websocket` | Required | Required |
| `Connection: Upgrade` | Required | Required |
| `Sec-WebSocket-Key` | Not required | Required by WebSocket handshake |
| `Sec-WebSocket-Accept` | Not generated | Generated by server |
| Post-101 framing | Raw bytes | WebSocket frames |
| Client masking | None at this layer | Client→server WebSocket frames are masked |
| Ping/pong | No HTTPUpgrade-specific control frames | WebSocket control frames |
| Close frame | None | WebSocket close frame |

The shared HTTP headers provide camouflage/upgrade semantics, but the resulting data plane is different.

## HTTPUpgrade vs HTTP CONNECT

HTTP CONNECT also transitions into a tunnel, but the setup semantics differ:

| Property | HTTP CONNECT proxy | HTTPUpgrade transport |
| --- | --- | --- |
| Request | `CONNECT host:port HTTP/1.1` | `GET /path HTTP/1.1` |
| Destination | Expressed in CONNECT authority | Not in the HTTPUpgrade HTTP header; inner proxy protocol carries it |
| Success | Usually `2xx` | `101 Switching Protocols` |
| Proxy authentication | HTTP proxy mechanisms may apply | None in this wrapper |
| Post-handshake bytes | Tunnel/application bytes | Inner proxy-protocol bytes |

HTTPUpgrade is therefore an **extra transport layer** for another proxy protocol, whereas an HTTP CONNECT proxy itself performs destination proxying.

## SOCKS5 Phase-by-phase Comparison

| Phase | SOCKS5 | HTTPUpgrade transport | Relationship |
| --- | --- | --- | --- |
| Initial TCP | Connect to SOCKS server | Connect to HTTPUpgrade listener | Same lower-layer step |
| Method negotiation | SOCKS method list | None | Removed from transport |
| Authentication | Optional SOCKS auth | None at this layer | Delegated to inner protocol/security |
| Destination | SOCKS request contains target | HTTPUpgrade path/Host identify transport endpoint; inner protocol contains target | Moved to inner layer |
| Success response | SOCKS `REP` | HTTP `101` only confirms transport upgrade | Different purpose |
| Data | Raw relay after SOCKS setup | Raw inner-protocol bytes after HTTP headers | Extra transport preface |
| Framing | No extra TCP record framing | No framing after `101` | Conceptually similar raw stream after setup |
| Errors | SOCKS numeric `REP` | Handler errors before `101`; inner errors afterward | Replaced |
| Close | TCP close | TCP/inner-protocol close | Same underlying close after transport setup |

## Current Chimera_Client Status

The current `Chimera_Client` outbound transport tree does not contain an HTTPUpgrade transport module.

Therefore a `Chimera_Server` HTTPUpgrade listener currently needs another compatible client implementation. Do not list `Chimera_Client → Chimera_Server HTTPUpgrade` as a verified combination until a Client runtime path and interoperability test exist.

## Current Test Evidence

The Server contains unit coverage in `handler/httpupgrade.rs` that verifies at least:

- a valid upgrade succeeds;
- first inner-protocol bytes immediately following the HTTP headers are preserved;
- an incorrect path is rejected.

There is no dedicated external HTTPUpgrade E2E file in the currently inspected `chimera_server_app/tests` set. That is weaker evidence than the current gRPC transport's Xray compatibility tests and should be reflected in compatibility claims.

## Security Notes

- `Host` and `path` are routing/camouflage checks, not cryptographic authentication.
- Internet-facing deployments should use an appropriate outer security layer where confidentiality and peer authentication are required.
- Do not expose `acceptProxyProtocol` or `ed` as supported merely because they are present in the parsed Xray-compatible configuration structure; current Server rejects them.
- The 12 KiB header limit and 4-second timeout are useful resource bounds and should not be weakened casually.
- Because bytes after `101` are raw, security tools that assume WebSocket framing can produce misleading results.

## Troubleshooting

Check in this order:

1. TCP reachability and any outer TLS/security layer;
2. request is exactly HTTP/1.1 `GET`;
3. normalized path matches;
4. optional Host matches;
5. `Connection: Upgrade` and `Upgrade: websocket` are present;
6. header block stays within 12 KiB and arrives within 4 seconds;
7. server sends `101 Switching Protocols`;
8. stop using WebSocket framing after `101` and inspect the raw inner protocol;
9. debug inner protocol authentication/destination/target connection separately.

If the HTTP upgrade succeeds but the proxy handshake fails, the problem is below this transport layer.

## Source Anchors

Current Chimera behavior in this chapter is grounded in:

- `Chimera_Server/chimera_server_lib/src/handler/httpupgrade.rs`;
- `Chimera_Server/chimera_server_lib/src/config/mod.rs`;
- `Chimera_Server/chimera_server_lib/src/config/server_config/builder/mod.rs`;
- `Chimera_Server/chimera_server_lib/src/config/server_config/types.rs`;
- `Chimera_Server/chimera_server_lib/src/handler/tcp/tcp_handler_util.rs`.

For portable Xray compatibility, compare these current implementation boundaries with the peer implementation rather than assuming every parsed `httpupgradeSettings` field is active at runtime.
