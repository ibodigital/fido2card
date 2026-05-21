# fido2switch-service.ps1
# Runs as SYSTEM at machine startup.
# Watches smart card readers (Identive SCR33xx, HID Omnikey 5022) for card
# *insertion*. Reads the card's UID via PC/SC (FF CA 00 00 00). When the UID
# differs from the one recorded for the current session, disconnects the
# active session via tsdiscon.exe so the new user can log in.
# Card removal does nothing in this variant.

$basePath        = "C:\ProgramData\fido2switch"
$triggerFile     = Join-Path $basePath "trigger.txt"
$logFile         = Join-Path $basePath "service.log"
$pauseFile       = Join-Path $basePath "pause-until.txt"
$currentCardFile = Join-Path $basePath "current-card.txt"

if (-not (Test-Path $basePath)) {
    New-Item -ItemType Directory -Path $basePath | Out-Null
    # Allow Users group to read/write pause + current-card files.
    # SID S-1-5-32-545 works on every Windows locale.
    $usersSid = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-545")
    $acl = Get-Acl $basePath
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $usersSid, "Modify", "ContainerInherit,ObjectInherit", "None", "Allow")
    $acl.AddAccessRule($rule)
    Set-Acl -Path $basePath -AclObject $acl
}

function Write-Log($msg) {
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $logFile -Value "[$timestamp] $msg"
}

# --- PC/SC P/Invoke for reading card UID ----------------------------------
# SCardConnect + SCardTransmit "FF CA 00 00 00" returns the contactless card
# serial / UID for MIFARE-style and most PIV-over-NFC cards. Contact-mode
# PIV cards may answer 6A 81 (not supported); in that case the UID can't be
# read and we log + skip rather than disconnecting.

$pcscSource = @'
using System;
using System.Runtime.InteropServices;

public static class WinSCard {
    [DllImport("winscard.dll")]
    public static extern int SCardEstablishContext(uint dwScope, IntPtr r1, IntPtr r2, out IntPtr ctx);

    [DllImport("winscard.dll")]
    public static extern int SCardReleaseContext(IntPtr ctx);

    [DllImport("winscard.dll", CharSet = CharSet.Unicode, EntryPoint = "SCardListReadersW")]
    public static extern int SCardListReaders(IntPtr ctx, IntPtr groups, [Out] char[] readers, ref int len);

    [DllImport("winscard.dll", CharSet = CharSet.Unicode, EntryPoint = "SCardConnectW")]
    public static extern int SCardConnect(IntPtr ctx, string reader, uint shareMode, uint protos, out IntPtr card, out uint activeProto);

    [DllImport("winscard.dll")]
    public static extern int SCardDisconnect(IntPtr card, uint disposition);

    [DllImport("winscard.dll")]
    public static extern int SCardTransmit(IntPtr card, IntPtr sendPci, byte[] sendBuf, int sendLen, IntPtr recvPci, byte[] recvBuf, ref int recvLen);

    [DllImport("kernel32.dll", CharSet = CharSet.Ansi)]
    public static extern IntPtr GetModuleHandle(string name);

    [DllImport("kernel32.dll", CharSet = CharSet.Ansi)]
    public static extern IntPtr LoadLibrary(string name);

    [DllImport("kernel32.dll", CharSet = CharSet.Ansi)]
    public static extern IntPtr GetProcAddress(IntPtr module, string proc);

    public static IntPtr GetPci(uint protocol) {
        IntPtr h = GetModuleHandle("winscard.dll");
        if (h == IntPtr.Zero) { h = LoadLibrary("winscard.dll"); }
        // SCARD_PROTOCOL_T0 = 1, SCARD_PROTOCOL_T1 = 2
        string symbol = (protocol == 1) ? "g_rgSCardT0Pci" : "g_rgSCardT1Pci";
        return GetProcAddress(h, symbol);
    }
}
'@

if (-not ('WinSCard' -as [type])) {
    try {
        Add-Type -TypeDefinition $pcscSource -Language CSharp -ErrorAction Stop
    } catch {
        Write-Log "FATAL: failed to compile PC/SC interop: $_"
        throw
    }
}

