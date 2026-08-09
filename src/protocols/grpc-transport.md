# gRPC Transport

The gRPC transport documented here is an Xray-style transport wrapper implemented by `Chimera_Server`. It is not the server's management gRPC API and it is not itself a proxy protocol. It turns a bidirectional byte stream for an inner protocol into gRPC messages over HTTP/2-compatible HTTP serving.

The current `Chimera_Client` outbound tree does not contain a matching gRPC transport module, so this page primarily documents Server behavior and the Xray interoperability surface exercised by Server E2E tests.

## Position in the Stack

```text
TCP
  ↓
optional TLS or REALITY
  ↓
HTTP/2-compatible connection
  ↓
POST /<serviceName>/Tun
  ↓
gRPC message framing
  ↓
protobuf Hunk { bytes data = 1 }
  ↓
inner proxy byte stream
  ↓
VLESS / VMess / Trojan / other supported inner handler
```

A successful HTTP/gRPC exchange only proves the transport wrapper. The inner proxy protocol can still reject authentication, destination fields, flow mode, or other protocol state afterward.

## Server Configuration Boundary

The current Server activates this transport when `streamSettings.network` is `grpc` and the `grpc_transport` Cargo feature is compiled.

`grpcSettings` is required. The current builder normalizes `serviceName` by trimming surrounding `/` characters and whitespace. If the resulting name is empty, configuration is rejected.

The default service name is:

```text
GunService
```

The effective request path is then:

```text
/GunService/Tun
```

or generally:

```text
/<serviceName>/Tun
```

## Current Configuration Support

The parsed configuration structure contains fields such as:

- `serviceName`;
- `multiMode`;
- `authority`;
- `idleTimeout`;
- `healthCheckTimeout`;
- `permitWithoutStream`;
- `initialWindowsSize`.

Current runtime behavior is more limited than the parsed shape:

- `multiMode = true` is explicitly rejected;
- `authority`, `idleTimeout`, `healthCheckTimeout`, `permitWithoutStream`, and `initialWindowsSize` are currently parsed but not applied by the transport builder;
- `serviceName` is active runtime behavior.

These fields should therefore not all be labeled equally as implemented.

## Security Wrappers

The gRPC transport can currently sit behind three Server security modes:

| Security | Current behavior |
| --- | --- |
| Plain | HTTP connection directly on accepted TCP. |
| TLS | Server terminates TLS before HTTP/gRPC; `h2` is added to ALPN if absent. |
| REALITY | Server accepts a REALITY stream before handing it to the HTTP/gRPC server. |

For TLS, certificate and private key material are required. The transport builder ensures `h2` is present in the ALPN list because normal gRPC transport relies on HTTP/2 semantics.

## HTTP Request Requirements

The current request handler accepts a request only when all three conditions hold:

1. method is `POST`;
2. URI path is exactly `/<serviceName>/Tun`;
3. `Content-Type` begins with `application/grpc`.

A request that fails these checks receives an HTTP 200 response carrying:

```text
grpc-status: 12
grpc-message: unimplemented gRPC method
```

This is gRPC's error model: the HTTP status can remain 200 while the gRPC status reports the application/transport error.

## gRPC Message Envelope

Each gRPC message starts with the standard 5-byte message prefix used by this implementation:

```text
+----------------------+---------------------------+
| compressed flag      | message length            |
| u8                   | u32 big-endian            |
+----------------------+---------------------------+
        1 B                       4 B
```

The current Server requires:

```text
compressed flag = 0
```

Any non-zero compressed flag is rejected. Compressed gRPC Hunk messages are therefore not currently supported.

The current maximum encoded gRPC message size is 4 MiB.

## Hunk Protobuf Payload

Inside the 5-byte gRPC envelope, Chimera expects one small protobuf message whose field 1 carries the raw tunnel bytes.

Conceptually:

```proto
message Hunk {
  bytes data = 1;
}
```

For field 1 with wire type `length-delimited`, the first protobuf byte is:

```text
0x0a
```

followed by a protobuf varint length and then the raw data bytes:

```text
0a | VARINT(data_len) | data[data_len]
```

