# Deployment Security and Threat Model

This page describes the security boundaries that matter when deploying the Chimera ecosystem. It is not a claim that one configuration is universally secure; it is a checklist for understanding **which component trusts whom, which secrets cross which boundary, and what an attacker can reach if one layer is exposed**.

Protocol cryptography is only one part of the system. A correctly encrypted VLESS/REALITY or Shadowsocks connection can still be undermined by an unauthenticated LAN listener, leaked controller secret, unsafe fallback target, DNS/TUN leak, over-privileged service, or logs containing reusable credentials.

Use this page together with [End-to-End Troubleshooting](./troubleshooting.md), [Implementation Status and Source Evidence](./implementation-status.md), and the protocol-specific security sections.

## Trust Boundaries

A typical desktop deployment crosses these boundaries:

```text
local application
   ↓
local HTTP/SOCKS/mixed/TUN ingress
   ↓
Chimera_Client process
   ↓
remote encrypted/authenticated proxy transport
   ↓
Chimera_Server process
   ↓
server DNS/routing/outbound
   ↓
target network/service
```

Service mode inserts another privileged boundary:

```text
Chimera desktop user process
   ↓ local IPC
Chimera_Service privileged process
   ↓ process/config control
managed proxy core
```

Android inserts a VPN boundary:

```text
Android applications
   ↓
VpnService/TUN
   ↓
AChimera + embedded Rust core
   ↓ protect(fd)
remote network
```

Each arrow can have a different attacker and different authentication model. Do not treat “the proxy connection is encrypted” as protection for every arrow.

## Assets to Protect

Treat these as security-sensitive assets:

- Shadowsocks passwords/PSKs and AEAD-2022 raw keys;
- AnyTLS passwords;
- Trojan passwords;
- VLESS/VMess user identifiers where they grant service access;
- REALITY private keys, client public-key configuration, and short IDs;
- Hysteria 2 credentials;
- TUIC UUID/password material;
- TLS private keys and client certificates;
- Chimera controller/API bearer secrets;
- subscription URLs containing access tokens;
- generated runtime configuration when it contains credentials;
- service IPC/control capability;
- DNS/routing policy when it reveals or controls user traffic.

A value does not need to be a conventional password to be reusable authentication material.

## Threat Actors

Useful threat categories include:

| Actor | Typical capability |
| --- | --- |
| Local unprivileged user/process | Connect to local listeners/APIs, read world-readable files, influence local DNS or environment. |
| LAN peer | Reach listeners accidentally bound to LAN, probe unauthenticated SOCKS/HTTP/Dokodemo endpoints. |
| On-path network observer | See IPs, ports, timing, sizes, plaintext protocols without TLS, and possibly HTTP metadata. |
| Malicious proxy client | Send malformed/replayed/authentication-failing traffic and consume server resources. |
| Malicious/compromised proxy server | Observe target destinations and plaintext after proxy decryption, return malicious content, manipulate DNS/routing behavior under its control. |
| Reverse proxy/CDN/logging infrastructure | Observe HTTP/XHTTP/gRPC metadata that is outside end-to-end encrypted inner payloads. |
| Privileged local attacker | Control service/core lifecycle, routes, DNS, TUN, process memory, and configuration; protocol cryptography cannot protect against full local privilege compromise. |

The appropriate mitigation depends on which actor is in scope.

## Local Proxy Listeners Are Security Boundaries

SOCKS5, local HTTP proxy, and mixed listeners are often plaintext application-facing interfaces. If exposed beyond the intended host, they can become open proxies or leak credentials/traffic metadata.

For local-only desktop use:

- prefer loopback binding unless LAN access is intentionally required;
- verify `allow-lan`/source policy and actual bind address;
- use listener authentication where the implementation and deployment require shared access;
- firewall LAN/WAN access even when the application configuration appears restrictive;
- do not assume remote-protocol authentication protects the local listener.

A LAN peer that can use your local SOCKS listener does not need to know your remote VLESS UUID or Shadowsocks key; your Client will authenticate to the remote server on its behalf.

## Chimera_Client Controller/API

The Client controller is a control and observation surface, not a public application proxy.

Current TCP API behavior requires a bearer token when a secret is configured, and the Client rejects unsafe non-loopback TCP API exposure without a secret. Non-loopback API exposure also requires explicit valid CORS origins.

Security guidance:

