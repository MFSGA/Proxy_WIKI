# AChimera Android Client

## Role in the Ecosystem

`AChimera` is the Android application layer for the Chimera client ecosystem.
It is not a separate proxy protocol implementation. The Android app owns the
platform-specific VPN lifecycle, profile storage, user interface, and telemetry
presentation, while packet forwarding is delegated to the embedded Rust core
through UniFFI.

The core runtime shape is:

```text
Android UI / ViewModels
        |
        v
ChimeraBackend
        |
        +--> profile download / verification / persistence
        |
        v
Android VpnService (TunService)
        |
        +--> create and own Android TUN interface
        +--> protect core sockets from VPN recursion
        |
        v
UniFFI bridge
        |
        v
Chimera Rust client core
        |
        v
SOCKS / HTTP / mixed listeners, rules, DNS, outbound proxies
```

## Source Anchors

The Android repository is easiest to understand through these files:

- `app/src/main/java/rs/chimera/android/backend/ChimeraBackend.kt`: application
  backend contract.
- `app/src/main/java/rs/chimera/android/backend/ChimeraBackendImpl.kt`: profile,
  runtime, controller, traffic, memory, and connection orchestration.
- `app/src/main/java/rs/chimera/android/service/TunService.kt`: Android
  `VpnService` lifecycle and TUN ownership.
- `app/src/main/java/rs/chimera/android/ffi/ChimeraFfi.kt`: UniFFI initialization
  and socket-protection bridge.
- `app/src/main/java/rs/chimera/android/ffi/Clash.kt`: Rust core startup bridge.

## VPN Startup Flow

A normal Android VPN start follows this sequence:

1. The backend verifies that an active profile exists.
2. Android `VpnService.prepare(...)` is used to request VPN permission when the
   user has not granted it yet.
3. `TunService` is started as the Android VPN service.
4. The service resolves and validates the active profile path.
5. Android creates the TUN interface and detaches the file descriptor used by
   the Rust runtime.
6. The profile and runtime overrides are passed through the UniFFI bridge to the
   Chimera client core.
7. The core starts its local listeners and networking runtime.
8. The service publishes runtime state and keeps ownership of the VPN/TUN
   lifecycle until shutdown.

A failure before the Rust core starts should be treated differently from a
failure after the core starts: the former is normally an Android permission,
profile, or TUN setup problem, while the latter belongs to runtime config,
listener, DNS, rule, or outbound initialization.

## Socket Protection

Android VPN applications must prevent their own outbound sockets from being
captured by the VPN again. `AChimera` exposes a bridge from Rust back to
`VpnService.protect(fd)`.

Conceptually:

```text
proxied application packet
        |
        v
Android TUN
        |
        v
Rust proxy core
        |
        +--> create remote socket
                 |
                 +--> VpnService.protect(fd)
                 |
                 v
              physical network
```

Without this protection, a remote proxy connection can recursively enter the
same TUN path and fail or loop.

## Profile Lifecycle

The current backend supports both local and remote profiles.

For local profiles it tracks metadata such as profile ID, display name, file
path, active state, creation time, and size.

For remote profiles it additionally stores source URL and update metadata, and
uses the Rust-side download helper for retrieval. A downloaded profile is not
assumed valid merely because the HTTP request succeeded: configuration
verification is exposed separately through the UniFFI layer.

Profile deletion is deliberately defensive. The repository contains policy
objects for staging, persistence, deletion, and recovery so that an interrupted
or failed delete operation does not silently corrupt the profile catalog.

Relevant tests include:

- `ProfileCatalogPolicyTest`
- `ProfileDeletionPolicyTest`
- `ProfileDeletionRecoveryPolicyTest`
- `ProfileFilePolicyTest`
- `ProfilePersistencePolicyTest`
- `ProfileRemotePolicyTest`

## Runtime Settings

The Android app currently exposes runtime listener overrides for:

- mixed port,
- HTTP port,
- SOCKS port.

These settings are application/runtime overrides. They do not define which
remote proxy protocols are compiled into the embedded core. Protocol
availability still follows the `Chimera_Client` build and configuration.

## Observability

`ChimeraBackendImpl` polls the embedded controller and exposes application state
for:

- total traffic,
- memory usage,
- active connections,
- service/runtime state,
- runtime errors.

The Android UI therefore consumes controller state from the Rust core rather
than maintaining a second independent accounting model.

## Failure Boundaries

When troubleshooting Android, identify the failing layer before changing proxy
protocol settings:

| Symptom | First layer to inspect |
| --- | --- |
| Android never asks for or receives VPN permission | `VpnService.prepare` / platform permission flow |
| Service starts but no TUN FD is available | `TunService` interface creation and detach path |
| Core startup fails immediately | profile verification, runtime overrides, Rust initialization |
| Proxy connects recursively or never leaves the device | socket `protect(fd)` bridge |
| UI shows stale traffic or connections | controller polling/backend state collection |
| Remote profile update fails | download helper, URL policy, temporary-file/persistence path |

## Relationship to Chimera Desktop

`AChimera` and the desktop `Chimera` application are sibling control surfaces,
not two layers that normally run in one forwarding path.

The desktop application can choose and manage external core processes or
`Chimera_Service`; Android embeds the client core in the application and passes
its TUN file descriptor through UniFFI. Both ultimately depend on
`Chimera_Client` behavior for Clash-style configuration and proxy forwarding.
