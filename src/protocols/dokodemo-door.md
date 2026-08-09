# Dokodemo-door

Dokodemo-door is a destination-forwarding inbound rather than an authenticated proxy wire protocol. A client connects or sends a UDP datagram to the inbound listener, and the server forwards the payload to either a configured target or the operating system's recovered original destination.

There is no Dokodemo-specific request header, authentication negotiation, success reply, record framing, or encryption format. That absence is the most important fact for packet-level analysis: after any configured outer transport/security wrapper is removed, the bytes are the application's own bytes.

This page documents the current `Chimera_Server` implementation and its Xray-shaped configuration surface.

## Position in the Stack

Fixed-target TCP mode is conceptually:

```text
client TCP
   ↓
optional transport/security wrapper
   ↓
Dokodemo-door inbound
   ↓
configured address:port
   ↓
target TCP service
```

Transparent redirect mode is instead:

```text
intercepted TCP/UDP traffic
   ↓
Linux redirect/TProxy-style socket metadata
   ↓
recover original destination
   ↓
Dokodemo-door forwarding/routing
   ↓
original target
```

Dokodemo-door therefore answers **where to forward**. It does not define a new application protocol between the client and server.

## Configuration Fields

The current Server parses the following `settings` fields:

| Field | Current meaning |
| --- | --- |
| `address` | Fixed forwarding target address when `followRedirect` is false. |
| `port` | Fixed forwarding target port when `followRedirect` is false. |
| `followRedirect` | Use the socket's original destination instead of the configured target. |

When `address` is omitted, the current builder uses the inbound bind address as the target address. When `port` is omitted, it uses the inbound listen port as the target port.

For ordinary fixed forwarding, configure both fields explicitly unless that fallback behavior is genuinely desired.

## Example: Fixed TCP Target

```json
{
  "inbounds": [
    {
      "tag": "dokodemo-door-tcp",
      "listen": "127.0.0.1",
      "port": 11003,
      "protocol": "dokodemo-door",
      "settings": {
        "address": "example.com",
        "port": 80,
        "followRedirect": false
      },
      "streamSettings": {
        "network": "tcp"
      }
    }
  ]
}
```

A TCP client connecting to `127.0.0.1:11003` does not send a proxy destination header. The Server already knows the target `example.com:80` from configuration and forwards the client's first byte as target application data.

## TCP Data Path

The current TCP handler returns a direct forwarding result containing:

- the selected remote location;
- the same accepted byte stream;
- no protocol-specific success response;
- a `dokodemo-door` traffic context carrying the inbound tag.

Conceptually:

```text
ACCEPT TCP
   |
   +-- followRedirect=false --> target = configured address:port
   |
   +-- followRedirect=true  --> target = connection.original_destination
   |
   v
SELECT ROUTING / OUTBOUND
   |
   v
CONNECT TARGET
   |
   v
COPY RAW BYTES BOTH DIRECTIONS
```

No bytes are consumed by a Dokodemo request parser because no such parser exists.

## `followRedirect` on TCP

When `followRedirect` is enabled, the handler declares that it requires an original destination in the TCP connection context.

On Linux, the listener obtains this using the socket original-destination mechanism:

- IPv4 uses the original-destination socket information exposed through the Linux socket API;
- IPv6 uses the corresponding IPv6 original-destination path;
- the recovered IP and port become the Dokodemo forwarding target.

If the operating system does not provide an original destination, the TCP handler rejects the flow with an address-not-available error instead of falling back silently to the configured target.

On non-Linux platforms, the current Server rejects TCP `followRedirect` as unsupported.

## Transparent Interception Is an OS Feature

`followRedirect` does not itself create firewall/NAT interception rules. The operating system must first redirect traffic to the Dokodemo listener while preserving enough original-destination metadata for the Server to recover it.

A working transparent deployment therefore has at least two independent pieces:

```text
firewall / policy routing / redirect setup
                    ↓
              listener socket
                    ↓
          original-destination lookup
                    ↓
            Dokodemo forwarding
```

A correct Dokodemo configuration cannot compensate for missing or incorrect OS interception rules.

## TCP Transport Wrappers

For TCP mode, the current Server builder accepts these `streamSettings.network` values:

- empty / `tcp`;
- `httpupgrade`;
- `grpc`.

The normal security-layer builder can also wrap the TCP path where the selected combination is valid.

This means Dokodemo-door can be the **inner forwarding handler** behind another transport. In that case, the wrapper consumes its own handshake bytes first, and only the resulting inner raw stream is forwarded to the configured/original target.

See [gRPC Transport](./grpc-transport.md) and [HTTPUpgrade Transport](./httpupgrade.md) for the transport-layer behavior.

## UDP Mode

UDP mode is selected with:

```json
"streamSettings": {
  "network": "udp"
}
```

The current Server's generic UDP entry path supports Dokodemo-door and Shadowsocks at this stage.

For Dokodemo UDP, `streamSettings.security` must be `none`. Applying a stream security layer to the UDP Dokodemo path is rejected during configuration building.

