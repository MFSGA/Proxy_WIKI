# 端口与监听

## 概览
端口定义了本地应用、控制面板与 DNS 解析器连接 `chimera_client` 的位置。命名遵循 Clash 风格配置，而 `chimera_client` 目前使用下划线键表示相同概念。

## 端口映射
| Clash 键 | chimera_client 键 | 作用 |
| --- | --- | --- |
| `port` / `http-port` | `port` | 供浏览器与系统代理使用的 HTTP CONNECT 代理。 |
| `socks-port` | `socks_port` | 通用应用的 SOCKS5 代理；UDP associate 支持为可选。 |
| `mixed-port` | `mixed_port` | 在一个端口同时监听 HTTP + SOCKS5。 |
| `redir-port` | `redir_port` | Linux TCP 透明代理（iptables REDIRECT）。 |
| `tproxy-port` | `tproxy_port` | Linux TPROXY，用于 TCP/UDP 透明代理。 |
| `external-controller` | `external_controller` | 面向控制面板与自动化的 REST API 端口。 |
| `dns.listen` | `dns.listen` | 用于 fake-IP 或策略 DNS 的本地监听。 |

## 各端口说明
### HTTP 代理端口
接受 HTTP CONNECT 请求以及明文 HTTP 代理流量。是浏览器与系统代理设置的默认选择。

### SOCKS5 端口
接受支持 SOCKS 的应用连接。常用于开发工具和高级用户场景。

### Mixed 端口
同时接受 HTTP 与 SOCKS5。若只能配置一个本地端口，可使用该模式简化设置。

### Redir 端口
用于 Linux 上的 TCP 透明代理（iptables REDIRECT）。仅捕获 TCP，需内核级重定向规则配合。

### TProxy 端口
用于 Linux TPROXY，可捕获 TCP 与 UDP。需要策略路由与 `fwmark` 规则，通常与 TUN 或重定向工具配合。

### Controller 端口
提供面向控制面板、移动端外壳与自动化的 REST API。除非需要远程访问，否则应绑定到 localhost。

### DNS 监听端口
接受系统或 TUN 栈的 DNS 查询，通常与 fake-IP 或分流 DNS 规则搭配。

## chimera_client 支持说明
- 目前仅 `socks_port` 入站端口已接入；UDP associate 仍处于禁用状态。
- `port`、`mixed_port`、`redir_port` 与 `tproxy_port` 仅为兼容保留，尚未实现。
- DNS 服务与控制器监听仍在开发中；除非测试，请保持本地访问。

## 配置示例
### 最小化 chimera_client
```yaml
bind_address: "127.0.0.1"
allow_lan: false
socks_port: 7891
dns:
  enable: false
  ipv6: false
```

### Clash 或 Mihomo 布局（参考）
```yaml
port: 7890
socks-port: 7891
mixed-port: 7892
redir-port: 7893
tproxy-port: 7894
external-controller: 127.0.0.1:9090
dns:
  listen: 127.0.0.1:1053
```
