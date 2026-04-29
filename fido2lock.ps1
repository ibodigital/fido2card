$triggerFile = Join-Path $env:TEMP "fido2trigger.txt"

# Check if card is already present at startup
$cardPresent = Get-WmiObject Win32_PnPEntity |
    Where-Object { $_.DeviceID -like "SCFILTER*IDENTIVE*" }

if (-not $cardPresent) {
    Write-Host "No card present at startup — waiting for insertion before arming removal watch."
}

# Track whether we should lock on removal
$armed = [bool]$cardPresent

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

Write-Host "Monitoring started. Armed: $armed"

while ($true) {
    if (Test-Path $triggerFile) {
        $content = Get-Content -Path $triggerFile
        Remove-Item -Path $triggerFile -Force

        if ($content -eq "Inserted") {
            $armed = $true
            Write-Host "Card inserted — removal watch armed"
        } elseif ($content -eq "Deleted" -and $armed) {
            Write-Host "Card removed — locking workstation"
            rundll32.exe user32.dll,LockWorkStation
            $armed = $false  # disarm until card is inserted again
        } elseif ($content -eq "Deleted" -and -not $armed) {
            Write-Host "Card removed but not armed — ignoring"
        }
    }
    Start-Sleep -Seconds 1
}