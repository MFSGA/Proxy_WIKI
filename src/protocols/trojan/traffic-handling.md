# Trojan Traffic Handling

### Other Protocols (Fallback)
- Trojan listens on a TLS socket like a normal HTTPS service.
- After TLS completes, the server inspects the first application data packet.
- If the packet is not a valid Trojan request (wrong structure or password), the server treats it as "other protocols" and forwards the decrypted TLS stream to a preset endpoint (default `127.0.0.1:80`).
- The preset endpoint then controls the response, keeping the behavior indistinguishable from a real HTTPS site.

### Active Detection
- Probes without the correct structure or password are handed to the fallback endpoint.
- As a result, active scanners see ordinary HTTPS or HTTP behavior rather than a bespoke proxy banner.

### Passive Detection
- With a valid certificate, traffic is protected by TLS and resembles ordinary HTTPS.
- For HTTP destinations, there is only one RTT after the TLS handshake; non-HTTP traffic often looks like HTTPS keepalive or WebSocket.
- This similarity can help bypass ISP QoS that targets obvious proxy signatures.

### References
- https://github.com/trojan-gfw/trojan/issues/14
