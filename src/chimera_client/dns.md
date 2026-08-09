# DNS Module

## Purpose

DNS is part of the routing pipeline, not just a name-to-address lookup service.
The resolver strategy affects whether domain rules remain usable, whether TUN
traffic can be classified correctly, and whether DNS requests bypass the proxy
unexpectedly.

A stable DNS setup should answer three questions clearly:

1. Which resolver handles a query?
2. Does the client keep the original domain identity for later rule matching?
3. Does DNS traffic itself follow the intended proxy or direct path?

## Operating Modes

| Mode | Best fit | Advantages | Trade-offs |
| --- | --- | --- | --- |
| System / DNS disabled | Simple app-level proxying | Least invasive, easiest to debug | Depends on OS resolver behavior |
| Real-IP / `redir-host` style | Conservative enhanced DNS | Applications receive real addresses | Domain identity can be harder to retain in transparent flows |
| Fake-IP | TUN and domain-heavy routing | Preserves domain intent for later connection matching | Requires exclusions and careful DNS integration |

Start with the system resolver or real-IP behavior when validating a new setup.
Introduce Fake-IP only when the routing model benefits from it.

## Resolver Pipeline

A Clash-style enhanced resolver generally follows this conceptual sequence:

```text
application query
      |
      v
hosts/cache lookup
      |
      v
policy/default resolver selection
      |
      v
upstream DNS query
      |
      +----> fallback / validation path when configured
      |
      v
cache + answer
      |
      v
rule engine / connection flow
```

The exact fallback and policy behavior depends on the current
`chimera_client` implementation and should not be assumed to match every Mihomo
edge case.

## Conservative Configuration

For application-level SOCKS5 or HTTP proxying, keeping enhanced DNS disabled is
a useful baseline:

```yaml
dns:
  enable: false
  ipv6: false
```

If this works but an enhanced-DNS profile does not, the failure is probably in
the DNS interception/resolver path rather than the outbound proxy itself.

## Local DNS Listener

A local listener lets the operating system, TUN path, or other applications send
queries directly to `chimera_client`:

```yaml
dns:
  enable: true
  listen: 127.0.0.1:1053
  ipv6: false
```

During development, keep the listener on loopback. Binding DNS to a LAN or public
interface can expose an unintended resolver service.

## Fake-IP Example

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
```

Fake-IP exclusions should be kept small and understandable. Large copied filter
lists can hide routing mistakes and make failures difficult to reproduce.

## Policy and Fallback Example

```yaml
dns:
  enable: true
  listen: 127.0.0.1:1053
  ipv6: false

  nameserver:
    - https://dns.alidns.com/dns-query

  fallback:
    - 9.9.9.9

  fallback-filter:
    geoip: true
    geoip-code: CN
```

The schema and resolver hooks for policy/fallback behavior exist in the current
client documentation, but full behavioral parity with Mihomo should be verified
before relying on unusual edge cases.

## DNS and Rules

DNS mode directly affects the rule engine:

- Domain-based rules need access to the original hostname or equivalent metadata.
- IP rules depend on the resolved destination address.
- Fake-IP is most useful when an application resolves first and connects later,
  because the client can map the synthetic address back to the original domain.
- A DNS request that bypasses the intended resolver path can cause apparently
  random rule mismatches.

When debugging rules, inspect DNS before changing rule order blindly.

## DNS and TUN

TUN deployments often combine three separate mechanisms:

1. host traffic capture,
2. DNS interception or resolver redirection,
3. enhanced DNS such as Fake-IP.

`dns-hijack` in the TUN configuration does not replace a valid DNS configuration.
It only controls how captured DNS traffic is redirected into the DNS path.
See [Tun Module](./tun.md) for the routing side.

## Upstream Resolver Guidance

When choosing upstreams:

- keep at least one simple resolver path available while debugging;
- verify that encrypted DNS endpoint hostnames can be bootstrapped;
- avoid mixing many upstreams until the basic path is known to work;
- consider whether DNS itself should be proxied or sent directly;
- treat resolver latency, failure, and blocking as routing signals, not just DNS
  errors.

## Compatibility Notes

The current documentation describes support or runtime hooks for:

- the system resolver path,
- a local DNS listener,
- enhanced/Fake-IP resolution,
- nameserver policy and fallback structures,
- and `respect-rules`-style DNS dialing hooks.

These capabilities are aligned with the Clash family, but this Wiki should not
claim blanket Mihomo parity. Configuration syntax can also differ between the
external Clash-style form and the client's normalized internal representation.

## Troubleshooting

Use this order when DNS-related behavior looks wrong:

1. Confirm ordinary network connectivity without enhanced DNS.
2. Confirm the local DNS listener is actually reachable.
3. Query the listener directly, for example:

   ```bash
   dig @127.0.0.1 -p 1053 example.com
   ```

4. Check whether the OS or TUN path really sends DNS to that listener.
5. Temporarily use one simple upstream resolver to isolate DoH/DoT problems.
6. Inspect timeout, TLS, bootstrap, and validation errors in logs.
7. If Fake-IP is enabled, verify that the affected domain is not unexpectedly
   included in the filter list.
8. If rules are wrong, compare the domain seen by the rule engine with the final
   resolved IP.

## Related Pages

- [Ports and Listeners](./ports.md)
- [Tun Module](./tun.md)
- [Rule Types and Their Effects](./rules.md)
