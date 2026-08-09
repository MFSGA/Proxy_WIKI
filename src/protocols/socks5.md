# SOCKS5

## Positioning

SOCKS5 is a general-purpose application proxy protocol standardized by
RFC 1928. It can relay TCP connections and defines `UDP ASSOCIATE` for UDP
traffic. Because SOCKS operates below HTTP semantics, applications can use it
for many protocols without the proxy needing to understand the application
payload.

For local Chimera deployments, SOCKS5 is usually the best baseline listener to
validate before enabling TUN or transparent routing.

## Standards

The main standards are:

- RFC 1928 — SOCKS Protocol Version 5.
- RFC 1929 — Username/Password Authentication for SOCKS V5.
- RFC 1961 — GSS-API Authentication Method for SOCKS V5.
- RFC 3089 — SOCKS-based IPv6/IPv4 Gateway operation.

## Protocol Flow

### Method negotiation

1. The client opens a TCP connection to the SOCKS5 server.
2. The client sends the authentication methods it supports.
3. The server chooses one method.
4. If required, the client performs the selected authentication exchange.

### Proxy request

After negotiation, the client sends one of the SOCKS5 commands:

- `CONNECT` — create an outbound TCP connection.
- `BIND` — ask the proxy to accept a related incoming connection.
- `UDP ASSOCIATE` — establish the control association for UDP relay.

The request can identify a destination by IPv4 address, IPv6 address, or domain
name.

### `CONNECT`

For the common TCP case:

1. The client asks the proxy to connect to a destination.
2. The proxy evaluates access and routing policy.
3. The proxy returns a success or failure reply.
4. After success, client and server relay the TCP byte stream.

### `UDP ASSOCIATE`

UDP relay uses the TCP SOCKS connection as the lifetime/control channel. The
proxy returns an address and UDP port where the client sends SOCKS-framed UDP
datagrams. The association ends when the corresponding TCP control connection
ends.

UDP support is therefore a separate capability from basic SOCKS5 TCP support;
do not assume that every SOCKS5 implementation supports it equally well.

## Wire-Level Interaction and State Machine

The most important difference between SOCKS5 and many modern proxy protocols is
that SOCKS5 has a small explicit control protocol before raw forwarding begins.
After the handshake completes, the proxy normally stops interpreting payload
bytes.

### TCP connection and negotiation

The TCP session between application and SOCKS server starts with a method
selection exchange:

```text
Client -> Server
+----+----------+----------------+
|VER | NMETHODS | METHODS        |
+----+----------+----------------+
|0x05| 1 byte   | N bytes        |
+----+----------+----------------+

Server -> Client
+----+--------+
|VER | METHOD |
+----+--------+
|0x05| 1 byte |
+----+--------+
```

`METHOD` determines the next state. Common values include:

- `0x00` — no authentication.
- `0x02` — username/password authentication defined by RFC 1929.
- `0xff` — no acceptable method.

### Username/password authentication

When RFC 1929 authentication is selected, the exchange becomes:

```text
Client -> Server
+----+------+----------+------+----------+
|VER | ULEN | UNAME    | PLEN | PASSWD   |
+----+------+----------+------+----------+

Server -> Client
+----+--------+
|VER | STATUS |
+----+--------+
```

The authentication layer only proves identity to the SOCKS server. It does
not encrypt the TCP stream.

### Request command frame

After authentication, the client sends:

```text
+----+-----+------+----------+----------+
|VER | CMD | RSV  | ATYP     | DST.ADDR |
+----+-----+------+----------+----------+
|PORT|
+----+
```

Important fields:

- `CMD` selects `CONNECT`, `BIND`, or `UDP ASSOCIATE`.
- `ATYP` selects address encoding.
- IPv4 uses 4 bytes.
- IPv6 uses 16 bytes.
- Domain names use one length byte followed by domain bytes.
- `DST.PORT` is an unsigned 16-bit network-order value.

### Server reply

The server returns:

```text
+----+-----+------+----------+----------+
|VER | REP | RSV  | ATYP     | BND.ADDR |
+----+-----+------+----------+----------+
|BND.PORT|
+---------+
```

`REP` communicates the result. RFC 1928 defines these one-byte values:

| `REP` | Meaning |
| --- | --- |
| `0x00` | succeeded |
| `0x01` | general SOCKS server failure |
| `0x02` | connection not allowed by ruleset |
| `0x03` | network unreachable |
| `0x04` | host unreachable |
| `0x05` | connection refused |
| `0x06` | TTL expired |
| `0x07` | command not supported |
| `0x08` | address type not supported |
| `0x09`-`0xff` | unassigned |

For a failed request, RFC 1928 requires the SOCKS server to close the TCP
connection shortly after sending the reply. A client should therefore treat a
non-zero `REP` as terminal for that request instead of waiting for a later
application payload.

After a successful `CONNECT`, the state machine changes from **control
protocol** to **transparent byte relay**:

```text
Application TCP bytes
        |
        v
 SOCKS5 server
        |
        v
 Destination TCP socket
```

The SOCKS server does not parse HTTP, TLS, SSH, or application protocols after
this transition.

