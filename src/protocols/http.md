# HTTP

### 亮点
- 以普通 HTTP(S) 服务呈现，通过 `CONNECT` 方法将单个请求升级为隧道。
- 易于使用 Nginx、Apache 或云负载均衡器进行前置。
- 双方支持时可使用 HTTP/2 多路复用。

### 流程
1. 客户端与代理端点建立 TCP（或 TLS）连接。
2. 客户端可选执行 HTTP 认证（Basic、Digest、Bearer 或双向 TLS）。
3. 客户端发送 `CONNECT target.example.com:443 HTTP/1.1`（或 HTTP/2 的 `:method CONNECT`）。
4. 代理校验策略后返回 `200 Connection Established`。
5. 后续字节在隧道内透明转发，直到任一端关闭。

### 配置片段

### 优势
- 与标准 HTTPS 流量混合，难以与普通浏览区分。
- 可在仅允许 80/443 端口的企业防火墙后正常工作。
- HTTP/2 变体可在单个 TCP 会话中承载多个隧道，降低握手开销。

### 限制
- 仅支持 TCP；无法代理 UDP 流量，除非额外封装。
- 代理需为每条隧道维护状态，在大量短连接时影响扩展性。
- 额外 HTTP 头部若未清洗可能泄露元数据。
