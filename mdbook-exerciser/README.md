# exerciser

这是一个 mdBook 渲染器，用于从 Markdown 源文件生成练习模板。给定一个包含如下片段的 Markdown 文件 `example.md`：

````markdown
<!-- File src/main.rs -->

```rust,compile_fail
{{#include example/src/main.rs:main}}

fn some_more_code() {
    // TODO: Write some Rust code here.
}
```
````

以及 `book.toml` 中的 mdBook 配置：

```toml
[output.exerciser]
output-directory = "comprehensive-rust-exercises"
```

它会生成文件
`book/exerciser/comprehensive-rust-exercises/example/src/main.rs`，并写入相应内容。
