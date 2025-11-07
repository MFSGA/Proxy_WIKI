# chimera_server Library

## Purpose and Scope
`chimera_server` is the shared Rust crate that provides protocol primitives, configuration schemas, crypto suites, and common utilities for both client and server projects. By centralizing these capabilities, the ecosystem avoids duplicated logic, ensures protocol compliance, and keeps security fixes consistent across binaries.

## Key Modules
- Configuration model: strongly typed structures plus serde-based serialization for Clash manifests, Chimera manifests, and shared policy fragments.
- Crypto and handshake utilities: AEAD ciphers, key derivation, certificate pinning helpers, TLS fingerprint templates, and QUIC transport parameters.
- Transport abstractions: traits for stream/session lifecycles, multiplexing interfaces, buffer management, and async runtime adapters.
- Event bus: lightweight publish/subscribe mechanism so higher layers can tap into connection lifecycle events, metrics, and alerts.

## API Surface and Extensibility
The crate exposes a stable Rust API along with optional C FFI bindings for other languages. Extension points allow third parties to register custom cipher suites, add routing annotations, or hook into telemetry emission. Versioning follows semver with clear migration guides whenever breaking changes occur, ensuring that `clash-rs` and `Chimera` can track upgrades smoothly.

## Testing and Quality
`chimera_server` maintains exhaustive unit tests for parsers, crypto primitives, and transport behaviors. Integration suites spin up in-memory client/server pairs to validate interoperability before changes land. Benchmarks measure handshake latency, throughput, and memory footprint across representative hardware, providing baselines for regression detection.
