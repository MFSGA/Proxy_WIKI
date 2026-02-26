# Service Mode Configuration

## Scope and Intent
In Chimera GUI, service mode runs the proxy core as a background system service while the GUI acts as the control surface.
This separation is important when you need stable long-running behavior, elevated networking privileges, or startup-before-login workflows.

## Foreground Mode vs Service Mode
| Mode | Runtime shape | Typical use | Main limitation |
| --- | --- | --- | --- |
| Foreground mode | GUI process owns the core directly | Development and quick profile checks | Core stops when GUI exits or user logs out |
| Service mode | System service owns the core; GUI controls it via local IPC | Daily use, TUN/transparent routing, always-on setups | Requires service install and permission management |

## Why Enable Service Mode
- Keep traffic forwarding alive even if the GUI is closed.
- Start proxy service automatically at boot/login with predictable lifecycle.
- Support privileged paths (for example TUN, policy routing, transparent capture) more reliably.
- Reduce behavior drift across user sessions on shared machines.

## Configuration Workflow in Chimera GUI
1. Prepare and validate your active profile in normal mode first.
2. Open Chimera GUI settings and enable service mode.
3. Install/register the service when prompted by the GUI.
4. Choose startup policy:
   - Manual: start only when needed.
   - Automatic: start at system boot (recommended for always-on use).
5. Apply settings and trigger a service restart from the GUI.
6. Confirm the GUI can reconnect to the local control endpoint after restart.

## Key Options and Recommended Defaults
Option labels may vary slightly by platform/build, but the intent is usually the same:

| GUI option (common naming) | Meaning | Suggested default |
| --- | --- | --- |
| `Enable Service Mode` | Switch core runtime ownership to system service | On for long-term daily usage |
| `Install/Repair Service` | Register or repair service metadata | Run after first enable and after upgrades |
| `Start Service at Boot` | Auto-start service during system startup | On for TUN or gateway-style setups |
| `Keep Running After GUI Exit` | Leave service active when GUI closes | On |
| `Require Elevation on Apply` | Prompt for admin/root rights when applying privileged changes | On |
| `Auto Recover on Crash` | Restart service process after abnormal exit | On |

## Platform Notes
### Windows
- Service mode is usually backed by Windows Service Control Manager.
- Use an elevated shell for first-time install/repair if GUI prompts fail.
- Verify state with:

```powershell
Get-Service *chimera*
```

### Linux
- Service mode is typically managed by `systemd` (`chimera.service` or similar unit name).
- Prefer explicit restart after profile changes that affect TUN/routing behavior.
- Verify state with:

```bash
systemctl status chimera.service
journalctl -u chimera.service -n 100 --no-pager
```

### macOS
- Service mode is usually implemented through `launchd` (system daemon style).
- Ensure GUI and service binaries come from the same build channel/version.

## Rollout Strategy
1. Start with SOCKS/listener-only profile and confirm baseline connectivity.
2. Enable service mode and verify reconnect behavior after GUI restart.
3. Enable advanced options (TUN, DNS hijack, transparent capture) incrementally.
4. Reboot once and verify auto-start, rule hit behavior, and DNS resolution stability.

## Troubleshooting Checklist
| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Service cannot start | Missing admin/root privileges | Reinstall/repair service with elevation |
| GUI shows "disconnected from core" | Control endpoint mismatch or service crash loop | Reapply service settings and inspect service logs |
| TUN features do not take effect | Service running but privileged route setup failed | Check system logs and permission/capability grants |
| Profile changes seem ignored | GUI saved config but service did not reload | Trigger explicit service restart from GUI |
| Traffic stops after logout | Foreground mode still active | Recheck that service mode is enabled and installed |

## Operational Boundary
Service mode changes process lifecycle and permission model, not proxy policy semantics.
Your rules, DNS strategy, and outbound definitions are still determined by the active Chimera profile.
