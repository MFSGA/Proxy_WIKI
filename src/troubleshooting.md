# End-to-End Troubleshooting

Proxy failures become much easier to diagnose when the Chimera stack is treated as a sequence of independently testable layers. Do not start by changing UUIDs, DNS, TLS fingerprints, routes, and transport modes at the same time. First identify the **first layer that is observably wrong**.

The practical path is:

```text
application
  ↓
local listener / Android TUN / desktop system proxy
  ↓
Chimera_Client DNS + rule selection
  ↓
selected outbound protocol
  ↓
transport / TLS / REALITY / QUIC
  ↓
Chimera_Server listener / transport wrapper
  ↓
server-side proxy authentication + request parsing
  ↓
server routing / outbound
  ↓
target DNS + target socket
  ↓
target application
```

A failure at one layer often produces symptoms in the layer above it. The goal of this page is to stop at the first failing boundary instead of debugging every layer at once.

For implementation claims and concrete interoperability tests, use [Implementation Status and Source Evidence](./implementation-status.md) and [Test Evidence and Interoperability Matrix](./test-evidence.md) together with this page.

## First Question: Which Boundary Fails?

Use this symptom table before changing configuration:

| Symptom | First boundary to inspect |
| --- | --- |
| Local proxy port refuses connection | listener startup / bind / selected binary feature |
| Local proxy accepts, but controller shows no connection | application proxy settings, listener protocol, allow-LAN/source policy |
| Connection appears, but rule/outbound is unexpected | DNS result, rule order, provider state, selector/group choice |
| Correct outbound selected, remote TCP never establishes | routing/firewall/server address/port |
| TCP establishes, TLS immediately fails | SNI, certificate trust, ALPN, TLS version, REALITY parameters |
| TLS/transport succeeds, proxy auth fails | UUID/password/key/method/flow/protocol request |
| Proxy auth succeeds, target cannot connect | server DNS/routing/outbound/target firewall |
| TCP works but UDP does not | protocol-specific UDP support, session model, MTU, QUIC/datagram path |
| Only service mode fails | Desktop → Chimera_Service IPC, privileges, config path, managed core process |
| Only Android fails | VPN permission, TUN FD, `protect(fd)`, Android routes/DNS, embedded-core state |
| One Xray peer works but Chimera peer fails | exact implementation/feature/interoperability matrix, not the public protocol alone |

The phrase “proxy does not work” is not yet a useful diagnosis. Convert it into one row of this table first.

## Step 0: Validate Configuration Before Network Debugging

A process that rejected configuration has no meaningful network path to debug.

For `Chimera_Server`, the current CLI has a validation-only mode:

```bash
cargo run --package chimera_server_app -- --config path/to/config.json5 --check
```

A successful check exits without starting the server. Validation can catch unsupported fields such as Server gRPC `multiMode`, HTTPUpgrade `acceptProxyProtocol`/`ed`, unsupported XHTTP fields, non-zero REALITY `xver`, and other builder-level restrictions before any packet is sent.

For `Chimera_Client`, distinguish these cases:

1. YAML parses;
2. the outbound/listener is constructible in the current build;
3. the required Cargo feature was compiled;
4. runtime initialization succeeds.

A field being accepted by serde does not prove that it is active runtime behavior. AnyTLS currently has explicit Parsed-only compatibility fields, and several Server Xray-shaped fields are deliberately rejected rather than silently applied.

## Step 1: Prove the Local Ingress

Before debugging a remote protocol, prove that the application can reach the local Client ingress.

For a SOCKS listener, test the exact listener address/port configured in the active runtime. A useful external check is:

```bash
curl --socks5-hostname 127.0.0.1:7891 https://example.com/
```

For an HTTP proxy listener:

```bash
curl --proxy http://127.0.0.1:7890 https://example.com/
```

Use the actual configured ports rather than assuming Clash-family defaults.

If the connection is refused, stay at the listener layer. Check:

- whether the current binary contains the required inbound feature;
- whether another process already owns the port;
- whether the listener bound loopback, LAN, IPv4, or IPv6 as expected;
- source-address/allow-LAN policy;
- listener startup logs.

