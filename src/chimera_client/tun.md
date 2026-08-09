# Tun Module

## Purpose

TUN mode captures IP traffic at the operating-system network layer and sends it
into the proxy pipeline without requiring each application to configure an HTTP
or SOCKS proxy.

It is the closest `chimera_client` mode to a host-wide proxy, but it is also the
mode with the most external dependencies: interface creation, privileges,
routes, loop prevention, DNS handling, and platform-specific behavior all need
to work together.

For a new deployment, validate an application-level listener first. Only enable
TUN after the core, outbound protocol, and basic rule set are already known to
work.

## Current Status

The current client documentation exposes a `tun` configuration block and carries
TUN configuration into the internal runtime representation. Actual behavior is
still dependent on:

- whether the build includes the required TUN feature/runtime code,
- the target operating system,
- sufficient privileges,
- route-management support,
- and a compatible DNS configuration.

A successfully parsed `tun` block does not by itself prove that the host routing
setup is active.

## Core Configuration

```yaml
tun:
  enable: true
  device-id: "dev://tun0"
  route-all: true
  gateway: "198.18.0.1/24"
  mtu: 1500
  dns-hijack: true
```

The exact set of accepted keys follows the current `chimera_client`/clash-rs
configuration path rather than being a promise of full Mihomo key compatibility.

## Key Fields

| Key | Purpose | Operational notes |
| --- | --- | --- |
| `enable` | Enables the TUN path | Other TUN fields are irrelevant while disabled |
| `device-id` | Selects or identifies the TUN device | May be platform-specific |
| `gateway` | IPv4 address/prefix for the TUN interface | Commonly uses a dedicated private/benchmark range |
| `gateway-v6` | Optional IPv6 address/prefix | Needed when IPv6 is intentionally carried through TUN |
| `route-all` | Full-tunnel routing switch | Broadest and most invasive mode |
| `routes` | Prefix list for split routing | Used when only selected networks should enter TUN |
| `mtu` | Interface MTU | Useful when diagnosing fragmentation or PMTU problems |
| `so-mark` | Linux packet mark | Helps integrate loop prevention and policy routing |
| `route-table` | Linux policy-routing table | Avoid conflicts with existing host route tables |
| `dns-hijack` | Redirects captured DNS into the client DNS path | Requires a working DNS module configuration |

## Deployment Modes

### Full Tunnel

A full-tunnel profile attempts to route most host traffic through the TUN
interface:

```yaml
tun:
  enable: true
  device-id: "dev://tun0"
  route-all: true
  gateway: "198.18.0.1/24"
  dns-hijack: true
```

Use this only after confirming that the core has a reliable path to its remote
proxy server. Otherwise the proxy's own outbound connection can be captured by
TUN and form a routing loop.

### Split Tunnel

A split-tunnel profile limits TUN routing to selected prefixes:

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

Split routing is useful for staged rollout because it changes less of the host's
network behavior.

## Device Selection

The inherited configuration path documents device identifiers such as:

- `dev://tun0` — named TUN device,
- `tun0` — plain device-name form,
- `dev://utun1989` — macOS-style `utun` device,
- `fd://3` — advanced file-descriptor handoff where supported by the runtime.

Do not assume every form is meaningful on every operating system. In ordinary
desktop use, prefer the simplest platform-native device form supported by the
selected build.

## Routing Model

TUN introduces two traffic directions that must stay distinct:

```text
application traffic
       |
       v
   TUN interface
       |
       v
 chimera_client
       |
       +---- rules / DNS ----+
       |                     |
       v                     v
 proxy outbound          DIRECT/reject
       |
       v
 physical network
```

The core's own outbound traffic must reach the physical network without being
captured back into the same TUN path. Linux deployments commonly use packet
marks and policy routing for this purpose; other platforms use their own route
management mechanisms.

## DNS Interaction

TUN and DNS should be designed together.

