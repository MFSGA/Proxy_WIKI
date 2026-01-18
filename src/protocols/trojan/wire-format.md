# Trojan Wire Format

### TLS Handshake
- The client performs a normal TLS handshake first.
- If the handshake fails, the server closes the connection like a regular HTTPS server.
- Some implementations also return an nginx-like response to plain HTTP probes.

### Initial Request
After TLS is established, the first application data packet is:

```text
+-----------------------+---------+----------------+---------+----------+
| hex(SHA224(password)) |  CRLF   | Trojan Request |  CRLF   | Payload  |
+-----------------------+---------+----------------+---------+----------+
|          56           | 0x0D0A  |    Variable    | 0x0D0A  | Variable |
+-----------------------+---------+----------------+---------+----------+
```

### Trojan Request
Trojan Request uses a SOCKS5-like format:

```text
+-----+------+----------+----------+
| CMD | ATYP | DST.ADDR | DST.PORT |
+-----+------+----------+----------+
|  1  |  1   | Variable |    2     |
+-----+------+----------+----------+
```

- CMD values: 0x01 CONNECT, 0x03 UDP ASSOCIATE.
- ATYP values: 0x01 IPv4, 0x03 DOMAINNAME, 0x04 IPv6.
- DST.ADDR is the destination address, DST.PORT is network byte order.
- SOCKS5 field details: https://tools.ietf.org/html/rfc1928

### UDP Associate Framing
When CMD is UDP ASSOCIATE, each UDP datagram is framed in the TLS stream as:

```text
+------+----------+----------+--------+---------+----------+
| ATYP | DST.ADDR | DST.PORT | Length |  CRLF   | Payload  |
+------+----------+----------+--------+---------+----------+
|  1   | Variable |    2     |   2    | 0x0D0A  | Variable |
+------+----------+----------+--------+---------+----------+
```

- Length is the payload size in network byte order.
- Payload is the raw UDP datagram.

### Notes
- The first TLS record can include payload immediately after the request, reducing packet count and length patterns.
- Clients often expose a local SOCKS5 proxy and translate local SOCKS5 requests into Trojan requests.
