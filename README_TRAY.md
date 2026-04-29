# fido2lock - System Tray Version

Locks the Windows workstation when a FIDO2/PIV smart card is removed from a supported reader. Designed for shared workstations where users sign in with smart cards and the desktop must lock immediately on card removal.

Includes a system tray app letting users temporarily pause the auto-lock (e.g. for short breaks where the card stays at home).

## Features

- Watches smart card readers for card removal via WMI events
- Supports **Identive SCR33xx USB SC Reader** and **HID Omnikey 5022**
- Runs as SYSTEM at machine boot — works for every user, no per-user setup
- System tray app with **Pause 5 / 15 / 60 minutes** and **Resume now**
- Pauses auto-expire (no risk of forgetting and leaving auto-lock disabled)
- Logs to `C:\ProgramData\fido2lock\service.log`
- No dependency on the Windows `SCPolicySvc` (Smart Card Removal Policy) service

## Architecture

```
┌─────────────────────────────────┐
│  fido2lock-service.exe          │  Runs as SYSTEM at boot
│  (monitors WMI for card events) │  Locks user session via tsdiscon.exe
└────────────┬────────────────────┘
             │ reads/writes
             ▼
┌─────────────────────────────────┐
│  C:\ProgramData\fido2lock\      │
│    service.log                  │  Service activity log
│    pause-until.txt              │  Shared pause state
│    trigger.txt                  │  Internal WMI→loop signal
└────────────┬────────────────────┘
             ▲
             │ reads/writes
┌─────────────────────────────────┐
│  fido2lock-tray.exe             │  Runs per-user at logon
│  (NotifyIcon + WinForms menu)   │  Right-click → pause options
└─────────────────────────────────┘
```

The service runs once per machine (as SYSTEM) and never stops. The tray app starts in each user's session and only writes to the shared pause file. They communicate via that file, so no network sockets, named pipes, or IPC complexity.

## Repository contents

| File                    | Purpose                                                |
| ----------------------- | ------------------------------------------------------ |
| `fido2lock-service.ps1` | Service script (compiled to .exe) — monitors and locks |
| `fido2lock-tray.ps1`    | Tray script (compiled to .exe) — pause UI              |
| `build.ps1`             | Compiles both scripts to .exe with PS2EXE              |
| `deploy.ps1`            | Installs both exes and registers scheduled tasks       |
| `uninstall.ps1`         | Removes everything cleanly                             |
| `README.md`             | This file                                              |

## Requirements

### Build machine (developer workstation)

- Windows 10/11 with PowerShell 5.1+
- Internet access (to install PS2EXE module from PSGallery)
- Run as Administrator

### Target machine

- Windows 10/11
- Smart card reader: Identive SCR33xx or HID Omnikey 5022
- Smart Card service (`SCardSvr`) present (default in Windows)
- Local admin rights to run `deploy.ps1`
- `tsdiscon.exe` (ships with Windows Pro/Enterprise — verify with `Get-Command tsdiscon.exe`)

## Build

On your build machine:

```powershell
git clone <repo-url> fido2lock
cd fido2lock
.\build.ps1
```

This produces:

- `fido2lock-service.exe` (no console, requires admin)
- `fido2lock-tray.exe` (no console, runs as user)

## Deploy

Copy the entire folder (including the two newly built exes) to the target machine, then:

```powershell
# Open elevated PowerShell on the target
cd C:\path\to\fido2lock
.\deploy.ps1
```

This will:

1. Remove any existing FIDO2-related scheduled tasks
2. Copy both exes to `C:\Program Files\fido2lock\`
3. Create `C:\ProgramData\fido2lock\` with `Users` granted Modify
4. Register **FIDO2 Lock Service** task — runs as SYSTEM at startup
5. Register **FIDO2 Lock Tray** task — runs at every user logon
6. Start the service immediately (no reboot needed)

The tray app appears for new logins. To get it for your current session without logging out:

```powershell
Start-ScheduledTask -TaskName "FIDO2 Lock Tray"
```

### Custom install path

```powershell
.\deploy.ps1 -InstallDir "D:\Tools\fido2lock"
```

## Verification

Confirm tasks are registered and running:

```powershell
Get-ScheduledTask -TaskName "FIDO2 Lock Service", "FIDO2 Lock Tray" |
    Select-Object TaskName, State, @{N="RunAs";E={$_.Principal.UserId}}