Current Client logs include messages such as `tcp listen failed`, `udp listen failed`, listener stopped warnings, and source-address rejection. Do not move to TLS or remote authentication until the local listener is demonstrably reachable.

## Step 2: Use the Chimera_Client Controller as an Observation Point

When the Client controller is enabled, it is a much better observation point than guessing from an application timeout.

The current Client exposes controller surfaces including:

```text
/connections
/proxies
/configs
/dns/query
/traffic
/memory
/logs        WebSocket
```

The TCP controller uses bearer-token authentication when a secret is configured:

```text
Authorization: Bearer <secret>
```

The current Client refuses an unsafe non-loopback TCP API configuration without a secret, and also requires valid CORS origins for a non-loopback API listener.

Useful questions are:

- Does `/connections` show the application flow?
- Which proxy chain/group was selected?
- Does `/proxies` show the expected selector state?
- Does `/configs` reflect the runtime configuration you think is active?
- Does `/dns/query` resolve the same name the application is using?
- Do `/traffic` or connection counters move when the application sends data?
- What is the first warning/error on `/logs`?

If no connection appears at all, debug ingress. If a connection appears with the wrong chain, debug DNS/rules/group selection. If the right chain appears and then fails, move outward to the outbound/transport layer.

## Step 3: Separate DNS from Rule Selection

DNS and routing are related but not interchangeable.

A rule can behave differently depending on whether the Client sees:

- the original domain name;
- a locally resolved IP;
- a Fake-IP address that can be reverse-mapped;
- a failed/no DNS result.

Current Client logs have explicit paths for `failed to resolve destination` and failed Fake-IP reverse lookup. Use the controller DNS query surface and the DNS module page before blaming the remote protocol.

A useful isolation sequence is:

1. resolve the destination through the Client's configured resolver path;
2. confirm the expected domain/IP reaches the rule engine;
3. confirm the selected rule and proxy group;
4. only then inspect the remote dial.

If a profile works with a literal IP but not a domain, that is strong evidence to inspect DNS/rule behavior before protocol cryptography.

See [DNS Module](./chimera_client/dns.md) and [Rule Types and Their Effects](./chimera_client/rules.md).

## Step 4: Confirm the Outbound Exists in This Binary

A common source of confusion is documentation/source support versus artifact support.

Current `Chimera_Client` source contains optional features such as:

```text
anytls
shadowsocks
trojan
hysteria
ws
```

These are not all part of the default feature set. A valid profile can therefore fail during handler construction when the distributed/local binary was built without the required feature.

Client outbound-manager logs identify failures such as:

```text
failed to load socks5 outbound ...
failed to load anytls outbound ...
failed to load trojan outbound ...
failed to load vless outbound ...
```

Before packet capture, confirm the expected handler was actually constructed. See [Chimera_Client](./chimera_client.md) for the current feature matrix.

## Step 5: Prove Remote TCP/UDP Reachability Before Protocol Parsing

For TCP-based transports, determine whether a TCP connection to the remote listener can be established at all.

If SYN packets receive no response, proxy credentials are irrelevant. Check:

- server process/listener state;
- destination IP/port;
- local and server firewall;
- NAT/port forwarding;
- IPv4/IPv6 selection;
- cloud/security-group policy;
- routing to the server.

On the Server, listener-level failures appear before protocol handlers. Current Server logs include `Accept failed`, `TCP server stopped with error`, `UDP server stopped with error`, `xhttp accept failed`, and `gRPC transport accept failed`.

For QUIC protocols such as Hysteria 2 and TUIC, a successful TCP check on the same port proves nothing about UDP reachability. Test the actual UDP path and inspect both directions in a packet capture.

## Step 6: Split Security Handshake from Proxy Protocol Handshake

TLS/REALITY success and proxy authentication success are distinct events.

For TLS-based stacks, validate:

- SNI/server name;
- certificate chain/trust or intentional private CA;
- ALPN required by the transport (`h2` for the current Server gRPC/TLS path);
- client certificate/key when mTLS is configured;
- system clock where protocol/security checks depend on time.

