# Ports and Listeners

## Overview
Ports define where local applications, dashboards, and DNS resolvers connect to `chimera_client`. The naming follows Clash-style configuration, while `chimera_client` currently uses underscore keys for the same concepts.

## Port Map
| Clash key | chimera_client key | Role |
| --- | --- | --- |
| `port` / `http-port` | `port` | HTTP CONNECT proxy for browsers and system proxy settings. |
| `socks-port` | `socks_port` | SOCKS5 proxy for general applications; UDP associate support is optional. |
| `mixed-port` | `mixed_port` | Combined HTTP + SOCKS5 listener on one port. |
| `redir-port` | `redir_port` | Linux TCP transparent redirect (iptables REDIRECT). |
| `tproxy-port` | `tproxy_port` | Linux TPROXY for TCP/UDP transparent proxying. |
| `external-controller` | `external_controller` | REST API port for dashboards and automation. |
| `dns.listen` | `dns.listen` | Local DNS listener for fake-IP or policy DNS. |

## What Each Port Does
### HTTP proxy port
Accepts HTTP CONNECT requests and plain HTTP proxy traffic. It is the default choice for browsers and OS-level proxy settings.

### SOCKS5 port
Accepts SOCKS5 connections from applications that speak SOCKS natively. It is commonly used by developer tools and power users.

### Mixed port
Accepts both HTTP and SOCKS5 on a single port. Use this to simplify local proxy configuration when only one port can be configured.

### Redir port
Used for TCP transparent proxying on Linux via iptables REDIRECT. It only captures TCP and requires kernel-level redirection rules.

### TProxy port
Used for Linux TPROXY to capture both TCP and UDP. It requires policy routing and `fwmark` rules, and is often paired with TUN or redirection tooling.

### Controller port
Exposes the REST API used by dashboards, mobile shells, and automation. Bind it to localhost unless remote access is required.

### DNS listen port
Accepts DNS queries from the system or from a TUN stack. It is typically paired with fake-IP or split-horizon DNS rules.

## chimera_client Support Notes
- `socks_port` is the only inbound port wired today; UDP associate is currently disabled.
- `port`, `mixed_port`, `redir_port`, and `tproxy_port` are reserved for compatibility but not yet implemented.
- The DNS server and controller listener are under active development; keep them local unless you are testing.

## Configuration Examples
### Minimal chimera_client
```yaml
bind_address: "127.0.0.1"
allow_lan: false
socks_port: 7891
dns:
  enable: false
  ipv6: false
```

### Clash or Mihomo Layout (Reference)
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
