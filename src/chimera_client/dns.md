# DNS Module

## Scope and Goals
The DNS module is responsible for domain resolution before policy routing. Its goals are predictable rule matching, low latency, and safe resolution under hostile or unreliable networks. Configuration typically lives under a `dns` block in the Clash-style YAML and can be hot-reloaded.

## Configuration Areas
- Upstream resolvers: define UDP, DoH, or DoT endpoints, and choose which transport is allowed per environment.
- Resolution mode: select fake-IP versus real-IP behavior, and configure the fake-IP pool plus domain filters that must bypass synthesis.
- Split-horizon policies: map domain suffixes or rule sets to specific resolvers, including private zones and regional endpoints.
- Fallback strategy: add fallback resolvers and health checks for blocked, poisoned, or slow upstreams.
- Cache behavior: tune TTL caps, cache size, and prefetch rules to reduce latency without stale answers.
- Safety controls: enable hosts overrides, blocklists, or ECS avoidance to limit leakage and improve consistency.
- Bootstrap resolvers: keep a small plain DNS list so DoH or DoT endpoints can be resolved without circular dependencies.

## Resolution Modes
- Fake-IP mode: synthesizes IPs so traffic can be steered by domain rules even after apps connect by IP. This works best with TUN or transparent proxying but requires careful fake-IP filtering for local or IP-sensitive services.
- Real-IP mode: returns actual addresses to applications, which is simpler for LAN workflows and strict DNS consumers but reduces the ability to enforce domain rules after connection.
- Hybrid usage: keep fake-IP enabled for general traffic and add explicit fake-IP filters for mDNS, LAN suffixes, or time sync domains.

## Resolver Selection Flow
1. Apply hosts overrides and consult the in-memory cache.
2. Select a resolver based on domain policies or rule sets.
3. Query primary resolvers in order or in parallel.
4. If responses fail validation or time out, trigger fallback resolvers.
5. Cache the response with TTL caps and return it to the caller.

## Configuration References
### chimera_client (current)
The current implementation relies on the system resolver. Keep DNS disabled unless you are testing the in-progress DNS server, and override IPv6 only if you need to suppress AAAA answers.

```yaml
dns:
  enable: false
  ipv6: false
```

### Mihomo / Clash (reference projects)
This block mirrors the Clash-compatible DNS schema as used by Mihomo. It is usable in those projects and serves as a target shape for chimera_client parity.

```yaml
dns:
  enable: true
  listen: 127.0.0.1:1053
  ipv6: false
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  fake-ip-filter:
    - "*.lan"
    - "*.local"
  default-nameserver:
    - 1.1.1.1
    - 8.8.8.8
  nameserver:
    - https://dns.alidns.com/dns-query
    - tls://1.1.1.1:853
  fallback:
    - 9.9.9.9
  fallback-filter:
    geoip: true
    geoip-code: CN
```

## Operational Guidance
- Prefer explicit resolver policies when different traffic classes require distinct egress paths.
- Keep fake-IP exclusions narrow to avoid bypassing rule evaluation unintentionally.
- Use a small bootstrap resolver list for DoH or DoT endpoints that must resolve at startup.
- Tune cache caps with observed traffic patterns rather than using defaults blindly.
- Monitor fallback usage; spikes often indicate upstream blocks or transport failures.

## Troubleshooting Checklist
- Confirm the local DNS listener is reachable (for example, `dig @127.0.0.1 -p 1053 example.com`).
- Verify the system resolver or TUN stack actually points at the client listener.
- Revisit fake-IP filters for domains that must keep real IPs.
- Inspect logs for upstream timeouts, TLS handshake errors, or poisoned responses.
- Temporarily force a single UDP resolver to isolate DoH or DoT connectivity issues.