For REALITY, additionally verify:

- public/private key pair;
- short ID;
- accepted server name;
- client version bounds when configured;
- VLESS UUID/flow separately from the REALITY handshake.

The Server test suite intentionally contains cases where REALITY/transport state and VLESS account/flow state fail independently. Treat them as separate layers in logs and captures.

See [REALITY](./protocols/reality.md) and [Test Evidence and Interoperability Matrix](./test-evidence.md).

## Step 7: Validate the Transport Wrapper

A transport can fail after TCP/TLS succeeds but before the inner proxy parser sees a byte.

### XHTTP

Check mode, path, Host, session/sequence placement, upload method, data placement, padding metadata, body/header size limits, and whether the configured field is actually implemented by the Server.

Server logs contain transport-specific anchors such as:

```text
xhttp request rejected by host/padding validation
xhttp request rejected by path validation
xhttp packet-up write failed
xhttp logical stream ... failed
```

See [XHTTP Transport](./protocols/xhttp.md).

### gRPC transport

Check in this order:

```text
HTTP/2 / h2 or h2c
POST /<serviceName>/Tun
Content-Type: application/grpc
compressed flag = 0
Hunk protobuf field 1
inner proxy bytes
```

A `grpc-status: 12` response usually means method/path/content-type mismatch. Do not use management-gRPC API tests or endpoints to diagnose the proxy gRPC transport; they are separate subsystems.

See [gRPC Transport](./protocols/grpc-transport.md).

### HTTPUpgrade

The current Server expects HTTP/1.1 `GET`, matching path/optional Host, `Connection: Upgrade`, and `Upgrade: websocket`, then returns `101` and switches to a **raw byte stream**.

Do not apply WebSocket data framing after `101`. That mistake makes the transport handshake look successful while the inner proxy parser receives invalid bytes.

See [HTTPUpgrade Transport](./protocols/httpupgrade.md).

### WebSocket

WebSocket is a different transport. After its HTTP upgrade it still has WebSocket frame boundaries, opcodes, masking rules, control frames, and close semantics. Keep it separate from HTTPUpgrade in packet analysis.

## Step 8: Validate Proxy Authentication and Request Fields

Only after the transport/security layer is proven should you debug protocol credentials and request encoding.

Examples of protocol-layer checks:

| Protocol | High-value fields/state |
| --- | --- |
| SOCKS5 | method selection, RFC 1929 account, command, ATYP/destination |
| Shadowsocks | classic vs 2022 method, key length, salt/session replay, timestamp, EIH user |
| AnyTLS | SHA-256 password token, padding length, SETTINGS/SYN/PSH ordering, stream ID |
| Trojan | password hash line, CRLF framing, command/address, fallback behavior |
| VLESS | UUID, request version, command/address, flow, optional Encryption |
| VMess | AuthID time/replay, AEAD request header, security mode, record framing |
| Hysteria 2 | QUIC/TLS, HTTP auth request, bandwidth/UDP/session state |
| TUIC | QUIC/TLS, UUID/password token, command/session/association IDs |

At this layer, a transport capture may show a healthy connection even though the server immediately closes the inner stream.

Use the corresponding protocol chapter rather than changing transport settings blindly.

## Step 9: Separate Server Inbound Success from Target Success

A server can successfully authenticate the proxy client and still fail to reach the requested target.

After inbound parsing, inspect:

- target domain resolution on the Server;
- routing/outbound policy;
- blackhole/reject selection;
- target IP/port reachability;
- IPv4/IPv6 choice;
- target-side firewall;
- source-address restrictions at the target.

Current Hysteria 2 logs, for example, explicitly distinguish authentication failures from `failed to connect to <target>`. Similar separation should be preserved when reading other protocol logs.

For Dokodemo-door fixed-target mode, there is no proxy request header at all, so target configuration/resolution is especially important. For `followRedirect`, prove Linux original-destination interception before debugging routing.

See [Dokodemo-door](./protocols/dokodemo-door.md).

