# Trojan 流量处理

### 其他协议（回落）
- Trojan 在 TLS 端口上监听，行为类似普通 HTTPS 服务。
- TLS 完成后，服务端检查首个应用数据包。
- 若该包不是有效 Trojan 请求（结构或密码错误），服务端将其视为“其他协议”，并把解密后的 TLS 流转发到预设端点（默认 `127.0.0.1:80`）。
- 预设端点控制返回内容，使行为与真实 HTTPS 站点无差别。

### 主动探测
- 不符合结构或密码的探测会被转交给回落端点。
- 因此主动扫描只会看到普通 HTTPS 或 HTTP 行为，而不是特制代理响应。

### 被动探测
- 使用有效证书时，流量受 TLS 保护，外观类似普通 HTTPS。
- 对 HTTP 目的地而言，TLS 握手后仅有一次 RTT；非 HTTP 流量常看起来像 HTTPS keepalive 或 WebSocket。
- 这种相似性有助于绕过针对显著代理特征的 ISP QoS。

### 参考
- https://github.com/trojan-gfw/trojan/issues/14
