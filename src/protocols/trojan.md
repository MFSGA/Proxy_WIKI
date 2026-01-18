# Trojan

### Highlights
- Starts with a real TLS handshake; all subsequent bytes are TLS application data.
- Auth is a pre-shared password hashed with SHA-224 and hex encoded.
- Request framing reuses SOCKS5-style address fields for CONNECT and UDP ASSOCIATE.
- Invalid or unknown traffic can be forwarded to a fallback endpoint to look like normal HTTPS.

### Flow
1. Client completes a standard TLS handshake with the server (SNI/ALPN as configured).
2. Client sends `hex(SHA224(password))` + CRLF + Trojan Request + CRLF (+ optional payload).
3. Server validates the password and request, then connects to the destination.
4. For TCP, data is relayed bidirectionally; for UDP, packets are framed and tunneled over the TLS stream.

### Wire Format
- The precise framing and field definitions live in [Wire Format](./trojan/wire-format.md).
- The first TLS record may include payload after the request to reduce packet count.

### Traffic Handling
- Fallback behavior and anti-detection notes are in [Traffic Handling](./trojan/traffic-handling.md).

### Strengths
- Uses standard TLS stacks and certificates; inherits mature TLS security and ALPN support.
- Hard to fingerprint when served from a legitimate HTTPS endpoint.
- Minimal protocol overhead once the handshake completes.

### Limitations
- Shared-password model means revocation is coarse unless per-user passwords are used.
- Requires valid TLS certificates and operational renewal.
- Fallback behavior must be configured to keep probes indistinguishable from real HTTPS.

### References
- https://trojan-gfw.github.io/trojan/protocol
