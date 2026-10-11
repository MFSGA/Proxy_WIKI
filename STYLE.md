# Proxy Wiki Style Guide

Proxy Wiki is a technical reference for the Chimera proxy stack. Write for users
who need accurate behavior, configuration, and compatibility information.

## Writing

- Prefer concrete behavior over marketing language.
- Separate confirmed implementation behavior from planned or partial behavior.
- Use examples when documenting configuration formats or protocol flows.
- Keep terminology consistent with the relevant project: `Chimera_Client`,
  `Chimera`, `Chimera_Server`, Clash/Mihomo, and xray-core.
- Use `MUST`, `SHOULD`, and `MAY` only when describing protocol requirements or
  externally specified behavior.

## Structure

- User-facing setup and operation steps should come before implementation notes.
- Developer-facing details should name the module, file, or API path when known.
- Known limitations belong in the same chapter as the affected feature, with
  broader gaps summarized in `src/open-questions.md`.
- Protocol pages should cover handshake shape, configuration surface,
  interoperability notes, security considerations, and known limitations.

### Feature Status Fields

When adding or revising a page or section that summarizes a feature's status,
record these as two independent fields. Do not infer local maturity from
upstream alignment, or alignment from local maturity. Bring existing status
entries into this format when they are next audited; do not assign values from
assumptions. Use the exact labels below; Chinese pages may use the fixed
equivalents in `STYLE.zh.md`.

| Field                  | Allowed values                                                                         |
| ---------------------- | -------------------------------------------------------------------------------------- |
| **Upstream alignment** | `Needs assessment`, `Planned`, `Aligning`, `Aligned`, `Not aligning`, `Not applicable` |
| **Local maturity**     | `Not assessed`, `Not implemented`, `In development`, `Experimental`, `Stable`          |

For **Upstream alignment**, `Aligned` means parity only within a stated scope
and against a named upstream revision. `Planned` means alignment is agreed but
work has not started. `Aligning` means active work is underway. For these three
values, record the target repository and scope; for `Aligned`, also pin the
release or commit and link verification evidence. `Not aligning` means the
feature is intentionally out of scope or will retain a known difference; record
the reason and, when useful, a review date. Use `Needs assessment` until the
comparison has been audited, and `Not applicable` when there is no meaningful
upstream counterpart.

For **Local maturity**, `Not implemented` means no runtime path exists;
accepting configuration alone does not count as implementation. `In development`
means the implementation is incomplete and not ready for normal use.
`Experimental` means it can be used within documented limits but may change or
have material gaps. `Stable` means it is intended for regular use and its
behavior and limits are documented. Use `Not assessed` when the source has not
been audited. These labels describe maturity, not test strength: keep evidence
levels such as Parsed, Implemented, and Interop-tested separate, as defined in
[`src/implementation-status.md`](src/implementation-status.md).

State the two fields separately in feature summaries or tables. Record the
last-checked date when relevant and link the strongest evidence for claims of
alignment or stability. Apply the fields at the smallest useful direction or
component boundary when Client and Server behavior differs.

Example:

```text
Upstream alignment: Aligning (target: <repository>; scope: <capability>)
Local maturity: Experimental
```

### Protocol Page Template

New protocol/transport pages should follow this order when the topic applies:

1. **Position in the stack** — protocol vs transport vs security layer, and the
   direction/component that currently implements it.
2. **Configuration surface** — required fields, defaults only when verified,
   feature gates, parsed-only/rejected compatibility fields.
3. **Connection or handshake flow** — phase order before byte-level detail.
4. **Wire format / framing** — field order, lengths, endianness, bounds, and
   incremental parsing behavior.
5. **State machine** — success, close, retry, fallback, and malformed-input
   transitions where relevant.
6. **TCP and UDP behavior** — document separately; use “not applicable” rather
   than implying parity.
7. **Packet-capture view** — identify which layer is visible before decryption or
   inner-protocol handoff.
8. **Security notes** — authentication, confidentiality, replay/fallback
   boundaries, resource limits, and exposure assumptions.
9. **Chimera implementation status** — Client/Server direction, the two feature
   status fields above, feature gates, parsed-only/rejected fields, and
   important version/build boundaries.
10. **Test evidence** — strongest unit/integration/cross-project/external test
    anchors; do not upgrade an evidence label beyond the exact path tested.
11. **Compatibility boundaries** — explicitly list known differences from Xray,
    Clash/Mihomo, or other upstream implementations.
12. **Troubleshooting** — isolate failures by protocol layer rather than listing
    generic networking advice.
13. **Source anchors and references** — local implementation paths separately
    from public specifications/upstream references.

A page does not need empty headings for concepts that truly do not apply. When a
normally expected topic is omitted, make the reason explicit in the nearest
relevant section (for example, Dokodemo-door has no authentication handshake of
its own).

## Code and Configuration Blocks

- Use fenced code blocks with a language tag whenever possible.
- Keep example secrets, UUIDs, and domains obviously fake.
- Prefer minimal runnable examples over large copied configs.
- Mention platform assumptions for commands that only work on Linux, macOS, or
  Windows.

## Translation

- Keep protocol names, config keys, commands, and file paths unchanged.
- Translate explanatory prose, not machine-readable values.
- If an English sentence is ambiguous, fix the English source before updating
  translations.
