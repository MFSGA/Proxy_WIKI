# Legacy browser tests

This directory contains the previous WebdriverIO-based browser regression suite.
It is retained as optional reference material in case browser-level theme testing
is needed again, but it is not part of the current Proxy Wiki validation or CI
pipeline.

The active project checks focus on the Rust helpers and successful mdBook
builds. From the repository root, use:

```shell
cargo test
cargo clippy -- -D warnings
cargo xtask build
```

If browser regression testing becomes important again, the files in this
directory can be refreshed and reintroduced as a separate optional workflow.
