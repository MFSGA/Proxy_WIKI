# SOCKS5

### Official RFC


### Highlights
- Layer-4 proxy that forwards arbitrary TCP streams and supports UDP via ASSOCIATE command.
- Method negotiation lets the server advertise `NO AUTH`, `USERPASS`, or custom authentication.
- Widely supported by browsers, curl, SSH, and VPN clients.

### Flow
1. Client opens a TCP socket to the proxy.
2. Client sends a list of supported authentication methods; server responds with the chosen method.
3. Optional username/password exchange takes place.
4. Client issues `CONNECT`, `BIND`, or `UDP ASSOCIATE` with destination info.
5. Server replies with success/failure code and starts relaying traffic.

### Configuration Snippet

### Strengths
- Works with legacy tooling without extra plugins.
- UDP associate makes DNS-over-UDP possible.
- Minimal framing overhead keeps latency low.

### Limitations
- No built-in encryption; must rely on TLS-over-SOCKS or upstream obfuscation.
- UDP associate requires the client to keep listening on a local port, which some firewalls block.
- Authentication is static unless wrapped in a management layer.
