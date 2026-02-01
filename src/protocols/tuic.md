# TUIC

### Highlights
- QUIC-based proxy protocol that uses TLS 1.3 for encryption and stream multiplexing.
- Supports 0-RTT resumption and UDP relay over QUIC datagrams.
- Designed for aggressive latency tuning with modern congestion control.

### Flow
1. Client opens a QUIC connection to the server and completes the TLS 1.3 handshake.
2. Client authenticates with a UUID/token configured on the server.
3. Client opens bidirectional QUIC streams for TCP requests and uses datagrams for UDP relay.
4. Server validates auth, then forwards traffic to upstream destinations.

### Configuration Snippet

### Strengths
- Low handshake overhead with 0-RTT and multiplexed streams.
- Handles UDP natively without extra encapsulation layers.
- Good performance on lossy or high-latency mobile networks.

### Limitations
- Requires UDP reachability and QUIC-friendly network paths.
- QUIC fingerprints vary by implementation and can be throttled or blocked.
- MTU and packet pacing tuning are often required for best results.