## Example: Fixed UDP Target

```json
{
  "inbounds": [
    {
      "tag": "dokodemo-door-udp",
      "listen": "127.0.0.1",
      "port": 11020,
      "protocol": "dokodemo-door",
      "settings": {
        "address": "127.0.0.1",
        "port": 5353,
        "followRedirect": false
      },
      "streamSettings": {
        "network": "udp"
      }
    }
  ]
}
```

Each client datagram is ordinary application UDP payload. There is no Dokodemo UDP header around it.

## Fixed-target UDP Resolution

When `followRedirect` is false, the Server resolves the configured target once while starting the UDP inbound and stores the resulting socket address for the relay path.

The receive loop then treats every incoming datagram as payload for that fixed target, subject to routing/outbound selection.

This is different from SOCKS5 UDP, where each client datagram can carry its own destination address.

## UDP Session Key

For direct/freedom forwarding, the current relay reuses an outbound UDP session using a key composed of:

```text
client_addr
target_addr
outbound_tag
```

Datagrams with the same tuple can therefore reuse the same outbound socket/session.

The current session channel capacity is 64 queued payloads and the idle timeout is 60 seconds. Successful sends and accepted responses reset the idle timer.

These values are current Chimera runtime policies, not fields in a Dokodemo wire format.

## UDP Response Validation

A direct UDP session accepts a response only when the source socket address exactly matches the expected target address for that session.

A response from an unexpected source is ignored rather than forwarded to the original client.

Valid response bytes are written directly back to the client's socket address without adding a Dokodemo or SOCKS header.

## UDP Routing and Blackhole

Before creating/reusing a direct UDP session, the Server applies its UDP outbound selection using information including:

- inbound tag;
- client address;
- target socket address;
- target logical location.

A rule can therefore route Dokodemo UDP traffic to a blackhole outbound. In that case the payload is accounted for and dropped without creating the target relay session.

The repository contains an Xray-compatible example specifically for Dokodemo UDP routing to blackhole.

## UDP `followRedirect`

On Linux, the current UDP implementation can enable original-destination reception on the listener socket. For each datagram it obtains:

```text
client address
original destination address
payload
```

The original destination becomes both the routing target and the forwarding destination for that datagram/session.

On non-Linux platforms, current UDP `followRedirect` is rejected as unsupported.

As with TCP, the OS must have redirected the datagram in a way that preserves recoverable original-destination metadata.

## TCP vs UDP `followRedirect`

| Property | TCP | UDP |
| --- | --- | --- |
| Current platform | Linux only | Linux only |
| Destination source | Accepted socket's original destination | Per-datagram original destination metadata |
| Missing metadata | Flow rejected | Receive/relay path fails rather than using fixed target |
| Application framing | Raw TCP bytes | Raw UDP payload |
| Dokodemo header | None | None |

UDP original destination is per datagram because one listener can receive datagrams originally addressed to different targets. TCP gets one original destination from the accepted connection socket.

## No Authentication Handshake

Dokodemo-door does not authenticate a remote proxy user. If the listener is reachable by an untrusted network and forwards to a fixed sensitive service, it can effectively expose that service through the listener.

Security must come from deployment controls such as:

- bind/listen scope;
- firewall rules;
- outer TLS/REALITY/transport layers where appropriate for TCP;
- routing policy;
- target-service authentication.

Do not confuse a configured `Host`, gRPC service name, or transport path with Dokodemo user authentication.

## No Success Reply

There is no Dokodemo equivalent of the SOCKS5 `REP` response.

For fixed TCP forwarding, a client sees only normal target/application behavior after the Server succeeds in opening the outbound path. If target connection establishment fails, the observable effect is stream failure/close rather than a Dokodemo status packet.

For UDP, there is likewise no control channel announcing success; datagrams are forwarded or dropped according to routing and runtime errors.

## State Machine: Fixed TCP

```text
TCP_ACCEPT
    |
    v
SELECT_CONFIGURED_TARGET
    |
    v
SELECT_OUTBOUND / ROUTE
    |
    v
CONNECT_TARGET
    |
    v
RAW_BIDIRECTIONAL_RELAY
    |
    v
EOF / ERROR
```

## State Machine: Redirected TCP

```text
TCP_ACCEPT
    |
    v
READ_SO_ORIGINAL_DST
    |
    +-- unavailable --> ERROR
    |
    v
SELECT_ORIGINAL_TARGET
    |
    v
ROUTE / CONNECT / RELAY
```

## State Machine: UDP

```text
RECEIVE_DATAGRAM
    |
    +-- fixed mode ------> configured target
    |
    +-- redirect mode ---> original destination
    |
    v
SELECT_OUTBOUND
    |
    +-- blackhole --> DROP
    |
    v
GET_OR_CREATE_SESSION(client,target,outbound)
    |
    v
SEND RAW PAYLOAD
    |
    v
ACCEPT EXPECTED-TARGET RESPONSES
    |
    v
SEND RAW RESPONSE TO CLIENT
```

## Packet-capture View

