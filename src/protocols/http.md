# HTTP

### Highlights
- Presents itself as a normal HTTP(S) server and upgrades individual requests into tunnels via the `CONNECT` verb.
- Easy to front with Nginx, Apache, or cloud load balancers.
- Supports HTTP/2 multiplexing when both sides understand it.

### Flow
1. Client opens a TCP (or TLS) connection to the proxy endpoint.
2. Client optionally performs HTTP auth (Basic, Digest, Bearer, or mutual TLS).
3. Client sends `CONNECT target.example.com:443 HTTP/1.1` (or an HTTP/2 `:method CONNECT`).
4. Proxy validates policy, then responds `200 Connection Established`.
5. Subsequent bytes are relayed transparently until one side closes the tunnel.

### Configuration Snippet

### Strengths
- Blends with standard HTTPS traffic; hard to distinguish from regular web browsing.
- Works well behind corporate firewalls that only permit ports 80/443.
- HTTP/2 variants allow many tunnels over one TCP session, reducing handshake cost.

### Limitations
- TCP-only; cannot forward UDP flows without extra encapsulation.
- Proxies must maintain state per tunnel, which impacts scaling under many short-lived connections.
- Additional HTTP headers may leak metadata if not sanitized.
