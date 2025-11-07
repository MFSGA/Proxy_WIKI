# System Topology

The reference deployment pairs `clash-rs` clients with one or multiple `Chimera` frontends, all built on the shared primitives exposed by `chimera_core`. Clients typically run on user devices or edge nodes where they terminate local applications and translate outbound traffic into proxy-aware streams. These streams traverse secure tunnels toward `Chimera`, which performs authentication, routing, and protocol termination before forwarding packets to upstream services or the public internet.

Because the stack centers on `chimera_core`, upgrades to cipher suites, multiplexing strategies, or configuration schemas become instantly available to both sides, minimizing version skew. Observability is likewise unified: telemetry emitted at each layer shares identifiers so that request flows remain traceable end to end.
