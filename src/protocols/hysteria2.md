# Hysteria 2

### Highlights
- QUIC- and UDP-based transport built for high-throughput and high-latency networks.
- Implements selective acknowledgments, BBR-like congestion control, and application-layer keepalives.
- Supports protocol obfuscation by randomizing packet size/padding.

### Flow
1. Client initiates a QUIC handshake to the server UDP port (default 443/udp).
2. TLS 1.3 handshake with ALPN `h3` runs inside QUIC; server authenticates via password or token.
3. Once authenticated, the client opens bidirectional streams for TCP proxying or datagrams for UDP.
4. Adaptive congestion algorithm tunes pacing; optional packet loss recovery retransmits as needed.

### Configuration Snippet

### Strengths
- Excels on lossy or long-distance links thanks to optimized congestion control.
- Native UDP tunneling avoids TCP-over-TCP meltdown for gaming or VoIP.
- Built-in obfuscation and padding resist simple traffic fingerprinting.

### Limitations
- Requires stable UDP reachability; some enterprise networks block outbound UDP.
- Needs path MTU tuning to avoid fragmentation; 1200 bytes is a safe default.
- Implementations are newer compared with SOCKS5/HTTP, so client compatibility is narrower.
