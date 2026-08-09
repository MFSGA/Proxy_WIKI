# Test Evidence and Interoperability Matrix

This page records **what has actually been exercised by tests**, not merely what the parser or runtime can construct. It complements [Implementation Status and Source Evidence](./implementation-status.md): implementation status answers “does code exist?”, while this page answers “which peer/direction/behavior has test evidence?”.

The matrix was audited from the current local `Chimera_Client` and `Chimera_Server` source trees. Test names are deliberately included because capability names are not always visible in filenames: several important protocol interoperability cases live inside a shared `xray_client_proxy_e2e.rs` suite.

## Evidence Classes

| Class | Meaning |
| --- | --- |
| Unit | Exercises a parser, codec, state transition, or handler in-process. |
| Self-integration | Starts Chimera components/instances on both sides without an independent peer implementation. |
| Cross-project | Exercises two different Chimera repositories together, such as Chimera Client → Chimera Server. |
| External interoperability | Exercises Chimera against an independent implementation such as Xray. |
| Negative interoperability | Verifies expected rejection/fallback/failure against a real peer or full process stack. |
| Example/build validation | Proves a configuration example parses/builds, but does not prove network interoperability. |

These levels are cumulative only when the specific path is actually covered. A protocol with an external TCP test does not automatically have external UDP, TLS, fallback, multiplexing, or every cipher/transport variant tested.

## Default Tests vs Explicit E2E

Many `Chimera_Server` process-level interoperability tests carry `#[ignore]` because they launch Chimera and another binary such as Xray. This means:

- the test is real executable interoperability evidence;
- it is not necessarily part of the default fast `cargo test` run;
- maintainers must run the ignored suite explicitly when changing the covered protocol path.

Do not translate “ignored” into “not useful” or “not implemented”. It means the test belongs to an explicit, slower/environment-dependent verification tier.

## Client-side Integration Matrix

The following tests live in `Chimera_Client/clash-lib/tests`.

| Capability | Direction / peer | Evidence | What it proves |
| --- | --- | --- | --- |
| AnyTLS TCP | Chimera Client local SOCKS → Chimera AnyTLS outbound → Chimera AnyTLS inbound → target | `anytls_integration_tests.rs::integration_test_anytls_tcp` | Client AnyTLS TCP outbound and inbound interoperate through a real local socket path. |
| AnyTLS UDP | Chimera Client local SOCKS UDP → AnyTLS UoT v2 outbound → Chimera AnyTLS inbound → UDP target | `anytls_integration_tests.rs::integration_test_anytls_udp` | Current UDP-over-TCP v2 framing and session path work end to end within Client implementations. |
| Shadowsocks TCP | Chimera Client local SOCKS → Shadowsocks outbound → Chimera Shadowsocks inbound → target | `shadowsocks_integration_tests.rs::integration_test_shadowsocks_tcp` | Client-side Shadowsocks TCP inbound/outbound integration. |
| Shadowsocks UDP | Local SOCKS UDP → Shadowsocks outbound/inbound → UDP target | `integration_test_shadowsocks_udp` | Basic Client Shadowsocks UDP relay. |
| Shadowsocks UDP multi-target | One client path to multiple UDP targets | `integration_test_shadowsocks_udp_multi_target` | Destination/session handling does not collapse all UDP traffic into one target. |
| Shadowsocks UDP isolation | Multiple logical clients/sessions | `integration_test_shadowsocks_udp_session_isolation` | UDP session state remains isolated. |
| Direct UDP multi-target | Local UDP path → direct | `direct_udp_integration_tests.rs::ref_compat_udp_one_client_preserves_multiple_destinations` | Direct UDP preserves per-datagram destinations. |
| Direct UDP client isolation | Multiple clients → direct UDP | `ref_compat_udp_sessions_are_isolated_by_client` | Session keys distinguish client state. |
| TUN + Fake-IP | TUN/Fake-IP → direct and SOCKS-style proxy path → real network targets | `tun_fake_ip_real_tests.rs::tun_fake_ip_routes_direct_and_proxy_with_real_network` | TUN/Fake-IP routing can drive both direct and proxied real network traffic. |
| DNS listener | Real UDP/TCP DNS queries → Client DNS listener | `dns_real_traffic_tests.rs` | DNS listener handles real UDP/TCP query traffic and concurrency. |