- keep the controller on loopback unless remote administration is genuinely needed;
- configure a high-entropy secret before non-loopback exposure;
- restrict it with host firewall rules in addition to application authentication;
- do not put bearer secrets in screenshots, logs, shell history, or bug reports;
- remember that `/connections`, `/proxies`, `/configs`, DNS queries, logs, and traffic information can reveal sensitive operational metadata even without raw payloads.

A compromised controller can expose much more than a passive packet capture.

## Service Mode and Privileged IPC

`Chimera_Service` can start, stop, and restart selected cores using supplied configuration paths, report runtime status, and perform supported privileged network operations such as DNS changes.

That makes the Desktop → Service IPC boundary security-sensitive.

Operational requirements include:

- rely on the repository's local IPC ACL/security mechanisms rather than exposing the service control endpoint broadly;
- keep Desktop, Service, shared IPC types, and core binaries from trusted build/update sources;
- treat a config path supplied to a privileged service as security-sensitive input;
- avoid world-writable generated-config directories;
- verify service-account file permissions and executable paths;
- distinguish service-process compromise from proxy-core compromise in incident response.

Service mode increases operational privilege; it does not strengthen proxy protocol authentication by itself.

## Android VPN/TUN Boundary

`AChimera` owns an Android `VpnService` and passes the TUN file descriptor to the embedded Rust core. The `protect(fd)` callback prevents the proxy core's own remote sockets from being captured by the VPN again.

Security/reliability concerns include:

- incorrect route or DNS configuration can leak traffic outside the intended VPN path;
- failure to protect proxy sockets can create loops or unexpected routing;
- per-app include/exclude policy changes which applications are inside the trust boundary;
- profile files and remote subscription metadata remain sensitive application data;
- Android VPN permission proves user authorization to create the VPN, not remote proxy identity.

When the same profile behaves differently on desktop and Android, do not immediately weaken TLS/protocol checks to make Android work. Prove the VPN/TUN/protection path first.

## DNS Privacy and Routing Leaks

A proxy can carry application traffic while DNS still leaves through an unintended resolver.

Leak risks include:

- application resolves locally before using a proxy;
- system DNS bypasses the Client DNS listener;
- TUN captures traffic but DNS hijack/routing does not match;
- Fake-IP reverse mapping fails and routing falls back unexpectedly;
- server-side domain resolution reveals destinations to the server's resolver even when the client used remote-domain semantics.

Decide explicitly **where names should be resolved** and test that path. DNS privacy is not automatically provided by SOCKS5, HTTP CONNECT, or a remote encrypted proxy protocol.

## TUN and Transparent Routing Risks

TUN, redir, TProxy, and Dokodemo `followRedirect` move policy into operating-system routing/firewall state.

Common risks are:

- traffic bypass because a route/table/rule is missing;
- routing loops;
- DNS escaping through an interface not covered by policy;
- accidentally capturing the proxy server connection itself;
- exposing a transparent listener to networks that should never reach it;
- assuming `followRedirect` creates interception rules when it only consumes original-destination metadata.

Treat OS routes/firewall state as part of the security configuration, not as an implementation detail outside the proxy.

## Remote Listener Exposure

A server listener should expose only the protocol/transport actually intended for remote clients.

Controls include:

- bind only required addresses/interfaces;
- firewall only required TCP/UDP ports;
- remove obsolete inbounds and fallback listeners;
- avoid exposing management APIs on the same trust level as public proxy inbounds;
- verify IPv6 exposure separately from IPv4;
- treat QUIC/UDP reachability as a separate firewall surface from TCP.

A protocol's authentication failure behavior matters only after the attacker can reach the listener.

## TLS Security

For TLS-based transports/protocols:

- keep certificate verification enabled on clients unless there is a documented private trust model;
- validate SNI/server names deliberately;
- protect server private keys with restrictive file permissions;
- rotate certificates/keys according to deployment policy;
- provide client certificate/key together when mTLS is required;
- keep ALPN aligned with the transport (`h2` is required by the current Server gRPC/TLS path).

`skip-cert-verify` is a security downgrade, not a generic troubleshooting switch. If disabling it makes a connection work, fix the trust/SNI/certificate problem rather than leaving verification off.

## REALITY Security Boundary

REALITY adds a transport-security/camouflage mechanism but does not replace the inner proxy account/flow checks.

Protect:

- the REALITY private key;
- expected server names;
- short IDs;
- VLESS UUID/flow configuration separately.

Current Server tests deliberately cover cases where wrong server name, short ID, public key, client version, VLESS UUID, or Vision flow fail independently.

Fallback behavior is part of the security design. A mismatch may route traffic to the configured REALITY destination rather than simply closing. Ensure that destination is safe to expose and that fallback cannot be abused to reach an unintended internal service.