In plain fixed TCP mode, a capture at the Dokodemo listener looks like the underlying application protocol itself. For example, forwarding HTTP means the first client bytes may literally be:

```text
GET / HTTP/1.1\r\n
```

There is no preceding Dokodemo signature.

In fixed UDP mode, each captured UDP payload is likewise the application's datagram without a Dokodemo address envelope.

With HTTPUpgrade, gRPC, TLS, or another wrapper, capture interpretation must first remove that outer layer before reaching the raw target application bytes.

## Comparison with SOCKS5

| Phase | SOCKS5 | Dokodemo-door | Relationship |
| --- | --- | --- | --- |
| Client transport | Client connects to SOCKS listener | Client connects/sends to Dokodemo listener | Same ingress concept |
| Method negotiation | `VER/NMETHODS/METHODS` | None | Removed |
| Authentication | Optional subnegotiation | None | Removed/delegated to deployment |
| Destination request | Client sends `CMD + ATYP + DST` | Target is configured or recovered from OS original destination | Replaced |
| Success response | `REP + BND` | None | Removed |
| TCP payload | Raw after SOCKS handshake | Raw from first byte | Dokodemo has no protocol preface |
| UDP destination | Address in every SOCKS UDP header | Fixed target or OS original destination | Replaced |
| UDP framing | `RSV/FRAG/ATYP/DST/DATA` | Raw application payload | Removed |
| Fragmentation field | SOCKS `FRAG` | None | Removed |
| Transparent interception | Not inherent to normal SOCKS operation | Core use case for `followRedirect` | Extra OS-integration mode |
| Error reporting | Protocol `REP` during request | Socket/handler/log failure | Replaced |

Dokodemo-door is therefore closer to a programmable port forward / transparent redirect target than to a client-negotiated SOCKS proxy.

## Current Test Evidence

The current Server source contains tests for:

- TCP `followRedirect` selecting the original destination;
- TCP rejection when original destination context is missing;
- Linux TCP original-destination extraction path;
- fixed-target UDP relay;
- UDP session reuse for the same flow;
- forwarding multiple UDP responses;
- Linux UDP `followRedirect` routing by original destination;
- UDP routing/blackhole behavior;
- Xray-compatible Dokodemo TCP and UDP example parsing/building.

The Xray-compatible examples include:

- `dokodemo-door-tcp.json5`;
- `dokodemo-door-udp.json5`;
- `dokodemo-door-udp-routing-blackhole.json5`.

This is stronger evidence than a protocol enum entry alone, although transparent interception still depends on real Linux firewall/socket behavior in deployment.

## Current Compatibility Boundaries

The current implementation should be documented with these boundaries visible:

- `followRedirect` is Linux-only for both TCP and UDP;
- UDP Dokodemo does not support `streamSettings.security`;
- supported network choices are UDP, TCP/default, HTTPUpgrade, and gRPC as allowed by the builder;
- there is no Dokodemo authentication/header/reply protocol;
- fixed UDP target DNS resolution happens during inbound startup;
- UDP sessions expire after 60 seconds of inactivity;
- response packets from an unexpected target socket are ignored.

## Troubleshooting

For fixed forwarding:

1. verify the listener bind address/port;
2. verify configured `address` and `port` rather than relying on defaults unintentionally;
3. verify target DNS resolution and reachability;
4. verify routing has not selected blackhole or an unintended outbound;
5. for TCP wrappers, debug HTTPUpgrade/gRPC/TLS before Dokodemo forwarding;
6. inspect the target application protocol directly because Dokodemo adds no inner framing.

For `followRedirect`:

1. confirm the host is Linux;
2. confirm firewall/policy-routing rules actually intercept traffic into the listener;
3. confirm original-destination metadata survives the interception mode;
4. distinguish TCP socket original destination from UDP per-datagram destination metadata;
5. only then debug Server routing/target reachability.

A `followRedirect` failure is often an OS interception problem rather than a proxy wire-format problem.

## Source Anchors

Current Chimera behavior in this chapter is grounded in:

- `Chimera_Server/chimera_server_lib/src/config/server_config/builder/mod.rs`;
- `Chimera_Server/chimera_server_lib/src/config/server_config/types.rs`;
- `Chimera_Server/chimera_server_lib/src/handler/dokodemo.rs`;
- `Chimera_Server/chimera_server_lib/src/beginning/mod.rs`;
- `Chimera_Server/chimera_server_lib/src/beginning/udp.rs`;
- `Chimera_Server/examples/xray-compatible/dokodemo-door-tcp.json5`;
- `Chimera_Server/examples/xray-compatible/dokodemo-door-udp.json5`;
- `Chimera_Server/examples/xray-compatible/dokodemo-door-udp-routing-blackhole.json5`;
- `Chimera_Server/chimera_server_lib/tests/xray_compatible_examples.rs`.

For portable transparent-proxy behavior, also verify the Linux interception mechanism used by the deployment; Dokodemo-door can consume original-destination metadata but does not create the operating-system redirect rules that produce it.