### `BIND`: two replies, not one

`BIND` is unusual because one request can produce **two successful server
replies**. It was designed for protocols in which the proxied application
expects a peer to connect back to it.

```text
Client -> SOCKS server
    BIND request(target identity)

SOCKS server -> Client
    Reply #1: BND.ADDR/BND.PORT where the server is listening

Remote peer -> SOCKS server
    inbound TCP connection

SOCKS server -> Client
    Reply #2: BND.ADDR/BND.PORT identifying the connected peer

then
    bidirectional TCP relay
```

The first `BND.ADDR/BND.PORT` is the listening endpoint created by the SOCKS
server. The second identifies the remote peer after the inbound connection is
accepted. This is materially different from `CONNECT`, where one success reply
is enough to enter the relay state.

An implementation state machine therefore needs a distinct `BIND_WAIT_PEER`
state rather than treating every `REP=0x00` as permission to begin application
relay immediately.

### `UDP ASSOCIATE` datagram wire format

`UDP ASSOCIATE` uses the TCP SOCKS connection only as the control/lifetime
channel. UDP payloads themselves use a separate SOCKS5 UDP header:

```text
+----------+------+----------+----------+----------+----------+
| RSV      | FRAG | ATYP     | DST.ADDR | DST.PORT | DATA     |
+----------+------+----------+----------+----------+----------+
| 2 bytes  | 1    | 1        | variable | 2        | variable |
+----------+------+----------+----------+----------+----------+
```

Fields:

- `RSV` is two zero bytes (`0x0000`).
- `FRAG=0x00` means the datagram is not fragmented.
- `ATYP`, `DST.ADDR`, and `DST.PORT` use the same destination-address model as
  the TCP request command.
- `DATA` is exactly one application UDP datagram payload.

The important boundary property is that UDP itself already preserves datagram
boundaries. SOCKS5 therefore prepends routing metadata to **each UDP datagram**
instead of turning all UDP traffic into one byte stream.

#### Fragmentation semantics

RFC 1928 defines a SOCKS-layer fragmentation mechanism through `FRAG`, but also
states that an implementation may choose not to support it. An implementation
that does not support fragmentation must drop any datagram whose `FRAG` field
is not zero.

When fragmentation is implemented, the low seven bits carry the fragment
sequence number and the high bit marks the final fragment. Reassembly has a
short expiration timer and a fragment arriving with a lower sequence number
than the highest already seen causes the reassembly queue to be discarded.

This makes SOCKS5 fragmentation very different from protocols such as Hysteria
2 or TUIC, whose fragment headers explicitly carry packet/session identifiers
and fragment counts.

### UDP association lifecycle and source binding

The client first sends a normal TCP `UDP ASSOCIATE` request. A successful reply
returns `BND.ADDR/BND.PORT`, the UDP relay endpoint to which the client sends
SOCKS5 UDP datagrams.

```text
TCP control connection
Client ------------------------------ SOCKS server
       UDP ASSOCIATE
       <--- REP=0, BND.ADDR:BND.PORT

UDP data path
Client ===== SOCKS5 UDP datagrams ===> BND.ADDR:BND.PORT
                                      |
                                      +----> destination UDP sockets
```

The TCP connection is the association's lifetime anchor: once it closes, the
UDP association terminates. RFC 1928 also requires the server to restrict relay
traffic to the client associated with that TCP request rather than behaving as
an unrestricted public UDP forwarder.

The client may put all-zero address/port values in the request when it does not
know the UDP source endpoint at request time. The server reply, not the request,
is the authoritative destination for the client's SOCKS-encapsulated UDP
traffic.

### Control/data state machine

The complete baseline state machine is therefore:

```text
TCP_CONNECTED
     |
     v
METHOD_NEGOTIATION
     |
     +-- 0xff --------------------------> CLOSE
     |
     v
AUTH_SUBNEGOTIATION (if selected)
     |
     +-- auth failure ------------------> CLOSE
     |
     v
REQUEST
     |
     +-- CONNECT --> REPLY
     |                 |
     |                 +-- REP != 0 ----> CLOSE
     |                 +-- REP == 0 ----> TCP_RELAY
     |
     +-- BIND ----> REPLY_1
     |                 |
     |                 +-- failure -----> CLOSE
     |                 +-- success -----> BIND_WAIT_PEER
     |                                      |
     |                                      v
     |                                    REPLY_2
     |                                      |
     |                                      +-- success -> TCP_RELAY
     |
     +-- UDP ASSOCIATE -> REPLY
                           |
                           +-- success -> UDP_ASSOCIATED
                                           |
                                           +-- TCP control closes -> END
```

### Packet-capture view

SOCKS5 is unencrypted unless the selected authentication method adds its own
encapsulation. A normal packet capture can therefore expose the protocol
phases directly:

```text
TCP SYN/SYN-ACK/ACK
  -> 05 NMETHODS METHODS...
  <- 05 METHOD
  -> optional authentication subnegotiation
  -> 05 CMD 00 ATYP DST.ADDR DST.PORT
  <- 05 REP 00 ATYP BND.ADDR BND.PORT
  -> application bytes (CONNECT/BIND)
```

