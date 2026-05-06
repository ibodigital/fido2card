# fido2lock - Windows System Tray Version

Locks the Windows workstation when a FIDO2/PIV smart card is removed from a supported reader. Designed for shared workstations where users sign in with smart cards and the desktop must lock immediately on card removal.

Includes a system tray app letting users temporarily pause the auto-lock (e.g. for short breaks where the card stays at home).

> **Two variants are available:**
> - **fido2lock** (this section) — locks on card *removal*
> - **fido2switch** ([see below](#alternative-variant-fido2switch--user-switching-on-tap)) — does nothing on removal; disconnects the active session when a *different* card is tapped, so the next user can log in
>
> Pick one — they share scheduled-task names and shouldn't both be installed on the same machine.

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

## Repository layout

```
fido2lock/
├── fido2lock-service.ps1       ← Lock-on-removal service source
├── fido2lock-tray.ps1          ← Lock-on-removal tray source
├── build.ps1                   ← Compiles lock variant → bin\
├── deploy.ps1                  ← Installs lock variant
├── uninstall.ps1               ← Removes lock variant
├── fido2switch-service.ps1     ← User-switching service source (alt variant)
├── fido2switch-tray.ps1        ← User-switching tray source
├── build-switch.ps1            ← Compiles switch variant → bin\
├── deploy-switch.ps1           ← Installs switch variant
├── uninstall-switch.ps1        ← Removes switch variant
├── README.md
└── bin\                        ← Created by build.ps1 / build-switch.ps1
    ├── fido2lock-service.exe
    ├── fido2lock-tray.exe
    ├── fido2switch-service.exe
    └── fido2switch-tray.exe
```

The `bin\` folder is git-ignored (or should be) — sources are tracked, compiled binaries are built per machine.

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
powershell.exe -ExecutionPolicy Bypass -File .\build.ps1
```

This produces:

- `bin\fido2lock-service.exe` (no console, requires admin)
- `bin\fido2lock-tray.exe` (no console, runs as user)

## Deploy

Copy the entire folder (including `bin\` with the freshly built exes) to the target machine, then:

```powershell
# Open elevated PowerShell on the target
cd C:\path\to\fido2lock
powershell.exe -ExecutionPolicy Bypass -File .\deploy.ps1
```

This will:

1. Remove any existing FIDO2-related scheduled tasks
2. Copy both exes from `bin\` to `C:\Program Files\fido2lock\`
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

## Alternative variant: fido2switch — user-switching on tap

Same architecture, different behaviour:

- **Card removal does nothing.**
- **Tapping a *different* card** on the reader disconnects the active session via `tsdiscon.exe`, so the new user can log in.
- Tapping the **same** card again is a no-op.

Intended for shared/kiosk workstations where users hand-off the machine by tapping their card without first signing the previous user out.

### How card identity is determined

On every insertion event, the service uses PC/SC (`winscard.dll`) to send APDU `FF CA 00 00 00` to the card and reads the returned UID/serial. The UID is hex-encoded and stored in `C:\ProgramData\fido2switch\current-card.txt`. On the next insertion:

- New UID == stored UID → no action (same user re-tapping)
- New UID != stored UID → `tsdiscon` the active session, then update the file
- No stored UID yet → record this card as the current one (no disconnect)

If `FF CA` returns a non-success status (e.g. `6A 81` "function not supported", which some contact-mode PIV cards return), the service logs the failure and skips the disconnect rather than acting on bad data. This means the variant is best suited to **contactless** readers (HID Omnikey 5022 with PIV-over-NFC, or any MIFARE-style card) where `FF CA` reliably returns the card's contactless serial. For pure contact PIV cards you may need to extend the service to read the PIV CHUID instead.

### Files

```
fido2switch-service.ps1     ← Service source (insertion + UID compare + tsdiscon)
fido2switch-tray.ps1        ← Tray source (status + pause)
build-switch.ps1            ← Compiles both .ps1 → bin\
deploy-switch.ps1           ← Reads from bin\ and installs
uninstall-switch.ps1        ← Removes everything
```

The compiled exes land in the same `bin\` directory as the lock variant (`fido2switch-service.exe`, `fido2switch-tray.exe`).

### Install paths

```
C:\Program Files\fido2switch\         ← exes
C:\ProgramData\fido2switch\           ← logs, pause file, current-card.txt
```

These are deliberately distinct from the `fido2lock` paths so the two variants don't share state. **Scheduled tasks are not distinct** — `deploy-switch.ps1` removes any existing `FIDO2*` task before installing, on the assumption you only want one variant active.

### Build

```powershell
# On the build machine (run as Administrator)
powershell.exe -ExecutionPolicy Bypass -File .\build-switch.ps1
```

Produces `bin\fido2switch-service.exe` and `bin\fido2switch-tray.exe`.

### Deploy

Copy the entire folder (including `bin\` with the freshly built exes) to the target machine, then:

```powershell
# Open elevated PowerShell on the target
cd C:\path\to\fido2card
powershell.exe -ExecutionPolicy Bypass -File .\deploy-switch.ps1
```

This will:

1. Remove **all** existing `FIDO2*` scheduled tasks (including any `FIDO2 Lock *` tasks — the two variants are mutually exclusive)
2. Copy both exes from `bin\` to `C:\Program Files\fido2switch\`
3. Create `C:\ProgramData\fido2switch\` with `Users` granted Modify
4. Register **FIDO2 Switch Service** task — runs as SYSTEM at startup
5. Register **FIDO2 Switch Tray** task — runs at every user logon
6. Start the service immediately (no reboot needed)

To start the tray for your current session without logging out:

```powershell
Start-ScheduledTask -TaskName "FIDO2 Switch Tray"
```

#### Custom install path

```powershell
.\deploy-switch.ps1 -InstallDir "D:\Tools\fido2switch"
```

### Verify

```powershell
Get-ScheduledTask -TaskName "FIDO2 Switch Service", "FIDO2 Switch Tray" |
    Select-Object TaskName, State, @{N="RunAs";E={$_.Principal.UserId}}

Get-Content "C:\ProgramData\fido2switch\service.log" -Wait
```

A successful first tap looks like:

```
[...] Switch service started as SYSTEM (Identive SCR33xx + HID Omnikey 5022)
[...] First card seen (uid=04A3B91C2D5E80) — recording; no previous session to disconnect
```

A user-switch looks like:

```
[...] Card change: 04A3B91C2D5E80 -> 0419FF7822AB81 — disconnecting active session
[...] Disconnecting session 2
```

### Tray UX

The right-click menu shows:

- **FIDO2 Switch — active** (status)
- **Current card: 04A3B91C2D5E80** (current UID, or `—` if none recorded yet)
- **Pause 5 / 15 / 60 minutes** — while paused, a different card tap is logged but does *not* disconnect
- **Resume now**
- **Exit tray**

The pause file format is identical to the lock variant (ISO 8601 timestamp), just at `C:\ProgramData\fido2switch\pause-until.txt`.

### Resetting the recorded card

If the recorded UID gets out of sync (e.g. you swapped cards while the service was paused), wipe it:

```powershell
Remove-Item "C:\ProgramData\fido2switch\current-card.txt" -Force
```

The next tap will be treated as a fresh "first card" — recorded with no disconnect.

### Uninstall

```powershell
.\uninstall-switch.ps1
# or, to keep the log + current-card.txt for audit:
.\uninstall-switch.ps1 -KeepLogs
```

`uninstall-switch.ps1` only removes `FIDO2 Switch *` tasks; if you also have the lock variant installed, run `uninstall.ps1` separately.

## Troubleshooting

| Symptom                                             | Likely cause                                       | Fix                                                                                    |
| --------------------------------------------------- | -------------------------------------------------- | -------------------------------------------------------------------------------------- |
| `bin directory not found` on deploy                 | Forgot to run build.ps1 first                      | Run `.\build.ps1` then re-run `.\deploy.ps1`                                           |
| Tray icon never appears                             | Tray task disabled or PS2EXE produced a broken exe | Run `Start-ScheduledTask -TaskName "FIDO2 Lock Tray"` and check Task Scheduler history |
| Lock fires but session opens explorer instead       | Old version using `rundll32` still installed       | Run `uninstall.ps1` then `deploy.ps1` again                                            |
| Service log shows "tsdiscon" errors                 | Windows Home edition (no `tsdiscon.exe`)           | Replace with a different lock approach — file an issue                                 |
| Card removal not detected                           | Reader uses a different DeviceID pattern           | See [Adding more reader models](#adding-more-reader-models)                            |
| "Lock-ActiveSession error" in log                   | Permissions or session enumeration failed          | Confirm service is running as SYSTEM, not a regular user                               |
| `Identitätsverweise` / `IdentityNotMappedException` | Old version using `BUILTIN\Users` literal          | Update to current scripts which use SID `S-1-5-32-545`                                 |
| Tray app shows "service is not installed"           | `C:\ProgramData\fido2lock` missing                 | Run `deploy.ps1`                                                                       |
| Pause file written but lock still fires             | Service can't read pause file                      | Check ACL on `C:\ProgramData\fido2lock` — Users should have Modify                     |
| (switch) Log says "UID could not be read"           | Card returned `6A 81` to `FF CA` (contact PIV)     | Switch variant relies on contactless serial — use Omnikey 5022 / NFC, or extend the service to read PIV CHUID |
| (switch) Same card tap keeps disconnecting          | Stored UID corrupted / out of sync                 | `Remove-Item C:\ProgramData\fido2switch\current-card.txt` and tap once to re-record    |
| (switch) Both variants installed at once            | One overwrote the other's tasks                    | Run the matching `uninstall*.ps1` for the variant you don't want, then redeploy        |

## Security notes

- The pause feature is an explicit convenience trade-off. Anyone with interactive logon access can pause the lock for up to one hour. If your security policy does not allow this, remove the tray task from `deploy.ps1`.
- Pause durations are hardcoded in the tray script — adjust the menu items in `fido2lock-tray.ps1` if you need different limits.
- The pause file is per-machine, not per-user. One user pausing affects whoever is at the machine when the next card is removed. For shared workstations this is the desired behaviour; for single-user machines it is irrelevant.
- Pauses do not survive a reboot — the file may be there but the in-memory `$armed` state resets, and the next card insertion arms cleanly.

## License

Internal use only.
