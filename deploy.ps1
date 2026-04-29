# deploy.ps1
# Installs/updates the FIDO2 Lock service and tray app.
# Reads exes from .\bin\
# Run as Administrator on the target machine.

#Requires -RunAsAdministrator

param(
    [string]$InstallDir = "C:\Program Files\fido2lock"
)

$ErrorActionPreference = "Stop"

Write-Host "=== FIDO2 Lock Deployment ===" -ForegroundColor Cyan

# --- 1. Verify required exes exist in bin folder ---
$scriptDir   = $PSScriptRoot
$binDir      = Join-Path $scriptDir "bin"
$serviceExe  = Join-Path $binDir "fido2lock-service.exe"
$trayExe     = Join-Path $binDir "fido2lock-tray.exe"

if (-not (Test-Path $binDir)) {
    throw "bin directory not found at $binDir. Run build.ps1 first."
}
if (-not (Test-Path $serviceExe)) {
    throw "fido2lock-service.exe not found in $binDir. Run build.ps1 first."
}
if (-not (Test-Path $trayExe)) {
    throw "fido2lock-tray.exe not found in $binDir. Run build.ps1 first."
}

# --- 2. Remove any existing scheduled tasks ---
Write-Host "`n[1/5] Removing existing scheduled tasks..." -ForegroundColor Yellow
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
Write-Host "    Installed: fido2lock-service.exe, fido2lock-tray.exe"

# --- 4. Create ProgramData folder with permissions ---
# Use SID S-1-5-32-545 (BUILTIN\Users) to support all Windows locales
Write-Host "`n[3/5] Creating C:\ProgramData\fido2lock with permissions..." -ForegroundColor Yellow
$dataDir = "C:\ProgramData\fido2lock"
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
$serviceAction    = New-ScheduledTaskAction -Execute (Join-Path $InstallDir "fido2lock-service.exe")
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
    -TaskName "FIDO2 Lock Service" `
    -Action $serviceAction `
    -Trigger $serviceTrigger `
    -Settings $serviceSettings `
    -Principal $servicePrincipal `
    -Force | Out-Null
Write-Host "    Registered: FIDO2 Lock Service"

# --- 6. Register tray task (per user, AtLogOn) ---
# Use SID S-1-5-32-545 (Users) to support all Windows locales
Write-Host "`n[5/5] Registering tray task (runs at user logon)..." -ForegroundColor Yellow
$trayAction    = New-ScheduledTaskAction -Execute (Join-Path $InstallDir "fido2lock-tray.exe")
$trayTrigger   = New-ScheduledTaskTrigger -AtLogOn
$traySettings  = New-ScheduledTaskSettingsSet `
                    -ExecutionTimeLimit 0 `
                    -AllowStartIfOnBatteries `
                    -DontStopIfGoingOnBatteries
$trayPrincipal = New-ScheduledTaskPrincipal `
                    -GroupId "S-1-5-32-545" `
                    -RunLevel Limited

Register-ScheduledTask `
    -TaskName "FIDO2 Lock Tray" `
    -Action $trayAction `
    -Trigger $trayTrigger `
    -Settings $traySettings `
    -Principal $trayPrincipal `
    -Force | Out-Null
Write-Host "    Registered: FIDO2 Lock Tray"

# --- 7. Start service immediately ---
Write-Host "`nStarting service now..." -ForegroundColor Yellow
Start-ScheduledTask -TaskName "FIDO2 Lock Service"
Start-Sleep -Seconds 2

Write-Host "`n=== Deployment complete ===" -ForegroundColor Green
Write-Host "`nNext steps:"
Write-Host "  - Service is running. Log: C:\ProgramData\fido2lock\service.log"
Write-Host "  - Tray app will appear next time a user logs in."
Write-Host "  - To start tray now without logout: Start-ScheduledTask -TaskName 'FIDO2 Lock Tray'"
Write-Host ""
