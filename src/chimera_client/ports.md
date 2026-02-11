# Ports and Listeners

## Overview
Ports define how local applications, dashboards, and DNS resolvers enter `chimera_client`.
This page cross-references Clash-rs and Mihomo semantics, then states the current `chimera_client` status explicitly.

## Key Mapping
| Clash / Mihomo key | chimera_client key | Purpose |
| --- | --- | --- |
| `port` / `http-port` | `port` | HTTP CONNECT/plain proxy listener |
| `socks-port` | `socks_port` | SOCKS5 listener |
| `mixed-port` | `mixed_port` | Shared HTTP+SOCKS listener |
| `redir-port` | `redir_port` | Linux TCP transparent REDIRECT |
| `tproxy-port` | `tproxy_port` | Linux TPROXY (TCP/UDP) |
| `external-controller` | `external_controller` | REST controller endpoint |
| `dns.listen` | `dns.listen` | Local DNS socket |

## Behavior by Listener Type
### HTTP proxy (`port` / `http-port`)
- Typical browser/system-proxy entrypoint.
- Expects HTTP CONNECT and HTTP proxy semantics.

### SOCKS5 (`socks-port`)
- Most widely compatible app-level inbound.
- Supports direct app integration without kernel routing changes.

### Mixed (`mixed-port`)
- Single port for both HTTP and SOCKS protocols.
- Useful where clients only allow one proxy endpoint setting.

### Redir (`redir-port`)
- Linux TCP transparent capture via iptables REDIRECT.
- Does not capture UDP by itself.

### TProxy (`tproxy-port`)
- Transparent TCP+UDP capture path on Linux.
- Requires policy routing (`fwmark` + route table) and firewall integration.

### External controller (`external-controller`)
- Management API for dashboards and automation.
- Prefer loopback binding unless remote access is required.

### DNS listen (`dns.listen`)
- Local resolver socket used by fake-IP/split-DNS workflows.
- Usually paired with TUN or transparent proxy mode.

## Compatibility Status Matrix
| Feature | chimera_client now | clash-rs / Mihomo |
| --- | --- | --- |
| SOCKS5 inbound | Available | Available |
| SOCKS UDP associate | Limited / disabled in current notes | Available |
| HTTP inbound | Reserved/planned | Available |
| Mixed inbound | Reserved/planned | Available |
| Redir inbound | Reserved/planned | Available |
| TProxy inbound | Reserved/planned | Available |
| External controller | Under active development | Mature |
| Local DNS listener | Under active development | Mature |

## Recommended Usage Today
- Prefer `socks_port` as the stable ingress.
- Keep management and DNS bindings on `127.0.0.1` during development.
- Treat non-SOCKS inbounds as compatibility keys unless your branch explicitly enables them.

## Configuration Examples
### Minimal `chimera_client` profile (current-safe)
```yaml
bind_address: "127.0.0.1"
allow_lan: false
socks_port: 7891
dns:
  enable: false
  ipv6: false
```

### Clash / Mihomo reference layout
```yaml
port: 7890
socks-port: 7891
mixed-port: 7892
redir-port: 7893
tproxy-port: 7894
external-controller: 127.0.0.1:9090
dns:
  listen: 127.0.0.1:1053
```

## Migration Notes
When importing a profile from Mihomo or clash-rs:
1. keep original keys for readability,
2. map to `chimera_client` accepted keys where necessary,
3. disable inbounds not yet active,
4. verify with live connection tests before enabling LAN exposure.
