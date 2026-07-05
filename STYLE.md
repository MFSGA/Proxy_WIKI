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
