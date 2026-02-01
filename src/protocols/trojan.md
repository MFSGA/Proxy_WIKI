# Trojan

### 亮点
- 以真实 TLS 握手开头，后续字节均为 TLS 应用数据。
- 认证方式为预共享密码的 SHA-224 哈希并进行十六进制编码。
- 请求格式复用 SOCKS5 风格地址字段，用于 CONNECT 与 UDP ASSOCIATE。
- 无效或未知流量可转发至回落端点，外观类似正常 HTTPS。

### 流程
1. 客户端与服务端完成标准 TLS 握手（按配置设置 SNI/ALPN）。
2. 客户端发送 `hex(SHA224(password))` + CRLF + Trojan 请求 + CRLF（+ 可选 payload）。
3. 服务端校验密码与请求后连接目标地址。
4. 对 TCP 进行双向转发；对 UDP 则将数据包封装后通过 TLS 流隧道传输。

### 线格式
- 精确帧与字段定义见[线格式](./trojan/wire-format.md)。
- 第一个 TLS 记录可能在请求后携带 payload，以减少包数量。

### 流量处理
- 回落行为与反探测说明见[流量处理](./trojan/traffic-handling.md)。

### 优势
- 使用标准 TLS 栈与证书，继承成熟的 TLS 安全与 ALPN 支持。
- 在合法 HTTPS 端点上难以指纹识别。
- 握手完成后协议开销极小。

### 限制
- 共享密码模型导致吊销粒度较粗，除非使用每用户密码。
- 需要有效 TLS 证书及运维更新。
- 必须配置回落行为以抵御探测并保持 HTTPS 一致性。

### 参考
- https://trojan-gfw.github.io/trojan/protocol
