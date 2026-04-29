# uninstall.ps1
# Removes the FIDO2 Lock service and tray app entirely.
# Run as Administrator on the target machine.

#Requires -RunAsAdministrator

param(
    [string]$InstallDir = "C:\Program Files\fido2lock",
    [switch]$KeepLogs
)

$ErrorActionPreference = "SilentlyContinue"

Write-Host "=== FIDO2 Lock Uninstall ===" -ForegroundColor Cyan

# Stop and remove scheduled tasks
Write-Host "`nRemoving scheduled tasks..." -ForegroundColor Yellow
Get-ScheduledTask | Where-Object { $_.TaskName -like "FIDO2*" } | ForEach-Object {
    Write-Host "    Removing: $($_.TaskName)"
    Stop-ScheduledTask  -TaskName $_.TaskName -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $_.TaskName -TaskPath $_.TaskPath -Confirm:$false
}

# Kill any running tray instances across all user sessions
Write-Host "`nStopping any running tray processes..." -ForegroundColor Yellow
Get-Process -Name "fido2lock-tray" -ErrorAction SilentlyContinue | Stop-Process -Force
Get-Process -Name "fido2lock-service" -ErrorAction SilentlyContinue | Stop-Process -Force

# Remove install directory
if (Test-Path $InstallDir) {
    Write-Host "`nRemoving $InstallDir..." -ForegroundColor Yellow
    Remove-Item -Path $InstallDir -Recurse -Force
}

# Remove ProgramData (unless -KeepLogs)
$dataDir = "C:\ProgramData\fido2lock"
if (Test-Path $dataDir) {
    if ($KeepLogs) {
        Write-Host "`nKeeping logs at $dataDir (use without -KeepLogs to remove)" -ForegroundColor Yellow
    } else {
        Write-Host "`nRemoving $dataDir..." -ForegroundColor Yellow
        Remove-Item -Path $dataDir -Recurse -Force
    }
}

Write-Host "`n=== Uninstall complete ===" -ForegroundColor Green
