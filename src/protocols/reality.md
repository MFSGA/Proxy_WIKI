# Reality

### Highlights
- TLS camouflage layer from the Xray ecosystem that imitates a TLS 1.3 handshake without issuing a certificate.
- Uses a server public key and short ID to bind the handshake to a real-looking TLS fingerprint.
- Commonly paired with VLESS or Trojan to provide authentication and routing on top of the transport.

### Flow
1. Client selects a cover domain and configures the server public key + short ID.
2. Client initiates a TLS 1.3-like handshake (uTLS fingerprint) with SNI set to the cover domain.
3. Server validates the short ID and key exchange to accept the session.
4. On success, the connection upgrades to the chosen proxy protocol (for example VLESS).

### Configuration Snippet

### Strengths
- Avoids certificate issuance and rotation while keeping TLS-like handshake behavior.
- Harder to fingerprint via passive inspection when the TLS client fingerprint matches common browsers.
- Integrates with XTLS flow control for reduced overhead.

### Limitations
- Requires compatible client fingerprints; mismatches can break connectivity.
- Mostly confined to the Xray tooling ecosystem.
- Effectiveness depends on the chosen cover domain and correct configuration.
