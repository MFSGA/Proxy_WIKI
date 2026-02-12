# Rule Types and Their Effects

## Overview
In `chimera_client`, rules decide **which outbound group** handles a flow.
Evaluation is **top-to-bottom, first match wins**, consistent with Clash-rs and Mihomo behavior.

## Rule Evaluation Model
Input signals commonly include:
- domain indicators (SNI / Host),
- resolved destination IP,
- destination/source ports,
- process identity (when platform supports it),
- GeoIP/GeoSite datasets,
- and external rule-provider sets.

Typical actions route traffic to policy groups such as `DIRECT`, `REJECT`, `Proxy`, or `Auto`.

## Common Domain Rules
### `DOMAIN`
Exact hostname match.

```yaml
rules:
  - DOMAIN,api.github.com,Proxy
```

### `DOMAIN-SUFFIX`
Suffix match (includes subdomains).

```yaml
rules:
  - DOMAIN-SUFFIX,google.com,Proxy
```

### `DOMAIN-KEYWORD`
Substring-based domain match.
Use carefully to avoid overmatching.

```yaml
rules:
  - DOMAIN-KEYWORD,openai,Proxy
```

## IP and Network Rules
### `IP-CIDR`
IPv4 destination prefix match.

```yaml
rules:
  - IP-CIDR,1.1.1.0/24,DIRECT
```

### `IP-CIDR6`
IPv6 destination prefix match.

```yaml
rules:
  - IP-CIDR6,2606:4700::/32,DIRECT
```

### `SRC-IP-CIDR`
Source subnet match (useful on routers/gateways).

```yaml
rules:
  - SRC-IP-CIDR,192.168.50.0/24,GameProxy
```

### `GEOIP`
Country/region IP database match.

```yaml
rules:
  - GEOIP,CN,DIRECT
```

### `GEOSITE`
Domain category/list match.

```yaml
rules:
  - GEOSITE,geolocation-!cn,Proxy
```

## Port and Process Rules
### `DST-PORT`
Destination-port-based routing.

```yaml
rules:
  - DST-PORT,443,Proxy
```

### `SRC-PORT`
Source-port-based routing.

```yaml
rules:
  - SRC-PORT,60000-60100,DIRECT
```

### `PROCESS-NAME`
Executable name match.

```yaml
rules:
  - PROCESS-NAME,Telegram.exe,Proxy
```

### `PROCESS-PATH`
Full executable path match.

```yaml
rules:
  - PROCESS-PATH,/Applications/Discord.app/Contents/MacOS/Discord,Proxy
```

## Provider and Logical Rules
### `RULE-SET`
References remote/local provider-managed rule collections.

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
Final catch-all fallback.

```yaml
rules:
  - MATCH,DIRECT
```

## Recommended Ordering
1. Security blocks and guaranteed bypass (`REJECT`, private/local `DIRECT`).
2. Precise business rules (`DOMAIN`, `PROCESS-PATH`, `IP-CIDR`).
3. Provider/category rules (`RULE-SET`, `GEOSITE`).
4. Broad heuristics (`DOMAIN-KEYWORD`, `GEOIP`).
5. Final `MATCH` fallback.

## Compatibility Notes (clash-rs + Mihomo)
- First-match-wins semantics are aligned.
- Rule syntax is largely portable, but behavior still depends on DNS mode and inbound type.
- Process-level rules are platform-sensitive; validate on each target OS.
- GeoIP/GeoSite freshness directly impacts correctness.

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
- Keep intent explicit; avoid broad early rules.
- Version-control rule providers and refresh intervals.
- Enable connection decision logging when debugging mismatches.
- Validate DNS strategy and rule strategy together, especially with fake-IP/TUN.
