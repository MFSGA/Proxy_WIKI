# Protocol

## Overview

| Protocol | Default Transport | Authentication | Strengths | Typical Constraints |
| --- | --- | --- | --- | --- |
| SOCKS5 | TCP control + optional UDP | Optional username/password | Works with almost any TCP app, UDP associate mode | Clear-text by default, needs TLS/obfs elsewhere |
| HTTP(S) CONNECT | TCP over HTTP/1.1 or HTTP/2 | Basic auth, bearer token, mutual TLS | Blends with web traffic, easy to deploy on gateways | Only proxies TCP, relies on intermediary keeping long-lived tunnels |
| Trojan | TLS over TCP | Pre-shared password validated inside TLS | Hard to fingerprint, benefits from CDN/SNI | Each password maps to a port/user, needs valid TLS certificate |
| Hysteria 2 | QUIC (UDP) with TLS 1.3 | Password or OIDC-like token | High throughput, UDP native, congestion tuning | Requires open UDP ports, MTU tuning important |
| TUIC | QUIC (UDP) with TLS 1.3 | UUID or token-based auth | 0-RTT friendly, multiplexed streams, low handshake overhead | Needs UDP reachability, QUIC fingerprinting varies by implementation |
| VLESS | TLS/XTLS over TCP or MKCP | UUID-based identity | Flexible multiplexing, optional XTLS auto-split | No encryption without TLS/XTLS layer, ecosystem-specific tooling |
| xHTTP Transport | HTTP-style stream over TLS/Reality | Usually UUID/token from upper protocol (e.g., VLESS) | Better web-traffic camouflage, friendly to reverse proxies/CDNs | Header/path mismatch breaks handshake; extra overhead versus raw TCP |
| Reality (TLS camouflage) | TLS 1.3-like handshake | Public key + short ID (plus upstream auth) | Certificate-less TLS mimicry, resistant to passive probing | Depends on client fingerprint matching, tied to Xray tooling |

Detailed breakdowns now live in dedicated files; each follows the same structure (highlights, flow, configuration snippet, strengths, and limitations) to make comparisons straightforward.

## Deep Dives

- [SOCKS5](./protocols/socks5.md) – General-purpose TCP/UDP proxy with flexible method negotiation.
- [HTTP CONNECT Proxy](./protocols/http.md) – HTTPS-friendly tunnels that ride over standard web ports.
- [Trojan](./protocols/trojan.md) – TLS-camouflaged password proxy ideal for CDN fronting.
- [Hysteria 2](./protocols/hysteria2.md) – QUIC-based transport tuned for high-loss or high-latency links.
- [TUIC](./protocols/tuic.md) – QUIC-based proxy with multiplexing and aggressive latency tuning.
- [VLESS](./protocols/vless.md) – UUID-auth protocol with configurable transports such as TLS, XTLS, or Reality.
- [xHTTP Transport](./protocols/xhttp.md) – HTTP-like transport profile for Xray ecosystems, often paired with VLESS.
- [Reality](./protocols/reality.md) – TLS camouflage layer used by Xray transports without certificates.
