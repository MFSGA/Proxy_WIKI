# DNS Module

## Scope and Goals
The DNS module is responsible for domain resolution before policy routing. Its goals are predictable rule matching, low latency, and safe resolution under hostile or unreliable networks. Configuration typically lives under a `dns` block in the Clash-style YAML and can be hot-reloaded.

## Configuration Areas
- Upstream resolvers: define UDP, DoH, or DoT endpoints, and choose which transport is allowed per environment.
- Resolution mode: select fake-IP versus real-IP behavior, and configure the fake-IP pool plus domain filters that must bypass synthesis.
- Split-horizon policies: map domain suffixes or rule sets to specific resolvers, including private zones and regional endpoints.
- Fallback strategy: add fallback resolvers and health checks for blocked, poisoned, or slow upstreams.
- Cache behavior: tune TTL caps, cache size, and prefetch rules to reduce latency without stale answers.
- Safety controls: enable hosts overrides, blocklists, or ECS avoidance to limit leakage and improve consistency.

## Operational Guidance
Prefer explicit resolver policies when different traffic classes require different egress paths. Keep fake-IP exclusions narrow to avoid bypassing rule evaluation unintentionally. If upstreams are unstable, enable health checks and ensure timeouts are shorter than your policy matching budget.
