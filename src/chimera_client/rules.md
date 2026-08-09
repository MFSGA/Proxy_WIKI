# Rule Types and Their Effects

## Purpose

Rules decide which outbound policy handles a connection. In the Clash-style
model used by `chimera_client`, evaluation is ordered: rules are checked from
top to bottom and the first matching rule wins.

That makes rule order just as important as rule syntax. A valid rule placed too
late can be effectively unreachable because an earlier rule already captured
the flow.

## Rule Evaluation Model

A routing decision can use several kinds of metadata:

- domain name, SNI, or HTTP host,
- resolved destination IP,
- source or destination port,
- source subnet,
- process identity when supported by the platform,
- GeoIP/GeoSite datasets,
- and external rule-provider sets.

The selected target is usually an outbound or policy group such as `DIRECT`,
`REJECT`, `Proxy`, or `Auto`.

## Domain Rules

### `DOMAIN`

Matches one exact hostname.

```yaml
rules:
  - DOMAIN,api.github.com,Proxy
```

Use this for the most precise domain-based exceptions.

### `DOMAIN-SUFFIX`

Matches a domain suffix and its subdomains.

```yaml
rules:
  - DOMAIN-SUFFIX,google.com,Proxy
```

This is usually preferable to a broad keyword when an entire domain tree should
share the same policy.

### `DOMAIN-KEYWORD`

Matches a substring in the domain name.

```yaml
rules:
  - DOMAIN-KEYWORD,openai,Proxy
```

Keyword rules are easy to overmatch. Keep them below more precise domain rules
unless broad matching is intentional.

## IP and Network Rules

### `IP-CIDR`

Matches an IPv4 destination prefix.

```yaml
rules:
  - IP-CIDR,1.1.1.0/24,DIRECT
```

### `IP-CIDR6`

Matches an IPv6 destination prefix.

```yaml
rules:
  - IP-CIDR6,2606:4700::/32,DIRECT
```

### `SRC-IP-CIDR`

Matches the source subnet. This is most useful when the client is acting as a
router or gateway for multiple devices.

```yaml
rules:
  - SRC-IP-CIDR,192.168.50.0/24,GameProxy
```

### `GEOIP`

Matches an IP against a geographic database.

```yaml
rules:
  - GEOIP,CN,DIRECT
```

GeoIP results are only as accurate as the installed dataset. Treat database
freshness as part of the routing configuration.

### `GEOSITE`

Matches a domain against a maintained category/list dataset.

```yaml
rules:
  - GEOSITE,geolocation-!cn,Proxy
```

As with GeoIP, behavior depends on the data files actually available to the
runtime.

## Port and Process Rules

### `DST-PORT`

Matches the remote destination port.

```yaml
rules:
  - DST-PORT,443,Proxy
```

Port-only routing is broad. Place service-specific domain rules above it when
possible.

### `SRC-PORT`

Matches the local/source port.

```yaml
rules:
  - SRC-PORT,60000-60100,DIRECT
```

### `PROCESS-NAME`

Matches the executable name when process inspection is supported.

```yaml
rules:
  - PROCESS-NAME,Telegram.exe,Proxy
```

### `PROCESS-PATH`

Matches a full executable path.

```yaml
rules:
  - PROCESS-PATH,/Applications/Discord.app/Contents/MacOS/Discord,Proxy
```

Process rules are platform-sensitive and can be affected by permissions,
application launchers, sandboxing, and executable path changes. Validate them
on every target operating system.

## Rule Providers

`RULE-SET` delegates matching to a named rule provider.

```yaml
rule-providers:
  streaming:
    type: http
    behavior: domain
    url: https://example.com/streaming.yaml
    interval: 86400
    path: ./ruleset/streaming.yaml

rules:
  - RULE-SET,streaming,Proxy
```

Rule providers make large policy sets easier to maintain, but introduce another
runtime dependency. A stale, unavailable, or incompatible provider can make a
routing policy behave differently from its source configuration.

For important providers, keep the source, update interval, expected behavior,
and local cache path explicit.

## Final Fallback

`MATCH` is the catch-all rule and should normally be last.

```yaml
rules:
  - MATCH,DIRECT
```

Anything after `MATCH` is unreachable.

## Recommended Ordering

A practical rule set usually moves from narrow/high-priority decisions to broad
fallbacks:

1. explicit blocks and local/private bypass rules;
2. exact domain or process exceptions;
3. specific IP and port rules;
4. provider/category rules such as `RULE-SET` and `GEOSITE`;
5. broad heuristics such as `DOMAIN-KEYWORD` and `GEOIP`;
6. final `MATCH` fallback.

This is a guideline rather than a mandatory ordering. The important property is
that earlier rules intentionally take priority over later ones.

## Example Policy

```yaml
rules:
  - DOMAIN,internal.example.com,DIRECT
  - DOMAIN-SUFFIX,corp.example.com,DIRECT
  - PROCESS-NAME,Telegram.exe,Proxy
  - GEOSITE,category-ads-all,REJECT
  - GEOIP,CN,DIRECT
  - RULE-SET,streaming,Proxy
  - MATCH,Auto
```

Read the example from top to bottom: an exact corporate exception wins before a
broader geographic or provider rule can see the same connection.

## DNS Interaction

Many apparent rule failures are actually DNS-context failures.

- Domain rules require the runtime to know the original hostname.
- IP rules depend on the address returned by the resolver.
- Fake-IP can help preserve domain intent through a later connection attempt.
- Transparent and TUN traffic can lose domain context if DNS bypasses the
  client's intended resolver path.

When a domain rule works through SOCKS5 but fails through TUN, compare the DNS
path before changing the rule itself. See [DNS Module](./dns.md).

## Compatibility Notes

The core first-match model and common Clash rule syntax are intended to remain
portable across `chimera_client`, clash-rs, and Mihomo. Exact support still
varies by runtime feature and platform.

In particular:

- process matching is platform-dependent;
- GeoIP/GeoSite behavior depends on local datasets;
- provider behavior depends on provider format and refresh success;
- DNS mode and inbound type can change the metadata available to a rule;
- newer Mihomo-only rule types should not be assumed to work unless they are
  explicitly implemented by the selected client core.

## Troubleshooting

When a connection selects the wrong outbound, debug the decision in this order:

1. Identify the first rule that actually matched, not the rule you expected to
   match.
2. Check whether an earlier broad rule shadows the intended one.
3. Confirm the policy/group named by the rule exists.
4. For domain rules, verify that the runtime still knows the hostname.
5. For IP/GeoIP rules, verify the resolved address and database state.
6. For process rules, confirm the observed executable name/path on that OS.
7. For `RULE-SET`, confirm the provider loaded and refreshed successfully.
8. Temporarily reduce the rules to a few explicit entries plus `MATCH` to isolate
   the problem.

## Related Pages

- [DNS Module](./dns.md)
- [Ports and Listeners](./ports.md)
- [Tun Module](./tun.md)
