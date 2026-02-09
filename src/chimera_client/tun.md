# Tun Module

## Scope and Goals
TUN mode captures Layer-3 traffic from the host and sends it into the proxy pipeline without requiring each application to be proxy-aware. Compared with HTTP/SOCKS listeners, TUN is the closest to "system-wide proxy" behavior and is usually combined with policy routing and DNS control.

This page follows `clash-rs` semantics and config keys so future `chimera_client` parity is straightforward.

## Current Project Status
- `chimera_client` (current mainline) does not yet expose a `tun` block in its config parser.
- The TUN section below is the clash-rs-aligned target shape and operational guidance, not a statement that all fields are already active in `chimera_client`.
- Today, use SOCKS/listener-based workflows in `chimera_client` unless you are validating an in-progress TUN branch.

## Configuration Schema (Clash-rs Aligned)
```yaml
tun:
  enable: true
  device-id: "dev://utun1989"
  route-all: true
  gateway: "198.18.0.1/24"
  gateway-v6: "fd00:fac::1/64"
  mtu: 1500
  so-mark: 3389
  route-table: 2468
  dns-hijack: true
  # dns-hijack:
  #   - 1.1.1.1:53
  #   - 8.8.8.8:53
  # routes:
  #   - 1.1.1.1/32
  #   - 2001:4860:4860::8888/128
```

## Key Fields and Semantics
| Key | Type | Default | Notes |
| --- | --- | --- | --- |
| `enable` | `bool` | `false` | Enables TUN runtime. |
| `device-id` | `string` | `utun1989` | Accepts `dev://<name>`, `fd://<n>`, or plain name (treated as device name). |
| `gateway` | `CIDR string` | `198.18.0.1/24` | IPv4 address/prefix assigned to the TUN interface. |
| `gateway-v6` | `CIDR string` | unset | Optional IPv6 address/prefix for dual-stack TUN. |
| `route-all` | `bool` | `false` | Route all host traffic through TUN. |
| `routes` | `list<CIDR>` | empty | Used when `route-all: false` to route only selected prefixes. |
| `mtu` | `u16` | platform default | Runtime uses `1500` by default (`65535` on Windows) if unset. |
| `so-mark` | `u32` | unset | Linux fwmark for loop prevention / policy routing integration. |
| `route-table` | `u32` | `2468` | Linux policy-routing table used by TUN route-all path. |
| `dns-hijack` | `bool` or `list` | `false` | Enables DNS interception behavior in TUN path. |

## Device-ID Formats
- `dev://utun1989` or `utun1989`: create/use named TUN device.
- `dev://tun0`: common Linux style.
- `fd://3`: use an existing file descriptor, useful when another component owns TUN creation.

On macOS, the device name must use the `utun` prefix.

## Routing Behavior
### `route-all: true`
- Linux: uses policy routing rules and a dedicated route table (`route-table`).
- macOS/Windows: installs broad default-route entries through TUN.
- DNS hijack integration is tied to this path on Linux (policy rule for destination port `53`).

### `route-all: false`
- Only CIDRs in `routes` are routed through TUN.
- This is safer for partial rollout and avoids taking over all host traffic.

If both are configured, `route-all` takes precedence operationally.

## DNS Interaction
- `dns-hijack` controls DNS interception in TUN flow, but it does not replace a working DNS module config.
- For predictable domain-based routing, pair TUN with DNS settings (`dns.enable`, resolver list, fake-IP strategy where needed).
- In practice, `dns-hijack: true` is commonly paired with fake-IP mode in Clash-style deployments.

## Linux Notes (Policy Routing)
- Ensure `iproute2` (`ip` command) is available.
- Run with sufficient privileges (CAP_NET_ADMIN or root-equivalent).
- Prefer setting `so-mark` and keep it consistent with your external policy rules to avoid proxy loops.

Quick checks:
```bash
ip rule
ip route show table 2468
ip -6 route show table 2468
```

## Example Profiles
### Full-tunnel profile
```yaml
tun:
  enable: true
  device-id: "dev://utun1989"
  route-all: true
  gateway: "198.18.0.1/24"
  dns-hijack: true
```

### Split-route profile
```yaml
tun:
  enable: true
  device-id: "dev://tun0"
  route-all: false
  gateway: "198.18.0.1/24"
  routes:
    - 1.1.1.1/32
    - 8.8.8.8/32
  dns-hijack: false
```

### FD-based profile
```yaml
tun:
  enable: true
  device-id: "fd://3"
  route-all: true
  gateway: "198.18.0.1/24"
```

## Troubleshooting Checklist
- Verify process privileges first; TUN creation and route changes fail silently in many restricted environments.
- Confirm the interface exists (`ip addr`, `ifconfig`, or platform equivalent).
- Validate route/rule installation after startup.
- If DNS appears broken, verify the DNS listener is reachable and the system resolver path actually passes through TUN.
- If traffic loops or stalls, check `so-mark`/policy-rule alignment and existing host firewall rules.

## References and Alignment Notes
- Clash-rs config schema: `clash-lib/src/config/def.rs` (`TunConfig`, defaults, `dns-hijack` shape).
- Clash-rs config conversion: `clash-lib/src/config/internal/convert/tun.rs`.
- Clash-rs tun runtime and device parsing: `clash-lib/src/proxy/tun/inbound.rs`.
- Clash-rs route behavior: `clash-lib/src/proxy/tun/routes/{linux,macos,windows}.rs`.
- Clash-rs sample profile: `clash-bin/tests/data/config/tun.yaml`.
- Chimera_Client current parser snapshot: `clash-lib/src/config/def.rs` (no `tun` block yet on mainline).