function Get-CardUid {
    [IntPtr]$ctx = [IntPtr]::Zero
    # SCARD_SCOPE_SYSTEM = 2
    $r = [WinSCard]::SCardEstablishContext(2, [IntPtr]::Zero, [IntPtr]::Zero, [ref]$ctx)
    if ($r -ne 0) {
        Write-Log ("SCardEstablishContext failed: 0x{0:X8}" -f $r)
        return $null
    }
    try {
        # Allocate a generous buffer up front rather than the two-call sizing
        # dance — far simpler from PowerShell.
        [int]$len = 4096
        $buf = New-Object char[] $len
        $r = [WinSCard]::SCardListReaders($ctx, [IntPtr]::Zero, $buf, [ref]$len)
        if ($r -ne 0) {
            Write-Log ("SCardListReaders failed: 0x{0:X8}" -f $r)
            return $null
        }
        # Result is a multi-string (double-NUL terminated).
        $allReaders = (-join $buf[0..($len-1)]).Split([char]0) | Where-Object { $_ }
        $target = $allReaders | Where-Object { $_ -match 'IDENTIVE|OMNIKEY|SCR33|5022' } | Select-Object -First 1
        if (-not $target) { $target = $allReaders | Select-Object -First 1 }
        if (-not $target) {
            Write-Log "No PC/SC readers enumerated"
            return $null
        }

        # Insertion event can fire a beat before the driver is ready to
        # accept SCardConnect — retry briefly.
        [IntPtr]$card = [IntPtr]::Zero
        [uint32]$proto = 0
        $connected = $false
        for ($i = 0; $i -lt 15; $i++) {
            # SCARD_SHARE_SHARED = 2, SCARD_PROTOCOL_T0|T1 = 3
            $r = [WinSCard]::SCardConnect($ctx, $target, 2, 3, [ref]$card, [ref]$proto)
            if ($r -eq 0) { $connected = $true; break }
            Start-Sleep -Milliseconds 200
        }
        if (-not $connected) {
            Write-Log ("SCardConnect to '{0}' failed: 0x{1:X8}" -f $target, $r)
            return $null
        }
        try {
            $apdu = [byte[]](0xFF, 0xCA, 0x00, 0x00, 0x00)
            $recv = New-Object byte[] 258
            [int]$recvLen = $recv.Length
            $pci = [WinSCard]::GetPci($proto)
            $r = [WinSCard]::SCardTransmit($card, $pci, $apdu, $apdu.Length, [IntPtr]::Zero, $recv, [ref]$recvLen)
            if ($r -ne 0) {
                Write-Log ("SCardTransmit failed: 0x{0:X8}" -f $r)
                return $null
            }
            if ($recvLen -lt 2) { return $null }
            $sw1 = $recv[$recvLen - 2]
            $sw2 = $recv[$recvLen - 1]
            if ($sw1 -ne 0x90 -or $sw2 -ne 0x00) {
                Write-Log ("Card returned non-success status: {0:X2}{1:X2} (FF CA may be unsupported on contact PIV cards)" -f $sw1, $sw2)
                return $null
            }
            $uidLen = $recvLen - 2
            if ($uidLen -le 0) { return $null }
            $hex = New-Object System.Text.StringBuilder
            for ($j = 0; $j -lt $uidLen; $j++) {
                [void]$hex.AppendFormat("{0:X2}", $recv[$j])
            }
            return $hex.ToString()
        } finally {
            # SCARD_LEAVE_CARD = 0 (don't reset the card on disconnect)
            [WinSCard]::SCardDisconnect($card, 0) | Out-Null
        }
    } finally {
        [WinSCard]::SCardReleaseContext($ctx) | Out-Null
    }
}

function Test-SwitchPaused {
    if (-not (Test-Path $pauseFile)) { return $false }
    try {
        $pauseUntil = [DateTime]::Parse((Get-Content $pauseFile -Raw).Trim())
        if ((Get-Date) -lt $pauseUntil) {
            return $true
        } else {
            Remove-Item $pauseFile -Force -ErrorAction SilentlyContinue
            Write-Log "Pause expired — auto-cleared"
            return $false
        }
    } catch {
        Write-Log "Could not parse pause file — ignoring: $_"
        return $false
    }
}

function Disconnect-ActiveSession {
    try {
        $explorerProcesses = Get-CimInstance Win32_Process -Filter "Name='explorer.exe'"
        if (-not $explorerProcesses) {
            Write-Log "No explorer.exe found — no active user to disconnect"
            return
        }
        foreach ($proc in $explorerProcesses) {
            $sessionId = $proc.SessionId
            Write-Log "Disconnecting session $sessionId"
            $null = & tsdiscon.exe $sessionId 2>&1
        }
    } catch {
        Write-Log "Disconnect-ActiveSession error: $_"
    }
}

function Get-StoredUid {
    try {
        $u = (Get-Content $currentCardFile -Raw -ErrorAction Stop).Trim()
        if ($u) { return $u }
    } catch { }
    return $null
}

# --- WMI insertion event subscription -------------------------------------

$insertQuery = "SELECT * FROM __InstanceCreationEvent WITHIN 2 " +
               "WHERE TargetInstance ISA 'Win32_PnPEntity' " +
               "AND (TargetInstance.DeviceID LIKE 'SCFILTER%IDENTIVE%' " +
               "OR TargetInstance.DeviceID LIKE 'SCFILTER%OMNIKEY%')"

$insertedAction = [scriptblock]::Create("Set-Content -Path '$triggerFile' -Value 'Inserted'")

Unregister-Event -SourceIdentifier "CardInserted" -ErrorAction SilentlyContinue
Register-CimIndicationEvent -Query $insertQuery -Action $insertedAction -SourceIdentifier "CardInserted" | Out-Null

Write-Log "Switch service started as SYSTEM (Identive SCR33xx + HID Omnikey 5022)"

while ($true) {
    if (Test-Path $triggerFile) {
        $content = Get-Content -Path $triggerFile
        Remove-Item -Path $triggerFile -Force

        if ($content -eq "Inserted") {
            $newUid = Get-CardUid
            if (-not $newUid) {
                Write-Log "Insertion detected but UID could not be read — ignoring"
            } else {
                $storedUid = Get-StoredUid
                if ($storedUid -eq $newUid) {
                    Write-Log "Same card re-tapped (uid=$newUid) — no action"
                } elseif (Test-SwitchPaused) {
                    Write-Log "Different card (new=$newUid, stored=$storedUid) but switch is PAUSED — not disconnecting"
                } else {
                    if ($storedUid) {
                        Write-Log "Card change: $storedUid -> $newUid — disconnecting active session"
                        Disconnect-ActiveSession
                    } else {
                        Write-Log "First card seen (uid=$newUid) — recording; no previous session to disconnect"
                    }
                    Set-Content -Path $currentCardFile -Value $newUid -Force
                }
            }
        }
    }
    Start-Sleep -Seconds 1
}
