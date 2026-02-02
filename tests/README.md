# Comprehensive Rust 测试

课程资料包含可能出问题的 JS 代码，需要检查其功能性。例如 `theme/speaker-notes.js` 或 `theme/book.js`。

Comprehensive Rust 使用 [webdriverIO](https://webdriver.io/) 与 [webdriverIO Expect API](https://webdriver.io/docs/api/expect-webdriverio/)，并结合 [Mocha](https://mochajs.org/)。WebdriverIO 负责用真实浏览器访问页面，并读取页面状态以便断言行为。

[Static Server Service](https://webdriver.io/docs/static-server-service/) 主要用于 [CI](../.github/workflows/build.yml) 中，将书籍服务在 `localhost:8080` 上，以便测试运行器访问。运行 `npm start` 或 `npm test` 时会启用该模式。

> **提示：** 使用 `cargo xtask web-tests` 可在仓库任意位置运行本目录下的测试。

在本地快速验证时，可以使用 `cargo xtask serve`，默认会在 3000 端口启动一个小型 HTTP 服务器。`npm run test-mdbook` 会调用一个特殊配置，使用 `http://localhost:3000`。

## 处理失败的测试

当测试失败时，通常会提示哪些页面的检查出现了问题。

### 合理的警告

例如：需要缩短过长的页面（或申请豁免）；或 mdBook 基础设施更新带来破坏性变更。这些问题在合入之前都需要修复。

### 测试环境异常

有时 CI 环境也会失败并出现如下错误：

```
ERROR webdriver: WebDriverError: tab crashed
```

如果看到类似信息，可能说明 Web 测试本身有问题，并非由你的改动引起。请提交 bug 报告。作为临时 workaround，如果其它检查都通过且你确信改动正确，可以选择放宽 web-test 的合并要求。
