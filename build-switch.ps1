# build-switch.ps1
# Compiles fido2switch-service.ps1 and fido2switch-tray.ps1 to .exe using PS2EXE.
# Output goes to .\bin\
# Run on a build/admin workstation.

#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"
$scriptDir = $PSScriptRoot
$binDir    = Join-Path $scriptDir "bin"

Write-Host "=== FIDO2 Switch Build ===" -ForegroundColor Cyan

# --- Ensure bin directory exists ---
if (-not (Test-Path $binDir)) {
    New-Item -ItemType Directory -Path $binDir | Out-Null
    Write-Host "Created bin directory: $binDir" -ForegroundColor Yellow
}

# --- Ensure PS2EXE is installed ---
if (-not (Get-Module -ListAvailable -Name ps2exe)) {
    Write-Host "Installing PS2EXE module..." -ForegroundColor Yellow
    Install-Module -Name ps2exe -Scope CurrentUser -Force
}

Import-Module ps2exe

# --- Compile service exe (no console, requires admin) ---
Write-Host "`nCompiling fido2switch-service.exe..." -ForegroundColor Yellow
Invoke-PS2EXE `
    -InputFile  (Join-Path $scriptDir "fido2switch-service.ps1") `
    -OutputFile (Join-Path $binDir    "fido2switch-service.exe") `
    -NoConsole `
    -RequireAdmin `
    -Title "FIDO2 Switch Service" `
    -Description "Switches users when a different smart card is tapped"

# --- Compile tray exe (no console, runs as user) ---
Write-Host "Compiling fido2switch-tray.exe..." -ForegroundColor Yellow
Invoke-PS2EXE `
    -InputFile  (Join-Path $scriptDir "fido2switch-tray.ps1") `
    -OutputFile (Join-Path $binDir    "fido2switch-tray.exe") `
    -NoConsole `
    -Title "FIDO2 Switch Tray" `
    -Description "FIDO2 Switch pause control"

Write-Host "`n=== Build complete ===" -ForegroundColor Green
Write-Host "Output:"
Write-Host "  $binDir\fido2switch-service.exe"
Write-Host "  $binDir\fido2switch-tray.exe"
Write-Host ""
Write-Host "Next: copy this folder (including bin\) to the target machine and run deploy-switch.ps1"