The current decoder rejects messages that do not begin with field 1 tag `0x0a`, contain an invalid varint, or truncate the declared payload.

## Full Upload Wire Shape

Putting the layers together, one client-to-server Hunk looks like:

```text
HTTP/2 DATA payload
    |
    +-- 00                         gRPC compressed flag = 0
    +-- 00 00 00 NN               gRPC message length, u32 BE
    +-- 0a                         protobuf field 1 tag
    +-- <varint raw length>
    +-- <inner proxy bytes>
```

HTTP/2 can split these bytes across DATA frames. The current decoder buffers body fragments until a complete gRPC message is available, so an HTTP/2 frame boundary is not a gRPC Hunk boundary.

## Upload Stream to Inner Protocol

The request body decoder performs this transformation:

```text
HTTP body fragments
   ↓
buffer
   ↓
decode 5-byte gRPC prefix
   ↓
decode protobuf Hunk field 1
   ↓
write raw bytes to 64 KiB duplex pipe
   ↓
inner TcpServerHandler
```

When the HTTP request body ends, the write side of the logical byte stream is shut down. If unconsumed partial gRPC bytes remain, the decoder reports a truncated gRPC message.

## Download / Response Stream

The inner protocol writes raw response bytes into the other side of the duplex pipe. The transport wraps every non-empty read chunk as:

```text
gRPC 5-byte prefix
  ↓
protobuf Hunk field 1
  ↓
HTTP response body DATA
```

After the logical response stream ends, the Server emits response trailers with:

```text
grpc-status: 0
```

The normal response headers include:

```text
HTTP status: 200
Content-Type: application/grpc
grpc-encoding: identity
grpc-accept-encoding: identity
```

## Single-stream Model

The current Server rejects `grpcSettings.multiMode = true`. The implemented path maps one accepted gRPC request to one logical duplex byte stream and one inner proxy handler invocation.

Do not infer Xray gRPC multi-mode parity from HTTP/2's own multiplexing capability. HTTP/2 can multiplex requests at the transport layer, but the currently implemented Chimera configuration/runtime model deliberately supports the single-stream gRPC mode documented here.

## Flow Control

There are multiple independent buffering/flow-control layers:

1. TCP flow control;
2. HTTP/2 connection and stream flow control;
3. HTTP body backpressure;
4. the current 64 KiB in-process duplex pipe;
5. inner protocol buffering and target TCP flow control.

The parsed `initialWindowsSize` field is not currently applied by Chimera Server, so users should not assume that setting changes the active HTTP/2 window in the current implementation.

## Close and Error Behavior

Important failure points include:

- TLS/REALITY handshake failure before HTTP;
- wrong HTTP method/path/content type;
- compressed gRPC message flag;
- message larger than 4 MiB;
- malformed/truncated Hunk protobuf;
- truncated request body;
- inner proxy protocol failure;
- target forwarding failure.

Transport validation errors can appear as gRPC status responses or as connection/log errors depending on where failure occurs. Inner protocol errors happen after the gRPC byte stream has already been established and should be debugged separately.

## Packet-capture Anchors

With plain gRPC transport, a capture can show HTTP/2/gRPC metadata and traffic sizes. With TLS or REALITY, those details are encrypted after the outer security handshake.

After decrypting HTTP/2 DATA, useful anchors are:

```text
00 xx xx xx xx    gRPC prefix
0a ...            protobuf field 1
```

The raw bytes after the Hunk protobuf belong to the inner protocol. For example, VLESS parsing begins only after gRPC transport decoding has removed both the gRPC and protobuf envelopes.

## HTTP/2 vs gRPC vs Inner Protocol

Keep these boundaries explicit:

| Layer | Responsibility |
| --- | --- |
| HTTP/2 | multiplexed HTTP transport, DATA frames, flow control |
| gRPC envelope | compressed flag + 32-bit message length |
| Hunk protobuf | length-delimited field containing tunnel bytes |
| inner proxy protocol | authentication, destination, TCP/UDP semantics |

An HTTP/2 DATA frame is not equivalent to one proxy packet, and one Hunk message is not necessarily one application request.

