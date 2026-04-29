# fido2card — Lock Workstation on Smart Card Removal

Monitors a smart card reader for card removal events and immediately locks the Windows workstation when the card is pulled out.

## Background

This script was developed for environments using a **FIDO2/PIV card** in an **Identive SCR33xx USB smart card reader**. The standard Windows `Smart Card Removal Policy` service (`SCPolicySvc`) was not viable in this environment (service missing or fails to start), so this script provides the same behaviour independently.

## How It Works

Windows exposes the inserted card as a `Win32_PnPEntity` device with a `DeviceID` beginning with `SCFILTER\...\IDENTIVE...`. This device appears when a card is inserted and disappears when it is removed.

The script uses **WMI event subscriptions** to watch for that device being deleted, then writes a trigger file which the main polling loop detects and acts on.

```
Card removed from reader
        │
        ▼
WMI __InstanceDeletionEvent fires (within 2 seconds)
        │
        ▼
Action scriptblock writes "Deleted" to %TEMP%\fido2trigger.txt
        │
        ▼
Main loop detects trigger file
        │
        ▼
rundll32.exe user32.dll,LockWorkStation
```

### Why a trigger file?

WMI event action scriptblocks run in a **background runspace** with a restricted environment. Calling `rundll32.exe` or interactive Win32 APIs directly from that runspace is unreliable. Writing to a temp file and acting from the foreground loop is a simple and reliable workaround.

## Requirements

