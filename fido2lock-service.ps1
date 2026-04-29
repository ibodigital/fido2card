# fido2lock-service.ps1
# Runs as SYSTEM at machine startup.
# Monitors smart card readers (Identive SCR33xx, HID Omnikey 5022) for card
# removal and locks the active user session via tsdiscon.exe.
# Honours a pause flag written by the tray app.

$basePath    = "C:\ProgramData\fido2lock"
$triggerFile = Join-Path $basePath "trigger.txt"
$logFile     = Join-Path $basePath "service.log"
$pauseFile   = Join-Path $basePath "pause-until.txt"

if (-not (Test-Path $basePath)) {
    New-Item -ItemType Directory -Path $basePath | Out-Null
    # Allow Users to read/write pause file (tray app needs to write it)
    $acl = Get-Acl $basePath
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        "BUILTIN\Users", "Modify", "ContainerInherit,ObjectInherit", "None", "Allow")
    $acl.AddAccessRule($rule)
    Set-Acl -Path $basePath -AclObject $acl
}

function Write-Log($msg) {
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $logFile -Value "[$timestamp] $msg"
}

function Test-LockPaused {
    if (-not (Test-Path $pauseFile)) { return $false }
    try {
        $pauseUntil = [DateTime]::Parse((Get-Content $pauseFile -Raw).Trim())
        if ((Get-Date) -lt $pauseUntil) {
            return $true
        } else {
            # Pause expired — clean up the file
            Remove-Item $pauseFile -Force -ErrorAction SilentlyContinue
            Write-Log "Pause expired — auto-cleared"
            return $false
        }
    } catch {
        Write-Log "Could not parse pause file — ignoring: $_"
        return $false
    }
}

function Lock-ActiveSession {
    try {
        $explorerProcesses = Get-WmiObject Win32_Process -Filter "Name='explorer.exe'"

        if (-not $explorerProcesses) {
            Write-Log "No explorer.exe found — no user appears to be logged in"
            return
        }

        foreach ($proc in $explorerProcesses) {
            $sessionId = $proc.SessionId
            Write-Log "Disconnecting session $sessionId"
            $null = & tsdiscon.exe $sessionId 2>&1
        }
    } catch {
        Write-Log "Lock-ActiveSession error: $_"
    }
}

function Get-CardPresent {
    Get-WmiObject Win32_PnPEntity | Where-Object {
        $_.DeviceID -like "SCFILTER*IDENTIVE*" -or
        $_.DeviceID -like "SCFILTER*OMNIKEY*"
    }
}

# Startup state
$cardPresent = Get-CardPresent
$armed = [bool]$cardPresent

if ($armed) {
    Write-Log "Startup: card already present — removal watch armed"
} else {
    Write-Log "Startup: no card present — waiting for insertion before arming"
}

$insertQuery = "SELECT * FROM __InstanceCreationEvent WITHIN 2 " +
               "WHERE TargetInstance ISA 'Win32_PnPEntity' " +
               "AND (TargetInstance.DeviceID LIKE 'SCFILTER%IDENTIVE%' " +
               "OR TargetInstance.DeviceID LIKE 'SCFILTER%OMNIKEY%')"

$deleteQuery  = "SELECT * FROM __InstanceDeletionEvent WITHIN 2 " +
               "WHERE TargetInstance ISA 'Win32_PnPEntity' " +
               "AND (TargetInstance.DeviceID LIKE 'SCFILTER%IDENTIVE%' " +
               "OR TargetInstance.DeviceID LIKE 'SCFILTER%OMNIKEY%')"

$insertedAction = [scriptblock]::Create("Set-Content -Path '$triggerFile' -Value 'Inserted'")
$deletedAction  = [scriptblock]::Create("Set-Content -Path '$triggerFile' -Value 'Deleted'")

Unregister-Event -SourceIdentifier "CardInserted" -ErrorAction SilentlyContinue
Unregister-Event -SourceIdentifier "CardRemoved"  -ErrorAction SilentlyContinue

Register-WmiEvent -Query $insertQuery -Action $insertedAction -SourceIdentifier "CardInserted" | Out-Null
Register-WmiEvent -Query $deleteQuery  -Action $deletedAction  -SourceIdentifier "CardRemoved"  | Out-Null

Write-Log "Monitoring started as SYSTEM (Identive SCR33xx + HID Omnikey 5022)"

while ($true) {
    if (Test-Path $triggerFile) {
        $content = Get-Content -Path $triggerFile
        Remove-Item -Path $triggerFile -Force

        if ($content -eq "Inserted") {
            $armed = $true
            Write-Log "Card inserted — removal watch armed"
        } elseif ($content -eq "Deleted" -and $armed) {
            if (Test-LockPaused) {
                Write-Log "Card removed but lock is PAUSED — not locking"
            } else {
                Write-Log "Card removed — locking active session"
                Lock-ActiveSession
            }
            $armed = $false
        } elseif ($content -eq "Deleted" -and -not $armed) {
            Write-Log "Card removed — not armed, ignoring"
        }
    }
    Start-Sleep -Seconds 1
}
