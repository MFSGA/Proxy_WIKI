# SOCKS5

### 官方 RFC
SOCKS 第 5 版协议主要由 **[RFC 1928](https://www.rfc-editor.org/rfc/rfc1928)** 规定。

**相关 RFC：**

* **[RFC 1928 — SOCKS Protocol Version 5](https://www.rfc-editor.org/rfc/rfc1928)**（核心协议、地址格式、UDP ASSOCIATE、认证协商）
* **[RFC 1929 — Username/Password Authentication for SOCKS V5](https://www.rfc-editor.org/rfc/rfc1929)**（可选认证方式）
* **[RFC 1961 — GSS-API Authentication Method for SOCKS V5](https://www.rfc-editor.org/rfc/rfc1961)**（可选认证方式）
* **[RFC 3089 — SOCKS-based IPv6/IPv4 Gateway](https://www.rfc-editor.org/rfc/rfc3089)**（IPv6 场景互操作）

### 亮点
- 四层代理，转发任意 TCP 流，并通过 ASSOCIATE 命令支持 UDP。
- 方法协商允许服务端公布 `NO AUTH`、`USERPASS` 或自定义认证方式。
- 被浏览器、curl、SSH 与 VPN 客户端广泛支持。

### 流程
1. 客户端向代理建立 TCP 连接。
2. 客户端发送支持的认证方式列表；服务端返回选定方式。
3. 可选的用户名/密码交换。
4. 客户端使用目标信息发起 `CONNECT`、`BIND` 或 `UDP ASSOCIATE`。
5. 服务端返回成功/失败码并开始转发流量。

### 配置片段

### 优势
- 兼容传统工具，无需额外插件。
- UDP associate 允许基于 UDP 的 DNS。
- 帧开销小，延迟低。

### 限制
- 无内置加密；需依赖 TLS-over-SOCKS 或上游混淆。
- UDP associate 要求客户端在本地保持监听端口，部分防火墙会阻断。
- 认证方式偏静态，需通过管理层封装以实现动态控制。

### 参考
- https://www.rfc-editor.org/rfc/rfc1928
- https://www.rfc-editor.org/rfc/rfc1929
- https://www.rfc-editor.org/rfc/rfc1961
- https://www.rfc-editor.org/rfc/rfc3089

### 附录
#### RFC 1928（全文）
{{#include ../../third_party/rfc/rfc1928.md:3}}

#### RFC 1929（全文）
{{#include ../../third_party/rfc/rfc1929.md:3}}

#### RFC 1961（全文）
{{#include ../../third_party/rfc/rfc1961.md:3}}

#### RFC 3089（全文）
{{#include ../../third_party/rfc/rfc3089.md:3}}
