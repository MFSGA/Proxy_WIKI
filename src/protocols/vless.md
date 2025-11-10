# VLESS

### Highlights
- Lightweight stateless protocol from Project V that uses UUIDs for client identification.
- Typically paired with TLS, XTLS, or Reality transport layers for encryption and camouflage.
- Supports multiplexing, fallback routes, and advanced routing rules within the Xray core ecosystem.

### Flow
1. Client connects to the server transport (TLS, XTLS, Reality, gRPC, or MKCP).
2. Client sends a VLESS header carrying the UUID, command (TCP/UDP), and target address.
3. Server validates the UUID, then opens a stream or datagram tunnel to the destination.
4. Optional features such as Flow Control Transport (FCT) or XTLS split accelerate traffic.

### Configuration Snippet


### Strengths
- UUID-based auth scales well for many users and integrates with automated issuers.
- Compatible with multiple transports, giving flexibility between TCP, gRPC, WS, or QUIC layers.
- XTLS/Reality options reduce TLS overhead and mimic legitimate HTTPS fingerprints.

### Limitations
- Requires the Xray-core ecosystem; not natively supported by mainstream OS tools.
- Misconfiguration of flow parameters can break compatibility with older clients.
- Security relies heavily on the chosen transport; bare VLESS without TLS offers no encryption.
