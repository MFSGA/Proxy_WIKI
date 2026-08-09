# Open Questions

This page tracks unresolved, source-verified documentation or implementation
gaps. Remove an item when the source or tests answer it; do not keep historical
TODOs merely because they once appeared in an older Wiki revision.

## Cross-Project Compatibility

- Add and maintain a generated or semi-generated compatibility matrix that can
  be checked against `Chimera_Client` and `Chimera_Server` source changes.
- Record the exact build artifact/features used for interoperability tests, not
  only the repository commit.
- Expand interoperability evidence beyond the current REALITY/Vision, XHTTP,
  gRPC, SOCKS, and selected Xray/client test paths.
- Define a stable policy for how long an audited source snapshot remains
  “current” before the Wiki requires a re-audit.

## Chimera Desktop

- Classify each runtime setting as hot-reloadable, restart-required, or
  application/OS-owned by following its actual update path.
- Document the profile/enhance pipeline in enough detail to show where generated
  runtime YAML can differ between Mihomo, clash-rs, and Chimera Client.
- Document failure handling for core download/update, generated-config
  validation, foreground process startup, and service-mode startup.
- Review `patch_clash_config` and adjacent IPC paths and document the concrete
  controller/restart behavior they use today.

## Chimera_Service

- Document the local IPC transport/ACL model per operating system with exact
  source-backed permission behavior.
- Document which privileged network operations are implemented on each platform;
  `/network/set_dns` must not be assumed portable merely because it exists in
  the shared IPC API.
- Add a compatibility note for desktop/service/shared-type version skew and the
  expected failure behavior.

## AChimera

- Document the exact Android route, DNS-server, MTU, IPv4/IPv6, and application
  include/exclude behavior configured by `TunService`.
- Record which `Chimera_Client` Cargo features are built into the Android native
  artifact so Android protocol availability can be stated precisely.
- Add an end-to-end Android test plan covering VPN permission, TUN setup,
  `protect(fd)`, DNS, profile validation, and one remote proxy path.
- Document controller polling intervals/backoff and behavior when the embedded
  core exits while the Android service remains alive.

## Chimera_Client

- Keep the AnyTLS `Parsed-only` field list synchronized with the Client config
  struct when compatibility fields are added or become active runtime behavior.
- Document the current SOCKS inbound and mixed-listener UDP limitations next to
  their configuration examples.
- Add a feature/build matrix to release documentation so users can determine
  whether `anytls`, `shadowsocks`, `trojan`, `hysteria`, and `ws` are compiled
  into a distributed binary.
- Clarify the intended future status of VMess, TUIC, WireGuard, SSH, and gRPC
  outbound support; these are not current variants of the inspected outbound
  enum.
- Document the unimplemented HTTP proxy-provider path if it remains exposed in
  configuration or migration guidance.

## Chimera_Server

- Add per-protocol implementation pages that map configuration fields to
  `ServerConfig` validation, listener/transport selection, and handler code.
- Convert explicit `not supported yet` builder/runtime errors into a maintained
  compatibility table and tests so documentation cannot silently drift.
- Document current outbound/routing limitations separately from inbound
  protocol support; for example, an inbound VMess implementation does not imply
  a VMess outbound proxy path.
- Expand XHTTP documentation with the exact list of accepted and rejected Xray
  fields, including the current `downloadSettings` limitation.
- Document the current gRPC transport subset, especially the rejected
  `multiMode` configuration.
- Document VLESS Vision direct-mode limitations and the conditions exercised by
  the existing REALITY/Vision E2E matrix.

## Protocol and Transport Reference

- Pin the upstream AnyTLS and Shadowsocks specification/version references used
  for interoperability claims when the corresponding upstream protocols change.
- Add external HTTPUpgrade interoperability coverage; current evidence is
  handler-level unit coverage rather than a dedicated external E2E test.
- Add cross-links from each protocol page to its Client/Server implementation
  status and interoperability tests.

## Test Evidence and Operations

- Create a single test-evidence table mapping each advertised combination to its
  integration/E2E test name, direction, peer implementation, and expected
  negative cases.
- Add an end-to-end troubleshooting guide that follows the actual layered
  topology: local listener/TUN → DNS/rules → outbound → transport/security →
  server inbound → target.
- Add a deployment threat-model chapter covering local listener exposure,
  credentials/keys, DNS leaks, TUN routing, fallback behavior, metadata logging,
  UDP/QUIC resource limits, and privileged service IPC.