A common failure mode is that application traffic enters TUN while DNS still
uses an unrelated system path. This can cause:

- domain rules to stop matching,
- Fake-IP mappings to be bypassed,
- DNS leaks,
- or traffic to appear to work inconsistently between applications.

`dns-hijack` only controls interception of captured DNS traffic. It does not
replace a valid `dns:` configuration.

For domain-heavy rule sets, verify the DNS flow described in
[DNS Module](./dns.md) before assuming the TUN route itself is wrong.

## Linux Notes

Linux TUN deployments may require root-equivalent privileges or capabilities
such as `CAP_NET_ADMIN`, depending on how the process creates interfaces and
routes.

When policy routing is involved, useful inspection commands include:

```bash
ip addr
ip rule
ip route
ip route show table 2468
ip -6 route
```

If `so-mark` or a dedicated route table is configured, make sure the values do
not conflict with rules installed by another VPN, container runtime, firewall,
or proxy application.

## Windows and macOS Notes

On Windows and macOS, TUN behavior is still sensitive to privileges, route
ownership, interface setup, and other networking software running on the host.

When troubleshooting these platforms:

- check whether another VPN or proxy tool is already managing default routes;
- verify the TUN interface was created successfully;
- inspect route changes before and after enabling TUN;
- disable competing network-filter or VPN software temporarily when isolating a
  problem;
- and restore application-level SOCKS/HTTP proxying to confirm that the proxy
  core itself remains healthy.

## MTU

MTU problems often look like partial connectivity: small requests work while
larger TLS or QUIC transfers stall.

If that happens:

1. keep the default MTU first;
2. confirm the problem only appears through TUN;
3. lower the MTU gradually if the network path requires it;
4. re-test both TCP and UDP-based outbound protocols.

Avoid treating an arbitrary low MTU as a permanent fix without identifying the
underlying path limitation.

## Compatibility Notes

`chimera_client` inherits several TUN concepts from clash-rs, while Mihomo uses
some different key names and routing abstractions. Similar functionality does
not always mean configuration is interchangeable.

Examples of potential differences include:

- device naming and file-descriptor handoff,
- explicit `gateway` / `gateway-v6` fields,
- `route-all` and `routes` versus Mihomo-style auto-route controls,
- route-table naming,
- and Linux packet-mark configuration.

When migrating a Mihomo profile, translate TUN settings deliberately instead of
copying the entire block and assuming semantic parity.

## Recommended Bring-Up Sequence

Use this sequence to reduce the number of variables being debugged at once:

1. Start `chimera_client` with TUN disabled.
2. Verify SOCKS5 or HTTP proxying works.
3. Verify the intended outbound proxy and rule group work.
4. Configure DNS and confirm direct queries to the client resolver succeed.
5. Enable TUN without adding unnecessary custom routes or MTU overrides.
6. Confirm the interface is created.
7. Confirm host routes changed as expected.
8. Confirm the core's own outbound traffic is not looping back into TUN.
9. Enable DNS hijacking/Fake-IP only after ordinary TUN traffic works.
10. Add advanced split routes, packet marks, or custom route tables last.

## Troubleshooting

If TUN is enabled but traffic fails, inspect the layers in order:

1. **Interface** — was the TUN device created?
2. **Privileges** — did route/interface operations succeed?
3. **Routes** — is traffic actually pointed at TUN?
4. **Loop prevention** — can the proxy core still reach its remote server?
5. **DNS** — are queries using the intended resolver path?
6. **Rules** — does the captured flow contain enough metadata for the expected
   rule?
7. **MTU** — do only large packets or particular transports fail?
8. **Platform conflicts** — is another VPN/proxy/firewall modifying the same
   routes?

If the problem remains unclear, return to SOCKS5/HTTP mode and re-enable TUN one
piece at a time.

## Related Pages

- [Ports and Listeners](./ports.md)
- [DNS Module](./dns.md)
- [Rule Types and Their Effects](./rules.md)