For UDP, the capture additionally shows independent UDP packets beginning with
`00 00 FRAG ATYP ...`. This clear separation between a TCP control association
and a UDP data plane is one of the most useful reference points when comparing
SOCKS5 with QUIC-native proxy protocols.

## SOCKS5 Compared With Modern Proxy Protocols

SOCKS5 is useful as a reference model because most modern proxy protocols solve
the same logical problems with additional layers:

| Function | SOCKS5 | Modern protocols |
| --- | --- | --- |
| User selection | METHOD + authentication | UUID/password/token systems |
| Destination address | ATYP + DST.ADDR | Similar address structures or protocol-specific metadata |
| TCP forwarding | CONNECT then raw stream | Usually stream multiplexing or framed transport |
| UDP forwarding | UDP ASSOCIATE | QUIC datagrams, custom UDP framing, multiplexed channels |
| Encryption | Not included | Usually TLS, QUIC TLS, REALITY, or protocol-specific security |
| Multiplexing | Not defined | Common in QUIC/Xray transports |

The conceptual mapping is:

```text
SOCKS5 CONNECT request
        |
        +--> destination metadata
        |
        +--> authentication
        |
        +--> byte relay

Modern protocol
        |
        +--> authentication
        +--> destination metadata
        +--> transport security
        +--> multiplex/session management
        +--> framed data relay
```

Modern protocols generally did not replace the SOCKS5 idea; they expanded the
control plane and moved more functionality into the protocol itself.

## Minimal Configuration

A local `chimera_client`-style profile can start with:

```yaml
bind_address: "127.0.0.1"
allow_lan: false
socks_port: 7891
```

An application can then use:

```text
socks5://127.0.0.1:7891
```

When DNS behavior matters, distinguish between applications that resolve the
domain locally and applications that pass the domain name to the SOCKS proxy.
That difference can affect domain rules.

## Strengths

- Generic TCP proxying without HTTP-specific assumptions.
- Domain-name, IPv4, and IPv6 destination forms.
- Standardized UDP relay mechanism.
- Widely supported by developer tools, browsers, SSH tooling, and networking
  libraries.
- Low protocol overhead and easy local debugging.

## Limitations

- SOCKS5 itself does not provide transport encryption.
- Application support is required unless traffic is captured by another layer.
- UDP relay behavior can vary among clients, NATs, and proxy implementations.
- Basic username/password authentication should not be treated as a substitute
  for encrypted transport.

## DNS and Rule Interaction

SOCKS5 can preserve a domain name all the way to the proxy when the application
uses remote resolution semantics. If the application resolves locally first,
the proxy may only see the resulting IP address.

This matters for rules such as:

```yaml
DOMAIN-SUFFIX,example.com,Proxy
```

If a domain rule unexpectedly stops matching, compare the application's DNS
behavior with the client DNS mode described in [DNS Module](../chimera_client/dns.md).

## Security Notes

For desktop use, bind SOCKS5 to loopback unless LAN access is intentional.
Publicly exposing an unauthenticated SOCKS listener creates an open-proxy risk.
If remote SOCKS access is required, place it behind a secure authenticated
channel rather than relying on SOCKS5 alone for confidentiality.

## Chimera Status

### Chimera_Client

SOCKS5 is documented as a current client-core inbound and is the recommended
starting point for validating proxy profiles. Treat TCP `CONNECT` as the
baseline capability; validate UDP association separately when an application
requires UDP.

### Chimera GUI

Chimera configures the listener through the selected core. It does not itself
implement the SOCKS5 protocol.

### Chimera_Server

The current server capability map includes SOCKS-related inbound work. That is
an implementation map rather than a guarantee of complete RFC 1928 parity, so
server deployments should verify the commands and authentication modes they
actually require.

## Troubleshooting

1. Confirm the listener is bound to the expected address and port.
2. Test a simple TCP destination before testing UDP.
3. If domain rules fail, determine whether the application sends a domain name
   or a pre-resolved IP address.
4. If authentication fails, test without authentication on loopback to isolate
   protocol behavior from credential configuration.
5. For UDP failures, verify that the TCP control connection remains open and
   that local firewall/NAT rules allow the returned UDP relay endpoint.
6. If SOCKS works but TUN does not, debug TUN routing separately rather than
   changing the proxy node configuration.

## References

- RFC 1928: <https://www.rfc-editor.org/rfc/rfc1928>
- RFC 1929: <https://www.rfc-editor.org/rfc/rfc1929>
- RFC 1961: <https://www.rfc-editor.org/rfc/rfc1961>
- RFC 3089: <https://www.rfc-editor.org/rfc/rfc3089>

## Appendices

### RFC 1928 (Full Text)

{{#include ../../third_party/rfc/rfc1928.md:3}}

### RFC 1929 (Full Text)

{{#include ../../third_party/rfc/rfc1929.md:3}}

### RFC 1961 (Full Text)

{{#include ../../third_party/rfc/rfc1961.md:3}}

### RFC 3089 (Full Text)

{{#include ../../third_party/rfc/rfc3089.md:3}}
