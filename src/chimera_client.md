# Chimera_Client

## 角色与目标
`chimera_client` 是热门 Clash 客户端的 Rust 重写版本，针对低延迟规则匹配和资源受限环境做了优化。它保留熟悉的 Clash 配置语言，同时利用 Rust 的安全保障，适用于桌面、移动端（通过绑定）以及无界面的自动化场景。客户端强调三大支柱：广泛协议兼容性、确定性策略路由、以及易于运维的使用体验。

## 架构概览
在内部，客户端划分为配置加载、控制器 API、传输引擎与策略运行时。配置加载器将 Clash YAML 解析为强类型 Rust 结构体，并通过 `chimera_core` 的 schema 进行校验与热更新。控制层提供本地 HTTP API 与可选 TUI，便于在设备上检查规则。传输引擎封装每种协议（如 Shadowsocks、VMess、Trojan、Reality/QUIC），并通过 `chimera_core` 共享加密套件与握手逻辑。策略运行时根据用户规则构建决策树，执行 DNS 策略，并将匹配流量导入对应的传输引擎。

## 模块化配置指南
`chimera_client` 的配置与模块边界保持一致，因此 Clash 风格的 YAML 中每个功能区域都有独立块。这让修改更易理解，也能降低热更新的影响范围。

- 核心运行时与配置：设置全局默认值，如模式选择、服务端口、日志级别、IPv6/allow-lan 开关与重载行为。
- 入站监听：定义本地 HTTP/SOCKS/TUN/透明代理端口、绑定地址、UDP 开关与网卡选择。参见[端口与监听](./chimera_client/ports.md)。
- 控制器与体验：配置 API 绑定地址/端口、鉴权令牌，以及可选的 TUI 或桌面外壳开关。
- DNS 流水线：声明上游解析器、缓存大小、fake-IP 与 real-IP 策略、回退行为与基于策略的解析器选择。参见[DNS 模块](./chimera_client/dns.md)。
- 策略引擎：排序规则、绑定规则提供者、选择默认组，并将流量映射到出站组。
- 传输引擎：指定各协议参数，如加密套件、传输层（TCP/WS/gRPC/QUIC）、多路复用与 TLS 指纹选项；复用默认值以保持配置一致。
- 可观测性：启用结构化日志、指标与追踪导出，并按环境调整采样与保留策略。
- 更新与同步：管理远程配置 URL、签名校验、轮询周期与无效配置的回滚。


## 协议覆盖与特性
`chimera_client` 旨在兼容最常见的代理生态：

- 传统协议：HTTP(S)、SOCKS5，以及 TCP/UDP 中继。
- 现代加密协议：Shadowsocks/SSR、VMess/VLESS（TCP/WS/gRPC/QUIC）、Trojan、NaïveProxy、TUIC、Hysteria v2。
- 高级传输：Reality TLS 指纹、多路复用 QUIC 会话，以及自定义混淆插件。

每个协议实现都会记录加密选项、认证要求、多路复用行为与回退策略。用户可在单一配置中混用多种出站类型，并通过级联代理完成复杂路由。

## 部署模式
客户端为主流桌面平台提供二进制，并为服务端路由或 CI 测试提供容器镜像。轻量级系统服务在 Linux 上封装守护进程，以便自动重启与密钥轮换。移动端则通过绑定向 Flutter 和 React Native 外壳开放控制器 API。配置同步依赖 GitOps 友好清单与可选远程配置 URL，便于集群按计划拉取签名更新。

## 性能、可观测性与故障排查
`chimera_client` 集成结构化日志、OpenTelemetry 追踪与按规则统计指标。运维人员可导出连接统计、延迟分位与规则命中次数用于看板。性能调优建议覆盖 DNS 缓存大小、规则树剪枝、各协议并发上限，以及在路由器上运行时的 CPU 亲和设置。故障排查章节涵盖 TLS 指纹不匹配、DNS 污染或控制器认证错误等常见问题。

## 参考仓库
`chimera_client` 源码地址如下：

- `chimera_client`: <https://github.com/MFSGA/Chimera_Client>
