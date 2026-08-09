# Trojan Traffic Handling

## Purpose

Trojan's outer TLS behavior is only part of its deployment model. The server
also needs a deliberate policy for traffic that reaches the TLS listener but is
not a valid Trojan request.

A well-designed fallback path serves two goals:

- ordinary HTTPS/non-Trojan traffic receives ordinary service behavior,
- invalid proxy authentication does not produce an obvious proxy-specific
  banner.

## Valid Trojan Traffic

After TLS completes, a valid client sends the Trojan authentication field and a
well-formed request. The server validates both before opening the requested
outbound connection.

For valid traffic:

```text
Client
  │ TLS
  ▼
Trojan listener
  │ valid auth/request
  ▼
Destination
```

## Non-Trojan Traffic

The original Trojan design allows traffic that is not recognized as a valid
Trojan request to be passed to a configured fallback endpoint.

Conceptually:

```text
Client
  │ TLS
  ▼
Trojan listener
  ├── valid Trojan request ──> proxy destination
  └── other traffic ─────────> fallback service
```

The fallback service might be a local web server or another deliberately
configured endpoint. Its job is to return the normal application behavior that
an unauthenticated visitor should see.

## Why Fallback Behavior Matters

Without a fallback, malformed input may receive a connection reset or a
protocol-specific response that differs from the surrounding HTTPS service.
That makes the endpoint easier to distinguish operationally.

A fallback does not make a server "undetectable". It simply avoids unnecessary
behavioral differences for traffic that is not accepted as Trojan.

## Security Boundaries

Fallback forwarding must be treated as a security-sensitive routing rule.
Avoid forwarding unauthenticated traffic to:

- internal dashboards,
- metadata services,
- databases,
- administrative HTTP endpoints,
- or arbitrary private-network destinations.

Prefer a dedicated low-privilege web service whose public behavior is expected
and safe.

## Certificate and SNI Consistency

The TLS certificate, configured SNI, fallback content, and public DNS name
should tell a coherent story. For example, a certificate for one hostname with
a fallback page that redirects to an unrelated private domain is operationally
confusing and can make troubleshooting harder.

## Reverse Proxy Deployments

If Nginx, Caddy, or another reverse proxy is part of the path, document clearly
which component terminates TLS and which component sees the Trojan application
payload. The original Trojan framing assumes the Trojan endpoint receives the
post-TLS byte stream.

Transport wrappers such as WebSocket introduce another routing layer and should
not be treated as identical to the original direct-TLS layout.

## Operational Checks

When validating a deployment, test both accepted and rejected traffic:

1. A valid Trojan client can authenticate and reach a known destination.
2. An invalid password does not reach the proxy destination.
3. Ordinary HTTPS/non-Trojan traffic reaches the intended fallback.
4. The fallback cannot access sensitive private services.
5. Logs distinguish operational failures for administrators without leaking
   useful authentication details to remote clients.

## Chimera Notes

`Chimera_Client` currently documents Trojan together with WebSocket support, so
its traffic path can differ from the original direct-TLS Trojan deployment.
`Chimera_Server` should likewise be tested against the exact inbound transport
configuration in use.

This page therefore describes the baseline fallback model, not a guarantee that
every Chimera transport combination uses the same fallback mechanism.

## References

- Trojan protocol and fallback behavior:
  <https://trojan-gfw.github.io/trojan/protocol.html>
