$triggerFile = Join-Path $env:TEMP "fido2trigger.txt"
$logFile = Join-Path $env:TEMP "fido2lock.log"

function Write-Log($msg) {
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $logFile -Value "[$timestamp] $msg"
}

# Check if card is already present at startup
$cardPresent = Get-WmiObject Win32_PnPEntity |
    Where-Object { $_.DeviceID -like "SCFILTER*IDENTIVE*" }

$armed = [bool]$cardPresent

if ($armed) {
    Write-Log "Startup: card already present — removal watch armed"
} else {
    Write-Log "Startup: no card present — waiting for insertion before arming"
}

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

Write-Log "Monitoring started"

while ($true) {
    if (Test-Path $triggerFile) {
        $content = Get-Content -Path $triggerFile
        Remove-Item -Path $triggerFile -Force

        if ($content -eq "Inserted") {
            $armed = $true
            Write-Log "Card inserted — removal watch armed"
        } elseif ($content -eq "Deleted" -and $armed) {
            Write-Log "Card removed — locking workstation"
            rundll32.exe user32.dll,LockWorkStation
            $armed = $false
        } elseif ($content -eq "Deleted" -and -not $armed) {
            Write-Log "Card removed — not armed, ignoring"
        }
    }
    Start-Sleep -Seconds 1
}