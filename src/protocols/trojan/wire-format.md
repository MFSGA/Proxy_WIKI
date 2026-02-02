# Trojan 线格式

### TLS 握手
- 客户端先执行标准 TLS 握手。
- 若握手失败，服务端像常规 HTTPS 服务一样关闭连接。
- 一些实现也会对纯 HTTP 探测返回类似 nginx 的响应。

### 初始请求
TLS 建立后，第一个应用数据包格式为：

```text
+-----------------------+---------+----------------+---------+----------+
| hex(SHA224(password)) |  CRLF   | Trojan Request |  CRLF   | Payload  |
+-----------------------+---------+----------------+---------+----------+
|          56           | 0x0D0A  |    Variable    | 0x0D0A  | Variable |
+-----------------------+---------+----------------+---------+----------+
```

### Trojan Request
Trojan Request 使用 SOCKS5 类似的格式：

```text
+-----+------+----------+----------+
| CMD | ATYP | DST.ADDR | DST.PORT |
+-----+------+----------+----------+
|  1  |  1   | Variable |    2     |
+-----+------+----------+----------+
```

- CMD 取值：0x01 CONNECT，0x03 UDP ASSOCIATE。
- ATYP 取值：0x01 IPv4，0x03 DOMAINNAME，0x04 IPv6。
- DST.ADDR 为目标地址，DST.PORT 为网络字节序。
- SOCKS5 字段详情：https://tools.ietf.org/html/rfc1928

### UDP Associate 封装
当 CMD 为 UDP ASSOCIATE 时，每个 UDP 数据报会在 TLS 流中封装为：

```text
+------+----------+----------+--------+---------+----------+
| ATYP | DST.ADDR | DST.PORT | Length |  CRLF   | Payload  |
+------+----------+----------+--------+---------+----------+
|  1   | Variable |    2     |   2    | 0x0D0A  | Variable |
+------+----------+----------+--------+---------+----------+
```

- Length 为 payload 字节数（网络字节序）。
- Payload 为原始 UDP 数据报。

### 备注
- 第一个 TLS 记录可在请求后立即携带 payload，减少包数量与长度特征。
- 客户端通常提供本地 SOCKS5 代理，并将本地请求转换为 Trojan 请求。