## Shadowsocks Security

For classic AEAD:

- use modern AEAD methods supported by both peers;
- protect passwords/master keys;
- never reuse salt/nonce material deliberately;
- keep replay defenses enabled.

For AEAD-2022:

- the current Server treats configured Base64 material as raw PSK and enforces exact key length;
- timestamp validation makes clock synchronization relevant;
- session/packet replay windows are active security state;
- multi-user EIH changes user selection and must use supported method combinations.

Do not advertise a Client-only cipher as Server-compatible without interoperability evidence.

## AnyTLS Security

AnyTLS uses two distinct layers:

1. TLS for encrypted transport/server identity;
2. a deterministic 32-byte `SHA256(password)` authentication token inside TLS.

Use a high-entropy password and keep TLS certificate verification enabled. The password hash is not a substitute for server certificate authentication.

The current Client inbound can send unknown-password traffic to a configured fallback **after TLS termination**. That fallback receives decrypted TLS application bytes. Point it only at a service intentionally designed to receive such traffic.

Parsed-only fingerprint/idle-session fields must not be relied upon as active security controls in the current runtime.

## Trojan Security

Trojan depends on TLS plus its password-based proxy authentication. Protect both layers independently.

Fallback rules are security-sensitive because unauthenticated or mismatched traffic can be intentionally routed elsewhere. Validate fallback destination, path/type rules, and which fields are actually implemented by Chimera Server.

A safe fallback target should not be an unauthenticated administrative or internal-only service merely because it is convenient for camouflage.

## VLESS and VMess Security

A VLESS UUID identifies/authorizes a proxy user but basic VLESS does not by itself provide transport confidentiality. Use the intended VLESS Encryption and/or TLS/REALITY stack according to the deployment design.

Keep flow mode and transport compatibility explicit; changing Vision/plain flow to bypass an error can change the security and traffic-shaping model.

VMess AEAD provides its own authenticated/encrypted request/body records and anti-replay/time-related state. Protect user IDs and do not re-enable historical insecure modes merely for compatibility.

For both protocols, outer transport camouflage is separate from inner proxy authentication.

## Hysteria 2 and TUIC Security

Hysteria 2 and TUIC build on QUIC/TLS and add their own proxy authentication/session semantics.

Security/resource considerations include:

- UDP listener exposure and firewall policy;
- credential protection;
- QUIC handshake/resource cost under unauthenticated floods;
- limits on concurrent streams/sessions/associations;
- UDP amplification/resource abuse against reachable targets;
- idle/session cleanup;
- target-routing policy.

Do not apply TCP-only rate/connection assumptions to a public QUIC listener.

## XHTTP Metadata Exposure

XHTTP can place session IDs, sequence numbers, padding metadata, and sometimes uplink data chunks in HTTP-visible structures such as paths, query strings, headers, or cookies depending on configuration.

Even when the inner proxy stream is encrypted/authenticated, infrastructure around the HTTP layer may log metadata:

- reverse proxy access logs;
- CDN/WAF logs;
- HTTP header/query tracing;
- browser/developer tooling in unusual deployments.

Avoid putting reusable secrets into configurable XHTTP metadata keys/values. Review logging retention and redaction when using header/cookie/query placement.

`Host`, path, padding, and session metadata are transport validation/camouflage, not a replacement for inner proxy authentication.

## gRPC and HTTPUpgrade Metadata

gRPC transport exposes service path, HTTP/2 metadata, timing, and message sizes to any infrastructure that can see the HTTP layer. TLS/REALITY can protect this on the network, but a terminating reverse proxy can still observe HTTP metadata.

HTTPUpgrade's `Host`, path, and `Upgrade` headers likewise provide transport matching/camouflage rather than cryptographic authentication. After `101`, current Chimera HTTPUpgrade carries raw inner-protocol bytes rather than WebSocket frames.

Do not confuse “request reached the correct path” with “proxy user authenticated”.

## Dokodemo-door Is Not an Authenticated Proxy

Dokodemo-door has no user-authentication handshake of its own.

A fixed-target Dokodemo listener exposed to an untrusted network can act as a direct port forward to the configured service. Protect it with bind scope, firewall policy, outer security where appropriate, and target-service authentication.

For Linux `followRedirect`, the OS interception rules determine which traffic enters the listener. A broad or incorrect redirect rule is a security policy bug even if the Rust handler behaves exactly as designed.

## Fallback Safety

