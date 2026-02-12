# DNS Module

## Scope and Goals
The DNS module decides how domains are resolved before policy routing.
In Clash-family clients, DNS behavior strongly affects rule hit accuracy, latency, and anti-pollution resilience.

This page uses clash-rs and Mihomo as reference behavior, while marking current `chimera_client` maturity.

## Why DNS Design Matters
- Domain rules require stable mapping between query results and connection flow.
- Fake-IP mode can preserve domain intent even when apps later connect by IP.
- Resolver choice impacts censorship resistance, startup reliability, and privacy leakage.

## Configuration Areas
- **Upstreams**: UDP / DoH / DoT endpoints and ordering.
- **Mode**: fake-IP vs real-IP.
- **Policy routing for DNS**: nameserver-policy and fallback strategy.
- **Cache strategy**: capacity, TTL bounds, prefetch behavior.
- **Safety controls**: fake-IP filters, hosts overrides, ECS handling.
- **Bootstrap**: plain DNS for resolving encrypted DNS endpoints.

## Mode Comparison
| Mode | Advantages | Trade-offs | Typical use |
| --- | --- | --- | --- |
| `fake-ip` | Better domain-rule retention after connect | Needs careful filter list | TUN / transparent proxy deployments |
| `redir-host` / real-IP style | Simpler app compatibility | Domain intent can be lost after IP connect | App-level proxy with conservative DNS goals |

## Resolver Selection Flow (Reference)
1. Check hosts override and cache.
2. Choose resolver by policy (domain/set-based) or default list.
3. Query primary resolver(s).
4. Run fallback path when validation/latency criteria fail.
5. Cache and return answer.

## Compatibility Status
| Capability | chimera_client now | clash-rs / Mihomo reference |
| --- | --- | --- |
| System resolver passthrough | Primary path | Also supported |
| Clash-style local DNS server | In progress | Mature |
| Fake-IP workflow | Target state | Mature |
| Nameserver policy / fallback filter | Target state | Mature |

## Configuration References
### `chimera_client` (current conservative profile)
```yaml
dns:
  enable: false
  ipv6: false
```

### Clash/Mihomo-aligned target schema
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

## Practical Guidance
- Start from real-IP/system resolver behavior for stability.
- Enable fake-IP only after validating domain-rule workflows end-to-end.
- Keep fake-IP exclusions narrow and auditable.
- Track fallback hit ratio; sudden growth often means upstream degradation or blocking.

## Troubleshooting Checklist
- Verify listener reachability: `dig @127.0.0.1 -p 1053 example.com`.
- Ensure OS/TUN resolver path really points to the client listener.
- Inspect logs for timeout, TLS, or response-validation failures.
- Test with one plain UDP resolver to isolate encrypted-DNS transport issues.

## Alignment References
- clash-rs: DNS schema and runtime behavior under `clash-lib/src/config` and DNS runtime modules.
- Mihomo: production reference for enhanced-mode, nameserver-policy, and fallback-filter semantics.