These are primarily **self-integration** or real-network integration tests. They do not prove compatibility with Xray for AnyTLS or Shadowsocks Server behavior.

## Chimera Client → Chimera Server REALITY/Vision

`Chimera_Server/chimera_server_app/tests/chimera_client_reality_vision_e2e.rs` is the dedicated cross-project suite for Chimera Client → Chimera Server.

Positive coverage includes:

- basic TCP and large payloads;
- payload/framing boundaries;
- domain targets;
- TLS 1.3 application-data transition;
- sequential and concurrent connections;
- multiple configured REALITY server names;
- multiple short IDs;
- exact client version bounds.

The companion `chimera_client_reality_vision_negative_e2e.rs` verifies rejection for cases including:

- client version below an explicit minimum;
- client version above an explicit maximum;
- wrong short ID;
- wrong server name;
- wrong REALITY public key;
- wrong VLESS UUID;
- missing required Vision flow;
- Vision flow presented to a plain VLESS account.

These tests are marked ignored because they launch both project binaries. They are nevertheless the strongest evidence for the exact **Chimera Client ↔ Chimera Server** REALITY/Vision combination.

## Xray Client → Chimera Server Matrix

The shared ignored suite `Chimera_Server/chimera_server_app/tests/xray_client_proxy_e2e.rs` contains several protocol cases. The filename is generic, so the individual test function is the important evidence anchor.

| Capability | Direction | Test | Coverage |
| --- | --- | --- | --- |
| VLESS + REALITY + Vision | Xray client → Chimera Server | `xray_client_can_proxy_tcp_through_chimera_reality_vision` | TCP proxying through REALITY/Vision. |
| VLESS + TLS + Vision | Xray client → Chimera Server | `xray_client_can_proxy_tcp_through_chimera_tls_vision` | TLS-wrapped Vision TCP. |
| Shadowsocks classic AEAD | Xray client → Chimera Server | `xray_client_can_proxy_tcp_through_chimera_shadowsocks` | Legacy/current classic AEAD TCP methods exercised by the loop in the test. |
| Shadowsocks multi-user classic | Two Xray clients → one Chimera inbound | `xray_clients_can_use_multiple_legacy_shadowsocks_users` | Multiple configured classic users select/authenticate independently. |
| Shadowsocks 2022 EIH | Two Xray clients → one Chimera inbound | `xray_clients_can_use_shadowsocks_2022_eih_users` | AEAD-2022 multi-user EIH user selection. |
| Shadowsocks 2022 TCP + AES UDP | Xray client → Chimera Server | `xray_client_can_proxy_tcp_and_aes_udp_through_chimera_shadowsocks_2022` | 2022 TCP plus AES-2022 UDP interoperability. |
| VLESS over gRPC transport | Xray client → Chimera Server | `xray_client_can_proxy_tcp_through_chimera_grpc` | Xray VLESS gRPC/h2c client can traverse Chimera's proxy gRPC transport. |
| VLESS over HTTPUpgrade | Xray client → Chimera Server | `xray_client_can_proxy_tcp_through_chimera_httpupgrade` | Xray VLESS HTTPUpgrade request/101/raw-stream path interoperates with Chimera. |
| Hysteria 2 | Xray client → Chimera Server | `xray_client_can_proxy_tcp_and_udp_through_chimera_hysteria2` | Both TCP and UDP proxying through the Server Hysteria 2 implementation. |

The same file also contains HTTP/Mixed inbound process-level coverage using direct HTTP CONNECT/forward-proxy/SOCKS clients rather than relying on an Xray proxy protocol for those local-proxy semantics.