## Current Test Evidence

The strongest current transport-level interoperability evidence is:

- `chimera_server_app/tests/xray_client_proxy_e2e.rs` → `xray_client_can_proxy_tcp_through_chimera_grpc`, which starts Xray as the VLESS/gRPC client and Chimera as the server;
- `chimera_server_lib/src/beginning/grpc_transport.rs` unit tests for Hunk round-trip encoding and incomplete-frame buffering.

Do **not** use `grpc_all_interfaces_e2e.rs`, `grpc_external_integration.rs`, or `grpc_xray_compat_e2e.rs` as evidence for this proxy transport. Those files test the Server's Xray-compatible **management gRPC API**, which is a different control-plane subsystem despite sharing the word “gRPC”.

## Chimera_Client Status

The current `Chimera_Client` outbound transport tree does not contain a gRPC transport implementation. Therefore a Server gRPC feature must not be presented as a current Chimera Client → Chimera Server end-to-end combination unless a different compatible client is used.

## SOCKS5 Comparison

SOCKS5 and gRPC transport live at different layers, but phase comparison helps troubleshooting:

| Phase | SOCKS5 | gRPC transport |
| --- | --- | --- |
| TCP connect | Connect to SOCKS proxy | Connect to gRPC server, possibly then TLS/REALITY |
| Proxy auth | SOCKS method/subnegotiation | Not handled by gRPC transport; inner protocol handles it |
| Destination request | SOCKS request header | Not handled by gRPC transport; inner protocol carries destination |
| Data framing | Raw TCP bytes after SOCKS setup | gRPC envelope + Hunk protobuf around inner bytes |
| Multiplexing | No HTTP/2 layer | HTTP/2 exists, but Chimera `multiMode` is not implemented |
| Flow control | TCP | TCP + HTTP/2 + in-process pipe + inner protocol |
| Errors | SOCKS `REP` during setup | HTTP/gRPC status for transport errors; inner protocol errors separately |
| Close | TCP close/half-close | HTTP request/response completion + gRPC trailers + underlying connection close |

The relationship is therefore **extra transport layer**, not replacement of SOCKS5's proxy semantics.

## Security Notes

- Prefer TLS or REALITY for Internet-facing gRPC transport; plain gRPC exposes HTTP metadata and inner ciphertext/plaintext according to the inner protocol.
- Keep TLS certificate validation and key material correct; `h2` ALPN is part of the active Server TLS setup.
- A valid gRPC path is not authentication by itself. Security still depends on the configured outer security and inner proxy protocol.
- Do not rely on parsed-but-unused timeout/window fields for resource-control guarantees.
- Bound message sizes and reject compression unless the implementation explicitly supports it; decompression support would add a separate resource-abuse surface.

## Troubleshooting

Check layers in this order:

1. TCP reachability;
2. TLS or REALITY handshake if configured;
3. HTTP/2 negotiation, especially `h2` ALPN for TLS;
4. exact `POST /<serviceName>/Tun` path;
5. `Content-Type: application/grpc`;
6. compressed flag `0` and gRPC message length;
7. protobuf field 1 (`0x0a`) and varint length;
8. inner proxy authentication/destination;
9. target connection.

A `grpc-status: 12` response usually points to method/path/content-type mismatch, while successful gRPC transport followed by no proxy traffic points lower in the inner protocol stack.

## Source Anchors

Current Chimera behavior in this chapter is grounded in:

- `Chimera_Server/chimera_server_lib/src/beginning/grpc_transport.rs`;
- `Chimera_Server/chimera_server_lib/src/config/mod.rs`;
- `Chimera_Server/chimera_server_lib/src/config/server_config/builder/mod.rs`;
- `Chimera_Server/chimera_server_app/tests/xray_client_proxy_e2e.rs`;
- `Chimera_Server/chimera_server_lib/src/beginning/grpc_transport.rs` test module.

For portable behavior, compare against the current Xray gRPC transport definition and the peer implementation used in deployment; the Server's parsed configuration surface is broader than its currently active runtime settings.
