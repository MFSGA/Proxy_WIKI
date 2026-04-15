# Chimera GUI

## Design Goals

`Chimera` serves as a high-performance ingress layer responsible for terminating client sessions, enforcing policies, and forwarding traffic to the target destination. A single ingress port can simultaneously expose multiple proxy protocols.

The core design priorities of Chimera are:

* minimizing handshake latency,
* providing fine-grained access control,
* ensuring cross-platform compatibility,
* enabling horizontal scalability,
* offer built-in observability.

## Currently Supported Platforms

### First Tier
- 🖥️ Windows ![Windows](https://img.shields.io/badge/Windows-supported-0078D6?logo=windows&logoColor=white)
- 🐧 Ubuntu
- 🍎 macOS

### Second Tier
- ❄️ NixOS

## Currently Supported Protocols

Please refer to [`Chimera_Client`](./chimera_client.md) and `clash-rs`.

---

