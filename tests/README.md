# Testing Proxy Wiki

Proxy Wiki uses WebdriverIO, Mocha, and a static server to test the generated
mdBook output in a real browser. These tests are most useful when changing
custom theme JavaScript, CSS, search behavior, speaker notes, or generated page
structure.

## Run Tests

Install Node dependencies once:

```shell
npm install
```

From the repository root, run:

```shell
cargo xtask web-tests
```

For local iteration, serve the book first:

```shell
cargo xtask serve
```

Then run the mdBook-targeted test config from this directory:

```shell
npm run test-mdbook
```

## CI Mode

The default test config serves a built book on `localhost:8080`. The mdBook
config expects an already-running local preview on `localhost:3000`.

When tests fail, first check whether the failure is caused by a real theme or
generated HTML regression. Browser crashes or WebDriver startup failures may
indicate a test environment problem instead.
