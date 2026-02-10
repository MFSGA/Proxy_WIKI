# xHTTP Transport

## Overview
xHTTP is an Xray transport that tunnels proxy traffic through regular HTTP request/response patterns, making it look closer to normal web application traffic. It is commonly used with VLESS + TLS/Reality to improve camouflage and traverse restrictive network environments.

## When to Use
- You need traffic to blend into common HTTPS API patterns.
- Your network environment is sensitive to long-lived WebSocket or gRPC signatures.
- You want to combine VLESS identity/auth with HTTP-style uplink/downlink behavior.

## Core Configuration Fields
| Field | Side | Meaning |
| --- | --- | --- |
| `network: xhttp` | client/server | Enables xHTTP transport. |
| `path` | client/server | HTTP request path used by transport, must match on both sides. |
| `host` | client | Optional `Host` header override (for fronting/reverse proxy cases). |
| `mode` | client/server | Transport mode, commonly `auto` (default) or platform-specific variants. |
| `extra.headers` | client | Extra HTTP headers to mimic app/API traffic. |
| `xmux` | client/server | Multiplex tuning such as concurrency limits and connection reuse. |
| `tls` / `reality` | client/server | Encryption/camouflage layer strongly recommended in production. |

## Minimal Example (Client, Clash-Meta style)
```yaml
proxies:
  - name: vless-xhttp
    type: vless
    server: edge.example.com
    port: 443
    uuid: 11111111-2222-3333-4444-555555555555
    tls: true
    servername: cdn.example.com
    network: xhttp
    xhttp-opts:
      path: /api/v1/sync
      host:
        - cdn.example.com
      mode: auto
      headers:
        User-Agent:
          - okhttp/4.12.0
```

## Minimal Example (Server, Xray style)
```json
{
  "inbounds": [
    {
      "port": 443,
      "protocol": "vless",
      "settings": {
        "clients": [
          { "id": "11111111-2222-3333-4444-555555555555" }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "xhttp",
        "security": "tls",
        "tlsSettings": {
          "serverName": "cdn.example.com",
          "certificates": [
            {
              "certificateFile": "/etc/ssl/fullchain.pem",
              "keyFile": "/etc/ssl/privkey.pem"
            }
          ]
        },
        "xhttpSettings": {
          "path": "/api/v1/sync",
          "mode": "auto"
        }
      }
    }
  ]
}
```

## Deployment Notes
- Keep `path` and mode fully aligned between client and server, otherwise handshakes fail.
- Prefer realistic but stable headers; frequently changing fingerprints can hurt reliability.
- If deploying behind Nginx/Caddy/CDN, ensure request buffering and timeout limits fit long-lived proxy streams.
- Start with conservative `xmux` values, then tune concurrency after observing latency and upstream limits.

## Troubleshooting Checklist
- `EOF` immediately after connect: verify UUID, TLS server name, and `path` consistency.
- Frequent reconnects: check reverse proxy idle timeout and HTTP/2 upstream settings.
- Good handshake but poor throughput: reduce header bloat, tune `xmux`, and verify CDN region affinity.
