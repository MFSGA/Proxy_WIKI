# Service Mode Configuration

## Scope

Service mode changes **who owns the client core process**. It does not add proxy
protocol features and it does not change rule, DNS, or outbound semantics.

In foreground mode the desktop application starts and owns the selected core
process directly. In service mode the desktop application delegates core
lifecycle to `Chimera_Service` over local IPC.

```text
Foreground mode

Chimera desktop
      |
      +--> selected core process

Service mode

Chimera desktop
      |
      v
local IPC
      |
      v
chimera-service
      |
      +--> selected core process
```

## Source Boundaries

The desktop-side integration lives primarily under:

- `Chimera/backend/tauri/src/core/clash/core.rs`,
- `Chimera/backend/tauri/src/core/service/`,
- `Chimera/backend/tauri/src/config/chimera/mod.rs`.

The privileged service implementation lives in the `Chimera_Service`
repository. Its IPC definitions and server routes are split between
`chimera_ipc` and `chimera_service`.

## Current IPC Surface

The inspected service source exposes these core operations:

| Endpoint | Purpose |
| --- | --- |
| `GET /status` | Read service/runtime/core status. |
| `POST /core/start` | Start a selected core using a supplied config path. |
| `POST /core/stop` | Stop the running core. |
| `POST /core/restart` | Restart the managed core. |
| `POST /network/set_dns` | Perform the supported privileged DNS operation on platforms where that path is implemented. |

The IPC crate also contains WebSocket event definitions and log-related API
surfaces. Treat these as local control-plane interfaces, not as remote proxy
protocols.

## Foreground vs Service Mode

| Property | Foreground | Service mode |
| --- | --- | --- |
| Core owner | Desktop process | `chimera-service` |
| Lifecycle calls | Direct child-process management | IPC requests to the service |
| Privilege boundary | Desktop/user process | Privileged service boundary |
| Config generation | Desktop | Desktop |
| Proxy protocol implementation | Selected core | Selected core |
| GUI/controller role | Directly manages core | Sends requests and observes service/core state |

The desktop still generates the runtime configuration in service mode. The
service receives the core type and config path; it does not independently merge
profiles or reinterpret proxy rules.

## Start Flow

At a high level, service-mode startup is:

1. Chimera selects the configured core type.
2. Chimera builds or refreshes the generated runtime configuration.
3. The desktop converts its core selection into `chimera_utils::core::CoreType`.
4. Chimera checks/uses the service IPC client.
5. A `/core/start` request is sent with the core type and generated config path.
6. `chimera-service` creates and supervises the child core process.
7. Status/events are used to reflect the resulting runtime state back to the
   desktop application.

The source also handles races where service/core status can change between a
status check and a start request. Documentation should therefore avoid
presenting service start as a single infallible toggle.

## Restart and Configuration Changes

A runtime setting can fall into one of three categories:

- handled through the selected core's own controller/hot-reload path,
- written into generated configuration and requiring core restart,
- owned by Chimera or the OS and not part of core config at all.

Service mode does not change this classification. It changes the restart path
from direct process management to `/core/restart` or a stop/start sequence
through the service.

When documenting an individual setting, verify its actual update path before
claiming that it is hot-reloadable.

## Service Installation and Platform Managers

`Chimera_Service` uses platform service-manager integration to install, start,
stop, query, and uninstall the privileged service. Windows also has dedicated
Windows-service control code.

The exact operating-system registration details are an implementation concern
of `Chimera_Service`; the desktop application should treat the service as a
managed local control endpoint.

Do not assume GUI settings such as “start at boot”, “auto recover”, or “keep
running after GUI exit” exist merely because they are common in other proxy
applications. They should be documented only when the corresponding Chimera
setting and service behavior are present in source.

## Failure Model

Troubleshoot service mode by separating desktop, IPC, service, and core failures:

| Symptom | First boundary to inspect |
| --- | --- |
| Service is not installed or cannot start | OS service manager / installation privileges |
| GUI cannot query status | local IPC endpoint, ACL/permissions, service process |
| `/core/start` fails | core type, config path, executable availability, service-side process spawn |
| Service is healthy but proxy traffic fails | selected core logs/config/protocol path |
| Config change appears ignored | determine whether the setting needs hot reload or core restart |
| Core exits unexpectedly | service core-manager status and captured core output/logs |

A healthy `chimera-service` process does not imply a healthy proxy core, and a
healthy proxy core does not imply successful remote protocol negotiation.

## Security Boundary

Service mode introduces a privileged local control plane. Operational guidance
should therefore emphasize:

- restrict local IPC access with the repository's ACL/security mechanisms,
- do not treat a user-supplied config path as harmless input,
- keep the desktop, service, and shared IPC/types compatible,
- inspect both service logs and core logs when diagnosing privilege-related
  networking failures.

## Verification

Useful source-level checks are:

- confirm `/status` reports the expected core state,
- exercise start/stop/restart through the same IPC client used by Chimera,
- verify the generated config path exists and is readable by the service,
- verify the selected core executable matches the requested `CoreType`,
- test privileged networking operations separately from proxy connectivity.
