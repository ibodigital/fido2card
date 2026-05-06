# deploy-switch.ps1
# Installs/updates the FIDO2 Switch service and tray app (user-switching variant).
# Reads exes from .\bin\
# Run as Administrator on the target machine.
#
# Note: this variant is mutually exclusive with the lock-on-removal variant.
# Any existing FIDO2 Lock / FIDO2 Switch scheduled tasks are removed first.

#Requires -RunAsAdministrator

param(
    [string]$InstallDir = "C:\Program Files\fido2switch"
)

$ErrorActionPreference = "Stop"

Write-Host "=== FIDO2 Switch Deployment ===" -ForegroundColor Cyan

# --- 1. Verify required exes exist in bin folder ---
$scriptDir   = $PSScriptRoot
$binDir      = Join-Path $scriptDir "bin"
$serviceExe  = Join-Path $binDir "fido2switch-service.exe"
$trayExe     = Join-Path $binDir "fido2switch-tray.exe"

if (-not (Test-Path $binDir)) {
    throw "bin directory not found at $binDir. Run build-switch.ps1 first."
}
if (-not (Test-Path $serviceExe)) {
    throw "fido2switch-service.exe not found in $binDir. Run build-switch.ps1 first."
}
if (-not (Test-Path $trayExe)) {
    throw "fido2switch-tray.exe not found in $binDir. Run build-switch.ps1 first."
}

# --- 2. Remove any existing FIDO2 scheduled tasks (lock or switch) ---
Write-Host "`n[1/5] Removing existing FIDO2 scheduled tasks..." -ForegroundColor Yellow
Get-ScheduledTask | Where-Object { $_.TaskName -like "FIDO2*" } | ForEach-Object {
    Write-Host "    Removing: $($_.TaskName)"
    Unregister-ScheduledTask -TaskName $_.TaskName -TaskPath $_.TaskPath -Confirm:$false
}

# --- 3. Install files ---
Write-Host "`n[2/5] Installing executables to $InstallDir..." -ForegroundColor Yellow
if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
}
Copy-Item $serviceExe -Destination $InstallDir -Force
Copy-Item $trayExe    -Destination $InstallDir -Force
Write-Host "    Installed: fido2switch-service.exe, fido2switch-tray.exe"

# --- 4. Create ProgramData folder with permissions ---
# Use SID S-1-5-32-545 (BUILTIN\Users) to support all Windows locales.
Write-Host "`n[3/5] Creating C:\ProgramData\fido2switch with permissions..." -ForegroundColor Yellow
$dataDir = "C:\ProgramData\fido2switch"
if (-not (Test-Path $dataDir)) {
    New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
}
$usersSid = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-545")
$acl = Get-Acl $dataDir
$rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
    $usersSid, "Modify", "ContainerInherit,ObjectInherit", "None", "Allow")
$acl.AddAccessRule($rule)
Set-Acl -Path $dataDir -AclObject $acl
Write-Host "    Permissions set: Users (S-1-5-32-545) granted Modify"

# --- 5. Register service task (SYSTEM, AtStartup) ---
Write-Host "`n[4/5] Registering service task (runs as SYSTEM at boot)..." -ForegroundColor Yellow
$serviceAction    = New-ScheduledTaskAction -Execute (Join-Path $InstallDir "fido2switch-service.exe")
$serviceTrigger   = New-ScheduledTaskTrigger -AtStartup
$serviceSettings  = New-ScheduledTaskSettingsSet `
                        -ExecutionTimeLimit 0 `
                        -RestartCount 3 `
                        -RestartInterval (New-TimeSpan -Minutes 1) `
                        -AllowStartIfOnBatteries `
                        -DontStopIfGoingOnBatteries
$servicePrincipal = New-ScheduledTaskPrincipal `
                        -UserId "SYSTEM" `
                        -LogonType ServiceAccount `
                        -RunLevel Highest

Register-ScheduledTask `
    -TaskName "FIDO2 Switch Service" `
    -Action $serviceAction `
    -Trigger $serviceTrigger `
    -Settings $serviceSettings `
    -Principal $servicePrincipal `
    -Force | Out-Null
Write-Host "    Registered: FIDO2 Switch Service"

# --- 6. Register tray task (per user, AtLogOn) ---
Write-Host "`n[5/5] Registering tray task (runs at user logon)..." -ForegroundColor Yellow
$trayAction    = New-ScheduledTaskAction -Execute (Join-Path $InstallDir "fido2switch-tray.exe")
$trayTrigger   = New-ScheduledTaskTrigger -AtLogOn
$traySettings  = New-ScheduledTaskSettingsSet `
                    -ExecutionTimeLimit 0 `
                    -AllowStartIfOnBatteries `
                    -DontStopIfGoingOnBatteries
$trayPrincipal = New-ScheduledTaskPrincipal `
                    -GroupId "S-1-5-32-545" `
                    -RunLevel Limited

Register-ScheduledTask `
    -TaskName "FIDO2 Switch Tray" `
    -Action $trayAction `
    -Trigger $trayTrigger `
    -Settings $traySettings `
    -Principal $trayPrincipal `
    -Force | Out-Null
Write-Host "    Registered: FIDO2 Switch Tray"

# --- 7. Start service immediately ---
Write-Host "`nStarting service now..." -ForegroundColor Yellow
Start-ScheduledTask -TaskName "FIDO2 Switch Service"
Start-Sleep -Seconds 2

Write-Host "`n=== Deployment complete ===" -ForegroundColor Green
Write-Host "`nNext steps:"
Write-Host "  - Service is running. Log: C:\ProgramData\fido2switch\service.log"
Write-Host "  - Tray app will appear next time a user logs in."
Write-Host "  - To start tray now without logout: Start-ScheduledTask -TaskName 'FIDO2 Switch Tray'"
Write-Host "  - First card tap is recorded (no disconnect). Tap a different card to switch users."
Write-Host ""
