# Ports and Listeners

## Purpose

Listeners define how local applications and operating-system traffic enter
`chimera_client`. They are the first boundary between an application and the
proxy core, so listener selection should be treated separately from outbound
protocol selection.

For most deployments, start with an application-level listener such as SOCKS5
or HTTP before enabling transparent or TUN-based capture.

## Listener Overview

| Configuration key | Role | Typical use | Notes |
| --- | --- | --- | --- |
| `port` / `http-port` | HTTP proxy listener | Browsers, system HTTP proxy | Primarily TCP proxy traffic |
| `socks-port` | SOCKS5 listener | General application proxying | Good baseline for local testing |
| `mixed-port` | HTTP + SOCKS5 listener | One shared application endpoint | Convenient when clients expose only one proxy field |
| `redir-port` | Transparent redirect listener | Linux gateway/router setups | Primarily TCP redirect workflows |
| `tproxy-port` | Transparent proxy listener | Linux TCP/UDP interception | Requires firewall and policy-routing integration |
| `external-controller` | Management API | GUI, dashboards, automation | Bind to loopback unless remote access is intentional |
| `dns.listen` | DNS listener | Local DNS interception/resolution | Usually used with enhanced DNS or TUN |

> Availability can depend on build features, platform support, and the exact
> `chimera_client` revision. A configuration key being accepted does not by
> itself guarantee that the corresponding runtime path is enabled.

## Listener Selection

### SOCKS5

SOCKS5 is the safest starting point when validating a new profile. It does not
require route changes and is supported by a wide range of applications.

```yaml
bind_address: "127.0.0.1"
allow_lan: false
socks_port: 7891
```

Use SOCKS5 first when you want to separate proxy-core behavior from operating
system routing and DNS interception issues.

### HTTP Proxy

An HTTP proxy listener is convenient for browsers and operating-system proxy
settings. HTTPS traffic normally enters through HTTP `CONNECT` tunneling.

```yaml
port: 7890
```

### Mixed Listener

A mixed listener accepts both HTTP-proxy and SOCKS-style clients on one port.
It is useful for desktop setups where exposing a single endpoint is simpler
than managing separate HTTP and SOCKS ports.

```yaml
mixed-port: 7892
```

### Transparent Listeners

`redir-port` and `tproxy-port` are intended for routing-level interception,
primarily on Linux. They should not be treated as drop-in replacements for
SOCKS5 or HTTP listeners.

Transparent proxying normally also requires:

- firewall rules,
- loop-prevention rules,
- policy routing for TProxy deployments,
- and a DNS strategy that preserves enough domain information for rule
  matching.

For host-wide interception, also see [Tun Module](./tun.md).

## Controller and DNS Bindings

Management and DNS listeners deserve stricter exposure rules than ordinary
local proxy listeners.

During development, prefer loopback-only bindings:

```yaml
external-controller: 127.0.0.1:9090

dns:
  enable: true
  listen: 127.0.0.1:1053
```

Do not expose the controller or DNS listener to a LAN or public interface unless
you have intentionally configured access controls and understand the security
impact.

## Example Local Profile

The following layout keeps all application-facing services local while making
listener roles explicit:

```yaml
bind_address: "127.0.0.1"
allow_lan: false

port: 7890
socks_port: 7891
mixed_port: 7892
external_controller: "127.0.0.1:9090"

dns:
  enable: false
```

Exact accepted key spelling can vary between compatibility layers. When
importing Clash/Mihomo profiles, preserve the original profile where practical
and verify the normalized runtime configuration produced by the client.

## Platform and Compatibility Notes

- Application-level HTTP and SOCKS listeners are the easiest paths to validate
  across platforms.
- Transparent redirect and TProxy workflows are platform-specific and require
  operating-system network configuration outside the YAML file.
- TUN support has its own privilege, routing, and DNS requirements; see
  [Tun Module](./tun.md).
- Listener availability may be gated by Cargo features or runtime build choices.
- Controller behavior should be treated as an API surface rather than a proxy
  protocol endpoint.

## Troubleshooting

When a local application cannot connect through the core, check the listener
before debugging outbound protocols:

1. Confirm the process is running and the expected port is listening.
2. Verify the application points to the correct listener type and port.
3. Confirm the listener is bound to the expected address (`127.0.0.1`, LAN IP,
   or wildcard address).
4. Check whether `allow_lan` or equivalent exposure settings block remote
   clients.
5. Test with a minimal SOCKS5 or HTTP profile before enabling TUN, Redir, or
   TProxy.
6. If routing works by IP but domain rules fail, inspect the DNS path as well.

## Related Pages

- [DNS Module](./dns.md)
- [Tun Module](./tun.md)
- [Rule Types and Their Effects](./rules.md)
