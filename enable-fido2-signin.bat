@echo off
REM ============================================================================
REM  Enable FIDO2 Security Key Sign-In on Windows 11
REM
REM  - Enables the "Turn on security key sign-in" policy
REM  - Verifies the FIDO Credential Provider is registered
REM  - Sets the FIDO2 Security Key as the default sign-in option
REM
REM  Must be run as Administrator. A restart is required after running.
REM ============================================================================

setlocal

set "FIDO_GUID={F8A1793B-7873-4046-B2A7-1F318747F427}"

REM ---- Self-elevate if not already running as Administrator ------------------
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting Administrator privileges...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

echo ============================================================================
echo  FIDO2 Security Key Sign-In - Windows 11 Configuration
echo ============================================================================
echo.

REM ---- Part 1: Enable Security Key Sign-In -----------------------------------
echo [1/3] Enabling "Turn on security key sign-in" policy...
reg add "HKLM\SOFTWARE\policies\Microsoft\FIDO" /v EnableFIDODeviceLogon /t REG_DWORD /d 1 /f >nul
if %errorlevel% neq 0 (
    echo       FAILED to set EnableFIDODeviceLogon.
    goto :error
)
echo       OK - EnableFIDODeviceLogon = 1
echo.

REM ---- Part 2: Verify the Credential Provider is Registered ------------------
echo [2/3] Verifying FIDO Credential Provider is registered...
reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\Credential Providers\%FIDO_GUID%" >nul 2>&1
if %errorlevel% neq 0 (
    echo       WARNING - FIDO Credential Provider not found in registry.
    echo       GUID: %FIDO_GUID%
    echo       The provider should appear after restart. If it does not,
    echo       ensure Windows is up to date ^(20H1 or later required^).
) else (
    echo       OK - FIDO Credential Provider is registered.
)
echo.

REM ---- Part 3: Set FIDO2 Security Key as the Default Sign-In Option ---------
echo [3/3] Setting FIDO2 Security Key as the default credential provider...
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\System" /v DefaultCredentialProvider /t REG_SZ /d "%FIDO_GUID%" /f >nul
if %errorlevel% neq 0 (
    echo       FAILED to set DefaultCredentialProvider.
    goto :error
)
echo       OK - DefaultCredentialProvider = %FIDO_GUID%
echo.

REM ---- Refresh Group Policy --------------------------------------------------
echo Refreshing Group Policy...
gpupdate /target:computer /force >nul
echo.

echo ============================================================================
echo  Done. Please RESTART the machine for changes to take effect.
echo ============================================================================
echo.
pause
exit /b 0

:error
echo.
echo ============================================================================
echo  ERROR - configuration did not complete successfully.
echo ============================================================================
echo.
pause
exit /b 1