## Fallback and Negative Process Tests

`xray_client_proxy_e2e.rs` also exercises full-process fallback behavior that is easy to miss in a simple protocol matrix:

| Case | Evidence |
| --- | --- |
| Unauthenticated plain TCP reaches VLESS fallback | `unauthenticated_plain_tcp_reaches_vless_fallback` |
| TLS payload reaches VLESS Vision fallback | `unauthenticated_tls_payload_reaches_vless_vision_fallback` |
| Trojan TLS fallback rule selection | `unauthenticated_tls_payload_reaches_trojan_fallback_rules` |
| REALITY SNI mismatch reaches destination fallback | `plain_tls_client_falls_back_to_reality_dest_on_sni_mismatch` |
| Wrong REALITY short ID falls back | `xray_client_with_wrong_reality_short_id_falls_back_to_dest` |
| Wrong REALITY SNI falls back | `xray_client_with_wrong_reality_sni_falls_back_to_dest` |

Fallback evidence matters because “invalid auth is rejected” and “invalid auth is safely routed to the configured fallback” are different runtime behaviors.

## REALITY/Vision Xray Baseline Matrix

The Server also has dedicated ignored Xray-baseline suites:

- `reality_vision_matrix_e2e.rs`;
- `reality_vision_negative_e2e.rs`.

They cover uTLS fingerprints, payload boundaries, domain/IPv6 targets, TLS 1.3 transitions, repeated sessions, half-close behavior, concurrency, multiple server names/short IDs, version bounds, and authentication/flow rejection cases.

These suites compare behavior with an Xray-oriented baseline and are stronger evidence for subtle REALITY/Vision state transitions than a single happy-path connection test.

## XHTTP Interoperability Matrix

`xhttp_matrix_e2e.rs` starts Chimera Server and Xray and generates a matrix of XHTTP cases. The matrix covers combinations including:

- `stream-one`, `packet-up`, `stream-up`, and `auto` modes;
- POST/GET/PATCH/PUT uplink methods where allowed;
- session ID placement in path/header/query/cookie;
- sequence placement variants;
- body/header/cookie uplink data placement;
- header-size limits;
- padding obfuscation placements and methods;
- `noGRPCHeader` / `noSSEHeader` variants.

These cases are ignored explicit E2E tests because they launch both Chimera and Xray.

`xhttp_security_matrix_e2e.rs` separately verifies XHTTP with:

- no security wrapper;
- TLS;
- REALITY.

`xhttp_protocol_matrix_e2e.rs` is primarily Chimera process-level behavioral/negative coverage for host/path rejection, padding validation, packet sequencing, body-size limits, duplicate stream-up, mode conflicts, CORS/options, and padding placement.

## gRPC: Proxy Transport vs Management API

The repository contains two unrelated features that both use gRPC terminology:

1. **proxy gRPC transport** — `beginning/grpc_transport.rs`, which wraps an inner proxy byte stream as Xray-style Hunk messages;
2. **management gRPC API** — Xray-compatible control-plane services for stats, handlers, routing, observatory, and related operations.

Use these evidence anchors correctly:

| Test | What it proves |
| --- | --- |
| `xray_client_proxy_e2e.rs::xray_client_can_proxy_tcp_through_chimera_grpc` | Proxy **transport** interoperability. |
| `beginning/grpc_transport.rs` unit tests | Hunk codec/incomplete-buffer behavior. |
| `grpc_all_interfaces_e2e.rs` | Management API behavior across many exposed interfaces. |
| `grpc_external_integration.rs` | External management API process integration. |
| `grpc_xray_compat_e2e.rs` | Management API behavioral comparison with Xray, including generated reports. |

Do not cite the management API tests as proof that VLESS/gRPC proxy transport works. Conversely, a successful VLESS/gRPC proxy test says nothing about StatsService or HandlerService compatibility.

## SOCKS and HTTP/Mixed Evidence