Fallback is not just a compatibility feature. It changes what unauthenticated, malformed, or camouflage traffic can reach.

For every fallback path, document:

- triggering condition;
- destination service;
- whether bytes are raw encrypted transport bytes or already-decrypted application bytes;
- whether original SNI/path metadata is preserved;
- whether the target service requires its own authentication;
- whether an attacker can intentionally trigger fallback repeatedly.

The Server E2E suite contains fallback cases because “reject” and “route to fallback” are materially different security outcomes.

## UDP and Amplification/Resource Abuse

Public UDP/QUIC listeners need resource controls independent of TCP controls.

Threats include:

- spoofed-source traffic where the network permits it;
- high-rate unauthenticated QUIC handshakes;
- creating many protocol associations/sessions;
- sending traffic toward high-amplification targets;
- retaining idle UDP state too long;
- oversized datagrams or fragmentation pressure.

Use firewall/rate controls, protocol authentication, bounded session state, idle expiry, and routing restrictions appropriate to the deployment.

Current implementations already contain protocol-specific replay/session/timeout controls in several paths, but those do not replace network-level abuse controls.

## Logging and Redaction

Logs are valuable for troubleshooting and can also become a data leak.

Do not log or publish:

- raw passwords/PSKs/private keys;
- controller bearer secrets;
- full subscription URLs containing tokens;
- complete generated configs without sanitization;
- authentication tokens or deterministic password hashes when they can be reused;
- sensitive DNS/target history beyond the required operational retention.

Be careful with structured logs containing target addresses, inbound tags, user identities, SNI, XHTTP metadata, and connection chains. Decide retention and access policy deliberately.

## Configuration and File Permissions

Generated configuration often contains everything needed to authenticate as the user.

Protect:

- profile directories;
- generated runtime YAML/JSON5;
- TLS/REALITY key files;
- service data/config directories;
- test fixtures containing real secrets;
- backups and crash reports.

Use placeholders or dedicated test credentials in repository examples. Never copy production credentials into an interoperability test merely to make it realistic.

## Updates and Build Provenance

The ecosystem can run different core binaries and optional Cargo feature sets. Security review must therefore identify the **actual artifact**, not only the repository source.

Record:

- core type;
- version/commit;
- enabled optional protocol features;
- update source/channel;
- checksum/signature verification process where available.

A protocol implementation existing in source does not prove the deployed binary contains it, and a security fix in source does not protect an older deployed binary.

## Deployment Baseline

A reasonable baseline for an Internet-facing deployment is:

1. bind local Client/controller listeners to loopback unless remote access is required;
2. firewall Server ports to only the required TCP/UDP surface;
3. enable and validate protocol authentication;
4. enable TLS/REALITY where the protocol/transport design requires it;
5. keep certificate verification enabled;
6. protect credentials and generated config files;
7. verify DNS/TUN routing does not bypass policy;
8. review all fallback destinations;
9. bound UDP/QUIC/session resources;
10. redact logs and bug reports;
11. run the strongest relevant negative/interoperability tests after security-sensitive changes.

This baseline is intentionally layered. No single checkbox replaces the others.

## Security Review Checklist

Before exposing a new inbound or client control surface, answer:

- Who can connect to it at the network layer?
- What authenticates that peer?
- Is the channel encrypted, and who terminates encryption?
- What metadata remains visible outside encryption?
- What happens on authentication failure: close, drop, or fallback?
- Can the caller choose an arbitrary destination?
- Can UDP/QUIC behavior be abused for resource consumption or amplification?
- Which secrets/config files are readable by the process and local users?
- What is logged?
- Which negative tests prove malformed/unauthorized traffic is handled as expected?

If any answer is unknown, treat it as an unresolved deployment risk rather than assuming a protocol name implies safety.

## Source Anchors

The implementation-specific boundaries in this page are derived from the current source and documentation work around:

- `Chimera_Client` listener/API authorization, DNS/TUN, optional protocol features, AnyTLS and Shadowsocks implementations;
- `Chimera_Service` IPC/ACL and privileged core/network management;
- `AChimera` `VpnService`, TUN ownership, and `protect(fd)` bridge;
- `Chimera_Server` config validation, fallback handling, protocol/transport handlers, replay/session state, routing, and tests;
- protocol chapters in this Wiki that document current wire/security behavior;
- negative and interoperability suites catalogued in [Test Evidence and Interoperability Matrix](./test-evidence.md).

When a field moves from Parsed-only/Rejected to active runtime behavior, or when a new listener/control endpoint is added, re-evaluate the corresponding trust boundary here.
