# Repository Agent Instructions

## Documentation Status Fields

- When adding or revising documentation that summarizes a feature's current
  status, record `Upstream alignment` and `Local maturity` as separate fields.
  Never infer one from the other.
- Use only the status values and definitions in `STYLE.md`; use the fixed
  Chinese equivalents in `STYLE.zh.md` when writing Chinese documentation.
- Follow `STYLE.md` for upstream targets, scope, revision, verification
  evidence, and review dates. Do not assign a status from assumptions; update
  existing entries only after auditing the relevant source.
- Keep implementation and test evidence levels separate from local maturity. See
  `src/implementation-status.md` for the evidence terminology.