`Chimera_Server/chimera_server_app/tests/socks_external_integration.rs` contains external-process SOCKS tests for:

- no-auth TCP round trip;
- username/password TCP round trip.

`xray_client_proxy_e2e.rs::http_and_mixed_inbounds_proxy_tcp` starts real Chimera HTTP and mixed listeners and exercises:

- authenticated HTTP CONNECT;
- absolute-form HTTP forwarding;
- transparent-style HTTP request forwarding where enabled;
- HTTP through mixed inbound;
- SOCKS5 through mixed inbound.

This is process-level protocol evidence even though it does not use Xray as the client for those local proxy requests.

## TUIC Evidence

`chimera_server_lib/src/handler/tuic/e2e_tests.rs::udp_stream_and_datagram_roundtrips_record_stats` exercises the current TUIC handler over QUIC and verifies:

- UDP stream relay;
- QUIC datagram relay;
- traffic-stat accounting.

This is strong in-repository E2E evidence for the implemented TUIC data path, but it is **not external TUIC interoperability evidence** with an independent client. Keep that distinction visible until such a test is added.

## Dokodemo-door Evidence

Dokodemo-door has no client wire protocol to compare against an external peer, so the relevant evidence is handler/socket/routing behavior rather than a protocol handshake.

Current tests include:

- `handler/dokodemo.rs::follow_redirect_uses_original_destination`;
- `handler/dokodemo.rs::follow_redirect_rejects_missing_original_destination`;
- Linux original-destination extraction tests in the listener path;
- `beginning/udp.rs::dokodemo_udp_follow_redirect_routes_by_original_destination`;
- `dokodemo_udp_relay_forwards_datagrams`;
- `dokodemo_udp_reuses_session_for_same_flow`;
- `dokodemo_udp_session_forwards_multiple_responses`;
- Xray-compatible TCP/UDP example parsing/building in `tests/xray_compatible_examples.rs`.

These tests validate the forwarding machinery; a real transparent deployment still depends on Linux firewall/policy-routing configuration outside the Rust process.

## What Is Not Yet Proven

The current test tree does **not** justify the following blanket claims:

- AnyTLS interoperability with `Chimera_Server` — the Server has no AnyTLS inbound;
- Chimera Client gRPC or HTTPUpgrade outbound interoperability — those outbound transport modules are not currently present;
- external TUIC interoperability with an independent TUIC client;
- every Shadowsocks cipher parsed by Client is accepted by Server;
- every XHTTP field parsed from Xray-shaped configuration is implemented;
- every ignored E2E runs in default CI simply because the source file exists.

Absence from this list does not necessarily mean a feature is broken. It means the Wiki should not upgrade a capability claim to “interop-tested” without a concrete test anchor.

## Running the Evidence Suites

From `Chimera_Client`, focused protocol integration tests can be run with commands such as:

```bash
cargo test -p clash-lib --test anytls_integration_tests
cargo test -p clash-lib --test shadowsocks_integration_tests
```

From `Chimera_Server`, the explicit ignored E2E tier can be exercised with:

```bash
cargo test --workspace -- --ignored
```

A focused external proxy suite can be run with:

```bash
cargo test -p chimera_server_app --test xray_client_proxy_e2e -- --ignored --nocapture
```

These process-level tests may require the expected peer binaries/test assets in the locations resolved by the repository's test harness. A test that cannot start its external dependency is an infrastructure failure, not evidence that the protocol itself failed.

## Maintenance Rule

When a protocol or transport changes:

1. identify the exact parser/runtime path that changed;
2. locate the strongest existing test that traverses that path;
3. update or add a positive test;
4. add a negative test when authentication, bounds, fallback, replay, or malformed input is involved;
5. run the relevant ignored external/cross-project suite when applicable;
6. only then update this Wiki's interoperability label.

If one test file contains several unrelated subsystems, cite the **test function**, not just the filename. The gRPC management/transport distinction and the shared `xray_client_proxy_e2e.rs` suite are the canonical examples of why this matters.
