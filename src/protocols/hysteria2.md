## 参考

- https://v2.hysteria.network/zh/docs/developers/Protocol/

# Hysteria 2 协议规范

Hysteria 是基于 QUIC 的 TCP 与 UDP 代理，专为速度、安全性与抗审查设计。本文档描述 Hysteria 2.0.0 起使用的协议，有时在内部也被称为“v4”协议。下文将其称为“协议”或“Hysteria 协议”。

## 规范性术语

本文档中的关键词 "MUST"、"MUST NOT"、"REQUIRED"、"SHALL"、"SHALL NOT"、"SHOULD"、"SHOULD NOT"、"RECOMMENDED"、"MAY" 与 "OPTIONAL" 的含义遵循 RFC 2119： https://tools.ietf.org/html/rfc2119

## 底层协议与线格式

Hysteria 协议必须建立在标准 QUIC 传输协议（RFC 9000）及其不可靠数据报扩展（RFC 9221）之上。

所有多字节数字使用大端序。

所有可变长度整数（"varints"）的编码/解码遵循 QUIC（RFC 9000）的定义。

## 认证与 HTTP/3 伪装

Hysteria 协议的关键特性之一是：对于没有正确认证凭据的第三方（无论是中间人还是主动探测者），Hysteria 代理服务器看起来与标准 HTTP/3 Web 服务器无异。此外，客户端与服务端之间的加密流量也与正常 HTTP/3 流量不可区分。

因此，Hysteria 服务器必须实现 HTTP/3 服务器（RFC 9114），并像标准 Web 服务器一样处理 HTTP 请求。为避免主动探测识别 Hysteria 服务器常见响应模式，实现应建议用户托管真实内容或设置为其他站点的反向代理。

真实的 Hysteria 客户端在连接时必须向服务器发送如下 HTTP/3 请求：

```text
:method: POST
:path: /auth
:host: hysteria
Hysteria-Auth: [string]
Hysteria-CC-RX: [uint]
Hysteria-Padding: [string]
```

`Hysteria-Auth`：认证凭据。

`Hysteria-CC-RX`：客户端最大接收速率（字节/秒）。值为 0 表示未知。

`Hysteria-Padding`：长度可变的随机填充字符串。

Hysteria 服务器必须识别此特殊请求，并且不应尝试提供内容或转发到上游站点，而必须使用所提供的信息进行认证。认证成功时，服务器必须返回如下响应（HTTP 状态码 233）：

```text
:status: 233 HyOK
Hysteria-UDP: [true/false]
Hysteria-CC-RX: [uint/"auto"]
Hysteria-Padding: [string]
```

`Hysteria-UDP`：服务端是否支持 UDP 转发。

`Hysteria-CC-RX`：服务端最大接收速率（字节/秒）。值为 0 表示无限制；"auto" 表示服务端拒绝提供值，要求客户端使用拥塞控制自行测定速率。

`Hysteria-Padding`：长度可变的随机填充字符串。

有关如何使用 `Hysteria-CC-RX` 的更多信息，请参阅拥塞控制章节。

`Hysteria-Padding` 为可选项，仅用于混淆请求/响应模式。双方都应忽略该字段。

若认证失败，服务端必须像不理解该请求的标准 Web 服务器一样响应，或者在作为反向代理时将请求转发至上游并返回响应。

客户端必须检查状态码判断认证是否成功。若状态码不是 233，客户端必须视为认证失败并断开连接。

只有在客户端通过认证之后，服务端才应将该 QUIC 连接视为 Hysteria 代理连接，并开始按下一节描述处理代理请求。

## 代理请求

### TCP

每个 TCP 连接，客户端必须创建新的 QUIC 双向流，并发送如下 TCPRequest 消息：

```text
[varint] 0x401 (TCPRequest ID)
[varint] Address length
[bytes] Address string (host:port)
[varint] Padding length
[bytes] Random padding
```

服务器必须返回 TCPResponse 消息：

```text
[uint8] Status (0x00 = OK, 0x01 = Error)
[varint] Message length
[bytes] Message string
[varint] Padding length
[bytes] Random padding
```

若状态为 OK，服务端必须开始在客户端与指定 TCP 目标之间转发数据，直到任一端关闭连接。若状态为 Error，服务端必须关闭 QUIC 流。

### UDP

UDP 数据包必须封装为以下 UDPMessage 格式，并通过 QUIC 不可靠数据报通道发送（客户端到服务端及服务端到客户端）：

```text
[uint32] Session ID
[uint16] Packet ID
[uint8] Fragment ID
[uint8] Fragment count
[varint] Address length
[bytes] Address string (host:port)
[bytes] Payload
```

客户端必须为每个 UDP 会话使用唯一 Session ID。服务端应为每个 Session ID 分配唯一 UDP 端口，除非具备其他机制区分不同会话的数据包（例如对称 NAT、不同出口 IP 等）。

协议没有显式关闭 UDP 会话的方法。客户端可以无限期保留并复用 Session ID，但服务端应在一段时间无活动后释放并重新分配与该 Session ID 关联的端口，或采用其他标准。当客户端发送到服务端已不认识的 Session ID 时，服务端必须将其视为新会话并分配新端口。

若服务端不支持 UDP 转发，应静默丢弃客户端发来的所有 UDP 消息。

#### 分片

由于 QUIC 不可靠数据报通道的大小限制，任何超过 QUIC 最大数据报大小的 UDP 包必须分片或丢弃。

对于分片包，每个分片必须携带相同的 Packet ID。Fragment ID 从 0 开始，表示当前分片在总分片数中的索引。服务端与客户端都必须等待该包的所有分片到达后再处理；若有分片丢失，则整个包必须被丢弃。

对于未分片的包，Fragment count 必须为 1。在这种情况下，Packet ID 与 Fragment ID 的值无关紧要。

## 拥塞控制

Hysteria 的一项独特功能是允许客户端设置 tx/rx（上行/下行）速率。在认证阶段，客户端通过 `Hysteria-CC-RX` 头部向服务端发送其 rx 速率。服务端可据此决定向客户端的发送速率，客户端也可以通过服务端返回的同名头部获知对方的 rx 速率。

三种特殊情况：

- 若客户端发送 0，表示不知道自身 rx 速率，服务端必须使用拥塞控制算法（例如 BBR、Cubic）调整发送速率。
- 若服务端返回 0，表示没有带宽限制，客户端可以任意速率发送。
- 若服务端返回 "auto"，表示不指定速率，客户端必须使用拥塞控制算法调整发送速率。

## “Salamander” 混淆

Hysteria 协议支持可选混淆层，代号 “Salamander”。

“Salamander” 会将所有 QUIC 数据包封装为如下格式：

```text
[8 bytes] Salt
[bytes] Payload
```

对于每个 QUIC 数据包，混淆器必须计算随机生成的 8 字节 salt 与用户提供的预共享密钥拼接后的 BLAKE2b-256 哈希：

```text
hash = BLAKE2b-256(key + salt)
```

然后使用如下算法对 payload 进行混淆：

```text
for i in range(0, len(payload)):
    payload[i] ^= hash[i % 32]
```

解混淆器必须使用相同算法计算带 salt 的哈希并还原 payload。任何无效数据包必须被丢弃。