## Step 10: Treat UDP as a Separate Data Plane

“TCP works” is weak evidence for UDP.

Different protocols use very different UDP models:

- SOCKS5 uses UDP ASSOCIATE plus a SOCKS UDP header;
- Shadowsocks encrypts packet-oriented destination + payload records and AEAD-2022 adds session/packet state;
- AnyTLS currently uses UDP-over-TCP v2, so datagrams inherit TCP ordering/head-of-line blocking;
- Hysteria 2 and TUIC use QUIC-oriented UDP/session semantics;
- Dokodemo-door forwards raw UDP to a fixed/original target;
- some local Client listeners currently do not provide UDP even when the remote outbound can.

For UDP failure, record:

1. client/source address;
2. logical target;
3. chosen outbound;
4. protocol session/association ID where applicable;
5. packet/datagram size;
6. whether the server emitted a response;
7. whether that response reached the original client.

Also check MTU, NAT timeout, firewall UDP policy, QUIC datagram support, and whether the implementation uses stream fallback versus native datagrams.

## Service Mode: Separate Four Processes/Boundaries

When foreground mode works but service mode does not, stop debugging the remote protocol first.

The service-mode chain is:

```text
Chimera desktop
  ↓
local IPC
  ↓
Chimera_Service
  ↓
managed core process
  ↓
proxy network path
```

Check these independently:

1. Is `chimera-service` installed/running?
2. Can the desktop query `/status` through the local IPC client?
3. Does `/core/start` receive the intended `CoreType` and generated config path?
4. Can the service account read the config and execute the selected core?
5. Does the managed core itself start its listeners?

A healthy service process does not prove a healthy core, and a healthy core does not prove remote protocol success.

See [Service Mode Configuration](./chimera/service-mode.md).

## Android: Separate VPN Lifecycle from Proxy Core

For `AChimera`, the path is:

```text
VpnService permission
  ↓
TUN creation / detached FD
  ↓
UniFFI core start
  ↓
socket protect(fd)
  ↓
DNS / rules / outbound
```

High-value failure boundaries are:

- `VpnService.prepare(...)` never succeeds;
- TUN FD is missing/invalid;
- profile verification fails before core start;
- the Rust core starts but its own sockets are not protected and re-enter the VPN;
- Android route/DNS settings do not send expected traffic into the TUN;
- controller traffic/connection state remains empty.

If the same profile works in desktop `Chimera_Client` but fails only on Android, inspect Android VPN/TUN/protection state before changing the remote protocol.

See [AChimera Android Client](./achimera.md).

## Packet Capture Strategy

Capture at the boundary you are trying to prove, not only at the Internet-facing NIC.

A useful sequence is:

1. application → local listener;
2. Client → remote server address;
3. server listener → target;
4. UDP response path back to the client where relevant.

Useful display/filter concepts include:

```text
tcp.port == <port>
udp.port == <port>
tls
http2
http
quic
```

For encrypted transports, packet capture proves reachability, direction, timing, retransmissions, close/reset behavior, and ciphertext sizes unless you have session keys or in-process traces. Do not claim a UUID/password/address is wrong merely because encrypted bytes are opaque.

Protocol pages contain the post-decryption wire anchors for SOCKS5, HTTP CONNECT, Shadowsocks, AnyTLS, Trojan, Hysteria 2, TUIC, VMess, VLESS, XHTTP, gRPC transport, HTTPUpgrade, REALITY, and Dokodemo-door.

## Build a Minimal Reproduction by Removing Layers

When a production stack contains many layers, reduce it deliberately.

A useful order is:

```text
1. target reachable directly from server
2. minimal server inbound without optional transport
3. matching minimal client outbound
4. local SOCKS/HTTP ingress
5. add TLS/REALITY
6. add XHTTP/gRPC/HTTPUpgrade/WebSocket
7. add DNS/Fake-IP/rules/groups
8. add TUN/service mode/Android VPN integration
```

Not every protocol allows every layer to be removed, but the principle is to replace one complex boundary at a time with a known-good simpler one.

