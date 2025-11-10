# Trojan

### Highlights
- Uses TLS as the outer layer; the first payload is a simple password-based handshake.
- Designed to look like normal HTTPS while granting full-duplex streams after auth.
- Commonly deployed alongside CDN fronting with SNI-based routing.

### Flow
1. Client performs a TLS handshake to the Trojan server using a legitimate SNI.
2. After TLS is established, the client writes a password plus target address in the Trojan format.
3. Server validates the password; on success it connects to the target.
4. Both sides exchange data within the encrypted TLS channel until termination.

### Configuration Snippet

### Strengths
- Leverages well-tested TLS stacks; inherits forward secrecy and ALPN capabilities.
- Simple credential model makes operational management straightforward.
- Can multiplex multiple users through one TLS endpoint while staying indistinguishable from HTTPS.

### Limitations
- Each password maps to a virtual user; revocation requires redeploying configs.
- TLS certificate management (issuance, renewal) is mandatory.
- Middleboxes that block unknown ALPNs may require tweaking to match mainstream HTTPS fingerprints.