- Windows 10 / Windows 11
- Identive SCR33xx USB smart card reader (or compatible — see [Adapting to Other Readers](#adapting-to-other-readers) below)
- PowerShell 5.1 or later
- The **Smart Card service** (`SCardSvr`) must be present (it does not need to be running — Windows starts it on demand)
- Does **not** require `SCPolicySvc`

## Usage

Run the script in an **elevated PowerShell session** (Run as Administrator):

```powershell
powershell.exe -ExecutionPolicy Bypass -File fido2lock.ps1
```

## Compile to EXE

There's no native way to compile PowerShell to a true executable, but the standard tool used for this is PS2EXE. It wraps the script in a .NET executable that bundles a PowerShell host.

```
# Install from PowerShell Gallery (run as Administrator)
Install-Module -Name ps2exe -Scope CurrentUser -Force

# Compile your script
Invoke-PS2EXE -InputFile fido2lock.ps1 -OutputFile fido2lock.exe -NoConsole -RequireAdmin -NoOutput
```

The flags used:

- NoConsole — runs without a console window (good for a background lock monitor)
- RequireAdmin — embeds a UAC manifest so it automatically requests elevation on launch
- NoOutput suppresses all output. But if you want to keep logging for debugging purposes, write to a file instead of the console

Log file will be at %TEMP%\fido2lock.log — you can tail it any time to confirm it's working:

```
Get-Content "$env:TEMP\fido2lock.log" -Wait
```

### What you get

The output is a standalone .exe that runs on any Windows machine with .NET Framework 4.x installed (which is present by default on all Windows 10/11 machines). The target machine does not need PowerShell Gallery or ps2exe installed — just the exe itself.
Caveats worth knowing

It's a wrapper, not a true native compile — the PowerShell runtime is still invoked inside the exe
Antivirus tools sometimes flag ps2exe outputs as suspicious because malware uses the same technique — you may need to whitelist it in your endpoint protection
If you're deploying via your RMM or AD, signing the exe with a code signing certificate avoids the AV issue

### Run on Windows Start

The cleanest way for a background admin process like this is a Scheduled Task, since it handles elevation automatically and survives across user switches.
Run this once in an elevated PowerShell to register it:

To run it minimised at startup, create a scheduled task:

```powershell
$action = New-ScheduledTaskAction -Execute "C:\Scripts\fido2lock.exe"

$trigger = New-ScheduledTaskTrigger -AtStartup

$settings = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit 0 `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1)

$principal = New-ScheduledTaskPrincipal `
    -UserId "SYSTEM" `
    -LogonType ServiceAccount `
    -RunLevel Highest

Register-ScheduledTask `
    -TaskName "FIDO2 Lock" `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -Principal $principal `
    -Force
```

- ExecutionTimeLimit 0 — runs forever, no timeout
- RunLevel Highest — runs elevated (UAC) automatically
  RestartCount 3 — restarts the exe up to 3 times if it crashes

Then to manage it:

```
# Check it's registered
Get-ScheduledTask -TaskName "FIDO2 Lock" | Select-Object TaskName, TaskPath, State, @{
    Name="RunAs"; Expression={ $_.Principal.UserId }
}, @{
    Name="Trigger"; Expression={ $_.Triggers.CimClass.CimClassName }
}

# Start it manually right now without rebooting
Start-ScheduledTask -TaskName "FIDO2 Lock"

# Remove it
Unregister-ScheduledTask -TaskName "FIDO2 Lock" -Confirm:$false
```

Put the `fido2lock.exe` in `C:\Scripts\` (or whatever path you prefer) before registering the task, and it will auto-start at every logon from that point on.

## The Script

```powershell
$triggerFile = Join-Path $env:TEMP "fido2trigger.txt"

$insertQuery = "SELECT * FROM __InstanceCreationEvent WITHIN 2 " +
               "WHERE TargetInstance ISA 'Win32_PnPEntity' " +
               "AND TargetInstance.DeviceID LIKE 'SCFILTER%IDENTIVE%'"

$deleteQuery  = "SELECT * FROM __InstanceDeletionEvent WITHIN 2 " +
               "WHERE TargetInstance ISA 'Win32_PnPEntity' " +
               "AND TargetInstance.DeviceID LIKE 'SCFILTER%IDENTIVE%'"

$insertedAction = [scriptblock]::Create("Set-Content -Path '$triggerFile' -Value 'Inserted'")
$deletedAction  = [scriptblock]::Create("Set-Content -Path '$triggerFile' -Value 'Deleted'")

Unregister-Event -SourceIdentifier "CardInserted" -ErrorAction SilentlyContinue
Unregister-Event -SourceIdentifier "CardRemoved"  -ErrorAction SilentlyContinue

Register-WmiEvent -Query $insertQuery -Action $insertedAction -SourceIdentifier "CardInserted" | Out-Null
Register-WmiEvent -Query $deleteQuery  -Action $deletedAction  -SourceIdentifier "CardRemoved"  | Out-Null

Write-Host "Monitoring Identive reader for card removal. Press Ctrl+C to stop."

while ($true) {
    if (Test-Path $triggerFile) {
        $content = Get-Content -Path $triggerFile
        Remove-Item -Path $triggerFile -Force
        if ($content -eq "Deleted") {
            Write-Host "Card removed — locking workstation"
            rundll32.exe user32.dll,LockWorkStation
        } elseif ($content -eq "Inserted") {
            Write-Host "Card inserted"
        }
    }
    Start-Sleep -Seconds 1
}
```

## Adapting to Other Readers

The WMI filter matches on `DeviceID LIKE 'SCFILTER%IDENTIVE%'`. If you use a different reader, find your device's actual ID while the card is inserted:

```powershell
Get-WmiObject Win32_PnPEntity |
    Where-Object { $_.DeviceID -like 'SCFILTER*' } |
    Select-Object Description, DeviceID
```

Then update the two `LIKE` patterns in the script to match your reader's `DeviceID`.

## Troubleshooting

| Symptom                                      | Cause                                              | Fix                                                                                       |
| -------------------------------------------- | -------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| Script starts but nothing happens on removal | WMI filter does not match your reader              | Run the device ID query above and update the `LIKE` pattern                               |
| `Access Denied` on startup                   | Not running as Administrator                       | Run PowerShell as Administrator                                                           |
| Lock fires but screen immediately unlocks    | Windows Hello / PIN re-authenticates automatically | Disable Windows Hello for the session or use Group Policy to require credential on unlock |
| Trigger file left behind after a crash       | Stale file from previous run                       | Delete `%TEMP%\fido2trigger.txt` manually and restart the script                          |

## What Was Tried First (and Why It Didn't Work)

**Approach 1 — WMI USB plug/unplug with `Description LIKE '%FIDO%'`**
The FIDO2 card does not appear as a USB device with "FIDO" in the description. It is presented through the smart card reader driver stack, so no USB insertion/removal event fires when the card is removed.

**Approach 2 — PC/SC `SCardGetStatusChange`**
The reader enumerates via `SWD\SCDEVICEENUM` (a virtual software device path) rather than a direct USB path. This caused `SCardGetStatusChange` to return `0x80100013` (`SCARD_E_READER_UNAVAILABLE`) even with `SCardSvr` running.

**Approach 3 (this script) — WMI `SCFILTER` device deletion**
The inserted card appears as `SCFILTER\CID_...\...IDENTIVE...` in `Win32_PnPEntity`. This device is created and destroyed by the smart card filter driver on card insert/remove, independently of the USB reader staying connected. Monitoring this works reliably.