```

Expected output:

```
TaskName             State   RunAs
--------             -----   -----
FIDO2 Lock Service   Running SYSTEM
FIDO2 Lock Tray      Ready   Users
```

Watch the service log live:

```powershell
Get-Content "C:\ProgramData\fido2lock\service.log" -Wait
```

## Usage (end user)

After logon, a shield icon appears in the system tray. Right-click for options:

- **FIDO2 Lock — active** (status, disabled menu item)
- **Pause 5 minutes**
- **Pause 15 minutes**
- **Pause 1 hour**
- **Resume now**
- **Exit tray**

When paused, the icon changes to a warning symbol and the tooltip shows the pause expiry time. The pause auto-expires — there is no way to pause indefinitely, by design.

## Pause file format

```
C:\ProgramData\fido2lock\pause-until.txt
```

Single line: ISO 8601 datetime (e.g. `2026-04-29T15:30:00.0000000+02:00`). When the current time exceeds this, the service treats the pause as expired and removes the file.

If you need to **administratively cancel a pause** without using the tray:

```powershell
Remove-Item "C:\ProgramData\fido2lock\pause-until.txt" -Force
```

## Adding more reader models

Both the service script and any future readers need their `DeviceID` pattern added in two places:

1. **`Get-CardPresent` function** — add another `-or` clause
2. **WMI queries** (`$insertQuery` and `$deleteQuery`) — add another `OR TargetInstance.DeviceID LIKE 'SCFILTER%YOURREADER%'`

To find the right pattern for a new reader, plug in a card and run:

```powershell
Get-WmiObject Win32_PnPEntity |
    Where-Object { $_.DeviceID -like 'SCFILTER*' } |
    Select-Object Description, DeviceID
```

Use a unique substring of the resulting DeviceID. Recompile and redeploy.

## Uninstall

```powershell
.\uninstall.ps1
```

Or to keep the logs for audit:

```powershell
.\uninstall.ps1 -KeepLogs
```

## Troubleshooting

| Symptom                                       | Likely cause                                       | Fix                                                                                    |
| --------------------------------------------- | -------------------------------------------------- | -------------------------------------------------------------------------------------- |
| Tray icon never appears                       | Tray task disabled or PS2EXE produced a broken exe | Run `Start-ScheduledTask -TaskName "FIDO2 Lock Tray"` and check Task Scheduler history |
| Lock fires but session opens explorer instead | Old version using `rundll32` still installed       | Run `uninstall.ps1` then `deploy.ps1` again                                            |
| Service log shows "tsdiscon" errors           | Windows Home edition (no `tsdiscon.exe`)           | Replace with a different lock approach — file an issue                                 |
| Card removal not detected                     | Reader uses a different DeviceID pattern           | See [Adding more reader models](#adding-more-reader-models)                            |
| "Lock-ActiveSession error" in log             | Permissions or session enumeration failed          | Confirm service is running as SYSTEM, not a regular user                               |
| Tray app shows "service is not installed"     | `C:\ProgramData\fido2lock` missing                 | Run `deploy.ps1`                                                                       |
| Pause file written but lock still fires       | Service can't read pause file                      | Check ACL on `C:\ProgramData\fido2lock` — Users should have Modify                     |

## Security notes

- The pause feature is an explicit convenience trade-off. Anyone with interactive logon access can pause the lock for up to one hour. If your security policy does not allow this, remove the tray task from `deploy.ps1`.
- Pause durations are hardcoded in the tray script — adjust the menu items in `fido2lock-tray.ps1` if you need different limits.
- The pause file is per-machine, not per-user. One user pausing affects whoever is at the machine when the next card is removed. For shared workstations this is the desired behaviour; for single-user machines it is irrelevant.
- Pauses do not survive a reboot — the file may be there but the in-memory `$armed` state resets, and the next card insertion arms cleanly.

## License

Internal use only.
