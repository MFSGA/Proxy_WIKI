# xtask

xtask 二进制的目的，是在项目内提供跨平台的任务自动化（有点类似 Node.js 项目中使用 `npm run` 来执行脚本）。详情请参考
[cargo xtask](https://github.com/matklad/cargo-xtask)。

若要新增任务支持，请在 `execute_task` 函数的 `match` 中添加新的分支，并新增对应的处理函数实现逻辑。
