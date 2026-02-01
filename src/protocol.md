# 协议

## 概览

| 协议 | 默认传输 | 认证方式 | 优势 | 常见限制 |
| --- | --- | --- | --- | --- |
| SOCKS5 | TCP 控制 + 可选 UDP | 可选用户名/密码 | 几乎适配所有 TCP 应用，支持 UDP associate | 默认明文，需要额外 TLS/混淆 |
| HTTP(S) CONNECT | HTTP/1.1 或 HTTP/2 上的 TCP | Basic、Bearer、双向 TLS | 与 Web 流量混合，易部署于网关 | 仅代理 TCP，依赖中间层保持长连接 |
| Trojan | TCP 上的 TLS | TLS 内验证预共享密码 | 难以指纹识别，利于 CDN/SNI | 每个密码绑定端口/用户，需要有效证书 |
| Hysteria 2 | TLS 1.3 的 QUIC（UDP） | 密码或类 OIDC 令牌 | 高吞吐、原生 UDP、拥塞控制可调 | 需开放 UDP 端口，MTU 调整重要 |
| VLESS | TCP 上 TLS/XTLS 或 MKCP | 基于 UUID 的身份 | 灵活的多路复用，可选 XTLS 自动分流 | 无 TLS/XTLS 即无加密，工具生态依赖较强 |

详细拆解已放在独立文件中；每个文件遵循一致结构（亮点、流程、配置片段、优势与限制），便于对比。

## 深入阅读

- [SOCKS5](./protocols/socks5.md) – 通用 TCP/UDP 代理，支持灵活方法协商。
- [HTTP CONNECT 代理](./protocols/http.md) – 通过标准 Web 端口建立 HTTPS 友好隧道。
- [Trojan](./protocols/trojan.md) – TLS 伪装的密码代理，适合 CDN 前置。
- [Hysteria 2](./protocols/hysteria2.md) – 基于 QUIC 的传输，针对高丢包或高延迟链路优化。
- [VLESS](./protocols/vless.md) – 基于 UUID 认证的协议，可配置 TLS、XTLS 或 Reality 等传输层。
