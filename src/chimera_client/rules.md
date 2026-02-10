# Rule Types and Their Effects

## Overview
In `chimera_client`, rules decide **which outbound group** a flow should use.
Rules are matched **top to bottom**, and the first matched rule wins. Place highly specific rules first, and broad fallback rules near the end.

## Rule Evaluation Basics
- First-match-wins: once a rule matches, later rules are ignored.
- Input signals: domain (SNI/Host), resolved IP, destination port, process name/path, network type, and GeoIP/GeoSite datasets.
- Common action: route to a policy group such as `DIRECT`, `REJECT`, `Proxy`, or `Auto`.

## Common Domain Rules
### `DOMAIN`
Matches an exact domain name.

Use when:
- You want strict and deterministic matching for a single host.

Example:
```yaml
rules:
  - DOMAIN,api.github.com,Proxy
```

### `DOMAIN-SUFFIX`
Matches a domain suffix, including subdomains.

Use when:
- You need to route an entire service namespace.

Example:
```yaml
rules:
  - DOMAIN-SUFFIX,google.com,Proxy
```

### `DOMAIN-KEYWORD`
Matches domains containing a keyword.

Use when:
- Service domains are scattered and suffix rules are inconvenient.

Caution:
- Overmatching risk is higher than `DOMAIN` / `DOMAIN-SUFFIX`.

Example:
```yaml
rules:
  - DOMAIN-KEYWORD,openai,Proxy
```

## IP and Network Rules
### `IP-CIDR`
Matches destination IPv4 CIDR blocks.

Use when:
- You need deterministic routing independent of domain names.

Example:
```yaml
rules:
  - IP-CIDR,1.1.1.0/24,DIRECT
```

### `IP-CIDR6`
Matches destination IPv6 CIDR blocks.

Use when:
- Your environment is dual-stack and IPv6 needs explicit policy.

Example:
```yaml
rules:
  - IP-CIDR6,2606:4700::/32,DIRECT
```

### `SRC-IP-CIDR`
Matches source IP CIDR (useful in gateway/router mode).

Use when:
- Different LAN clients should use different egress paths.

Example:
```yaml
rules:
  - SRC-IP-CIDR,192.168.50.0/24,GameProxy
```

### `GEOIP`
Matches destination IP by country/region code via GeoIP database.

Use when:
- You want country-based traffic splitting.

Example:
```yaml
rules:
  - GEOIP,CN,DIRECT
```

### `GEOSITE`
Matches domain sets from curated geosite categories.

Use when:
- You prefer maintained domain lists (e.g. `geolocation-!cn`, `category-ads-all`).

Example:
```yaml
rules:
  - GEOSITE,geolocation-!cn,Proxy
```

## Port and Process Rules
### `DST-PORT`
Matches destination port.

Use when:
- You need service-type routing (e.g., game ports, custom app ports).

Example:
```yaml
rules:
  - DST-PORT,443,Proxy
```

### `SRC-PORT`
Matches source port.

Use when:
- A local application uses fixed source ports and requires special handling.

Example:
```yaml
rules:
  - SRC-PORT,60000-60100,DIRECT
```

### `PROCESS-NAME`
Matches executable name.

Use when:
- Desktop scenario requires per-app split routing.

Example:
```yaml
rules:
  - PROCESS-NAME,Telegram.exe,Proxy
```

### `PROCESS-PATH`
Matches full executable path.

Use when:
- You need stronger process-level precision than `PROCESS-NAME`.

Example:
```yaml
rules:
  - PROCESS-PATH,/Applications/Discord.app/Contents/MacOS/Discord,Proxy
```

## Logical and Provider Rules
### `RULE-SET`
References an external provider-defined rule collection.

Use when:
- You want centralized, auto-updated policy sets.

Example:
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

### `MATCH`
Catch-all fallback rule.

Use when:
- You need a deterministic default action for unmatched traffic.

Example:
```yaml
rules:
  - MATCH,DIRECT
```

## Practical Ordering Template
A practical order is:
1. Hard blocks / safe bypass (`REJECT`, `DIRECT` for local or private ranges).
2. Precise business rules (`DOMAIN`, `PROCESS-PATH`, `IP-CIDR`).
3. Curated sets (`GEOSITE`, `RULE-SET`).
4. Broad heuristics (`DOMAIN-KEYWORD`, `GEOIP`).
5. Final fallback (`MATCH`).

## Minimal Mixed Example
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

## Operational Tips
- Keep rule intent explicit; avoid overlapping broad rules early in the list.
- Validate GeoIP/GeoSite databases and provider freshness regularly.
- For debugging, enable connection logs and verify which rule each flow hits.
- In transparent proxy mode, ensure DNS strategy and rule logic are aligned to avoid mismatches.