Keep a minimal known-good profile in the repository/test environment. It is far more useful than editing a large subscription profile during an incident.

## Error Strings Are Layer Markers

Treat log strings as hints about **where** failure occurred, not just as messages to search online.

Examples from current source include:

```text
Client listener:   tcp listen failed / udp listen failed
Client DNS:        failed to resolve destination
Client outbound:   failed to load <protocol> outbound
AnyTLS:            missing SYN before PSH / alert
Shadowsocks:       failed to perform Shadowsocks handshake
Server listener:   Accept failed / UDP server stopped with error
XHTTP:             request rejected by path or host/padding validation
Hysteria2:         auth rejected / failed to connect to target
TUIC:              Authentication timeout / Connection failed
```

If the first error says “failed to load outbound”, packet capture is premature. If the first Server error is target connect failure, changing the client UUID is unlikely to help.

## Compare Against the Strongest Existing Test

When a failure resembles an already-tested combination, reproduce the repository test before inventing a new configuration.

Examples:

- Chimera Client → Chimera Server REALITY/Vision: dedicated cross-project E2E;
- Xray → Chimera Server VLESS/gRPC: `xray_client_can_proxy_tcp_through_chimera_grpc`;
- Xray → Chimera Server HTTPUpgrade: `xray_client_can_proxy_tcp_through_chimera_httpupgrade`;
- Xray → Chimera Server Shadowsocks 2022: dedicated TCP/AES-UDP test;
- XHTTP: matrix and security-matrix E2E;
- AnyTLS/Shadowsocks Client behavior: dedicated Client integration tests.

See [Test Evidence and Interoperability Matrix](./test-evidence.md) for commands and exact test names.

If the known test passes but the deployment fails, compare configuration/build/platform differences. If the known test fails on the same checkout, investigate implementation/regression before blaming deployment.

## Incident Capture Checklist

For a useful bug report or incident note, record:

- exact repository commit/version for Client and Server;
- binary build features where optional protocols are involved;
- operating system and service/foreground/Android mode;
- sanitized active runtime configuration, not only the source subscription;
- local ingress protocol and address/port;
- selected rule/proxy chain;
- remote server IP/port and transport/security mode;
- first relevant Client warning/error;
- first relevant Server warning/error;
- whether TCP/UDP reachability is proven;
- packet capture around the failing boundary when useful;
- exact existing E2E/integration test that most closely matches the deployment.

Do not include private keys, raw passwords, bearer secrets, subscription URLs, or reusable authentication tokens in public reports.

## Stop Conditions

Stop expanding the search when you have identified the first failing boundary and can reproduce it independently.

Examples:

- listener does not bind → fix listener/build/config first;
- rule selects wrong outbound → fix DNS/rule/group state first;
- TLS certificate fails → fix TLS trust/SNI first;
- gRPC returns status 12 → fix transport method/path/content type first;
- proxy auth succeeds but target connect fails → fix server routing/target first;
- only service mode fails → fix IPC/privilege/core lifecycle first.

Changing downstream layers before the upstream failure is resolved makes the incident harder to reason about and can erase useful evidence.

## Source Anchors

The concrete observation/error paths used in this guide were checked against:

- `Chimera_Client/clash-lib/src/app/api/runner.rs` and `app/api/handlers`;
- `Chimera_Client/clash-lib/src/app/dispatcher/dispatcher_impl.rs`;
- `Chimera_Client/clash-lib/src/app/inbound` and `app/outbound/manager.rs`;
- `Chimera_Client/clash-lib/src/app/dns`;
- `Chimera_Client/clash-lib/src/proxy`;
- `Chimera_Server/chimera_server_app/src/main.rs`;
- `Chimera_Server/chimera_server_lib/src/beginning`;
- `Chimera_Server/chimera_server_lib/src/handler`;
- `Chimera_Server/chimera_server_lib/src/reality`;
- the cross-project and external E2E tests catalogued in [Test Evidence and Interoperability Matrix](./test-evidence.md).

This page should be updated when a failure boundary, controller endpoint, feature gate, or test path changes in source.
