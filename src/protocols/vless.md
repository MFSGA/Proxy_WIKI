# VLESS

### 亮点
- Project V 的轻量无状态协议，使用 UUID 标识客户端。
- 通常与 TLS、XTLS 或 Reality 传输层配合，实现加密与伪装。
- 在 Xray core 生态中支持多路复用、回落路由与高级路由规则。

### 流程
1. 客户端连接服务端传输层（TLS、XTLS、Reality、gRPC 或 MKCP）。
2. 客户端发送 VLESS 头部，包含 UUID、命令（TCP/UDP）与目标地址。
3. 服务端验证 UUID 后建立到目标的流或数据报隧道。
4. 可选的 Flow Control Transport（FCT）或 XTLS 分流可加速流量。

### 配置片段


### 优势
- UUID 认证便于规模化用户管理，并可与自动签发系统集成。
- 支持多种传输层，可在 TCP、gRPC、WS 或 QUIC 之间灵活切换。
- XTLS/Reality 可降低 TLS 开销并模拟合法 HTTPS 指纹。

### 限制
- 依赖 Xray-core 生态，主流操作系统工具不直接支持。
- Flow 参数配置错误可能破坏与旧客户端的兼容性。
- 安全性高度依赖所选传输层；裸 VLESS 不含加密。
