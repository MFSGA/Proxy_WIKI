# Chimera_Client

## Role and Objectives
`chimera_client` is a Rust reimplementation of the popular Clash client, optimized for low-latency rule evaluation and resource-constrained environments. It exposes the familiar Clash configuration language while embracing Rust’s safety guarantees, making it suitable for desktop, mobile (via bindings), and headless automation scenarios. The client focuses on three pillars: broad protocol compatibility, deterministic policy routing, and easy operator ergonomics.

## Architecture Overview
Internally, the client splits into configuration ingestion, controller APIs, transport engines, and policy runtime. The configuration loader parses Clash YAML into strongly typed Rust structures, validates them with `chimera_core` schemas, and hot-reloads updates. The controller layer provides both a local HTTP API and optional TUI, enabling on-device rule inspection. Transport engines encapsulate each supported protocol (e.g., Shadowsocks, VMess, Trojan, Reality/QUIC); they share cipher suites and handshake logic via `chimera_core`. The policy runtime builds a decision tree from user rules, executes DNS strategies, and feeds matching traffic into the appropriate transport engine.

## Module Configuration Guide
`chimera_client` keeps configuration aligned with its module boundaries, so each functional area has its own block in the Clash-style YAML. This makes changes easier to reason about, and limits the blast radius of hot-reload updates.

- Core runtime and profile: set global defaults such as mode selection, service ports, logging verbosity, IPv6/allow-lan toggles, and reload behavior.
- Inbound listeners: define local HTTP/SOCKS/TUN/transparent ports, bind addresses, UDP enablement, and device interface selection. See [Ports and Listeners](./chimera_client/ports.md).
- Controller and UX: configure the API bind host/port, authentication tokens, and optional TUI or desktop shell toggles.
- DNS pipeline: declare upstream resolvers, cache sizing, fake-IP versus real-IP strategy, fallback behavior, and policy-based resolver selection. See [DNS Module](./chimera_client/dns.md).
- Policy engine: order rules, attach rule providers, choose a default group, and map traffic to outbound groups. See [Rule Types and Their Effects](./chimera_client/rules.md).
- Transport engines: specify per-protocol parameters like cipher suites, transports (TCP/WS/gRPC/QUIC), multiplexing, and TLS fingerprint options; reuse defaults to keep profiles consistent.
- Observability: enable structured logs, metrics, and trace exports, with sampling and retention tuned per environment.
- Update and sync: manage remote profile URLs, signature verification, polling intervals, and rollback on invalid configs.


## Protocol Coverage and Features
`chimera_client` aims for interoperability with the most common proxy ecosystems:

- Traditional: HTTP(S), SOCKS5, and TCP/UDP relays.
- Modern encrypted: Shadowsocks/SSR, VMess/VLESS (TCP/WS/gRPC/QUIC), Trojan, NaïveProxy, TUIC, Hysteria v2.
- Advanced transports: Reality TLS fingerprinting, multiplexed QUIC sessions, and custom obfuscation plugins.

Each protocol implementation documents cipher options, authentication requirements, multiplexing behavior, and fallbacks. Users can mix outbound types in a single configuration and chain proxies for complex routing.

## Deployment Patterns
The client ships binaries for major desktop platforms and offers container images for server-side routing or CI testing. A lightweight system service wraps the daemon on Linux to manage automatic restarts and secret rotation. For mobile, bindings expose the controller API to Flutter and React Native shells. Configuration synchronization relies on GitOps-friendly manifests plus optional remote profile URLs, enabling fleets to pull signed updates on schedule.

## Performance, Observability, and Troubleshooting
`chimera_client` integrates structured logging, OpenTelemetry traces, and per-rule metrics. Operators can export connection stats, latency percentiles, and rule hit counts for dashboards. Performance tuning guidance covers DNS cache sizing, rule tree pruning, per-protocol concurrency caps, and CPU affinity when running on routers. Troubleshooting chapters walk through common failure modes such as TLS fingerprint mismatches, DNS poisoning, or controller authentication errors.

## Reference Repositories
The `chimera_client` source lives here:

- `chimera_client`: <https://github.com/MFSGA/Chimera_Client>
