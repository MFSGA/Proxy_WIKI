# chimera_client Client

## Role and Objectives
`chimera_client` is a Rust reimplementation of the popular Clash client, optimized for low-latency rule evaluation and resource-constrained environments. It exposes the familiar Clash configuration language while embracing Rust’s safety guarantees, making it suitable for desktop, mobile (via bindings), and headless automation scenarios. The client focuses on three pillars: broad protocol compatibility, deterministic policy routing, and easy operator ergonomics.

## Architecture Overview
Internally, the client splits into configuration ingestion, controller APIs, transport engines, and policy runtime. The configuration loader parses Clash YAML into strongly typed Rust structures, validates them with `chimera_core` schemas, and hot-reloads updates. The controller layer provides both a local HTTP API and optional TUI, enabling on-device rule inspection. Transport engines encapsulate each supported protocol (e.g., Shadowsocks, VMess, Trojan, Reality/QUIC); they share cipher suites and handshake logic via `chimera_core`. The policy runtime builds a decision tree from user rules, executes DNS strategies, and feeds matching traffic into the appropriate transport engine.

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
