# SOCKS5

### Official RFC
The SOCKS version 5 protocol is specified primarily in **[RFC 1928](https://www.rfc-editor.org/rfc/rfc1928)**.

**Key related RFCs:**

* **[RFC 1928 — SOCKS Protocol Version 5](https://www.rfc-editor.org/rfc/rfc1928)** (core protocol, addressing, UDP ASSOCIATE, authentication negotiation)
* **[RFC 1929 — Username/Password Authentication for SOCKS V5](https://www.rfc-editor.org/rfc/rfc1929)** (optional authentication method)
* **[RFC 1961 — GSS-API Authentication Method for SOCKS V5](https://www.rfc-editor.org/rfc/rfc1961)** (optional authentication)
* **[RFC 3089 — SOCKS-based IPv6/IPv4 Gateway](https://www.rfc-editor.org/rfc/rfc3089)** (interoperability for IPv6 scenarios)

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

### References
- https://www.rfc-editor.org/rfc/rfc1928
- https://www.rfc-editor.org/rfc/rfc1929
- https://www.rfc-editor.org/rfc/rfc1961
- https://www.rfc-editor.org/rfc/rfc3089

### Appendices
#### RFC 1928 (Full Text)
{{#include ../../third_party/rfc/rfc1928.md:3}}

#### RFC 1929 (Full Text)
{{#include ../../third_party/rfc/rfc1929.md:3}}

#### RFC 1961 (Full Text)
{{#include ../../third_party/rfc/rfc1961.md:3}}

#### RFC 3089 (Full Text)
{{#include ../../third_party/rfc/rfc3089.md:3}}
