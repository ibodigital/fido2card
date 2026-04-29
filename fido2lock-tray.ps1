# fido2lock-tray.ps1
# Runs in the user's desktop session at logon.
# Provides a system tray icon for pausing/resuming card-removal lock.

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$basePath  = "C:\ProgramData\fido2lock"
$pauseFile = Join-Path $basePath "pause-until.txt"

if (-not (Test-Path $basePath)) {
    [System.Windows.Forms.MessageBox]::Show(
        "FIDO2 Lock service is not installed. Tray app cannot start.",
        "FIDO2 Lock", "OK", "Error") | Out-Null
    exit 1
}

# --- Tray icon setup ----------------------------------------------------

$notifyIcon = New-Object System.Windows.Forms.NotifyIcon
$notifyIcon.Icon = [System.Drawing.SystemIcons]::Shield
$notifyIcon.Text = "FIDO2 Lock — active"
$notifyIcon.Visible = $true

$contextMenu = New-Object System.Windows.Forms.ContextMenuStrip

# --- Helpers ------------------------------------------------------------

function Set-Pause($minutes) {
    try {
        $until = (Get-Date).AddMinutes($minutes)
        Set-Content -Path $pauseFile -Value $until.ToString("o") -Force
        $notifyIcon.ShowBalloonTip(
            2000,
            "FIDO2 Lock paused",
            "Card removal will not lock the workstation until $($until.ToString('HH:mm')).",
            [System.Windows.Forms.ToolTipIcon]::Warning)
        Update-TrayState
    } catch {
        [System.Windows.Forms.MessageBox]::Show(
            "Could not write pause file: $_",
            "FIDO2 Lock", "OK", "Error") | Out-Null
    }
}

function Clear-Pause {
    if (Test-Path $pauseFile) {
        Remove-Item $pauseFile -Force -ErrorAction SilentlyContinue
    }
    $notifyIcon.ShowBalloonTip(
        2000,
        "FIDO2 Lock active",
        "Card removal will lock the workstation.",
        [System.Windows.Forms.ToolTipIcon]::Info)
    Update-TrayState
}

function Get-PauseStatus {
    if (-not (Test-Path $pauseFile)) { return $null }
    try {
        $pauseUntil = [DateTime]::Parse((Get-Content $pauseFile -Raw).Trim())
        if ((Get-Date) -lt $pauseUntil) {
            return $pauseUntil
        }
    } catch { }
    return $null
}

function Update-TrayState {
    $pauseUntil = Get-PauseStatus
    if ($pauseUntil) {
        $notifyIcon.Text = "FIDO2 Lock — paused until $($pauseUntil.ToString('HH:mm'))"
        $notifyIcon.Icon = [System.Drawing.SystemIcons]::Warning
    } else {
        $notifyIcon.Text = "FIDO2 Lock — active"
        $notifyIcon.Icon = [System.Drawing.SystemIcons]::Shield
    }
}

# --- Menu ---------------------------------------------------------------

$status  = $contextMenu.Items.Add("FIDO2 Lock — active")
$status.Enabled = $false
$contextMenu.Items.Add("-") | Out-Null

$pause5  = $contextMenu.Items.Add("Pause 5 minutes")
$pause15 = $contextMenu.Items.Add("Pause 15 minutes")
$pause60 = $contextMenu.Items.Add("Pause 1 hour")
$contextMenu.Items.Add("-") | Out-Null

$resume  = $contextMenu.Items.Add("Resume now")
$contextMenu.Items.Add("-") | Out-Null

$exit    = $contextMenu.Items.Add("Exit tray")

$pause5.Add_Click({  Set-Pause 5 })
$pause15.Add_Click({ Set-Pause 15 })
$pause60.Add_Click({ Set-Pause 60 })
$resume.Add_Click({  Clear-Pause })
$exit.Add_Click({
    $notifyIcon.Visible = $false
    [System.Windows.Forms.Application]::Exit()
})

# Update menu status text on open
$contextMenu.Add_Opening({
    $pauseUntil = Get-PauseStatus
    if ($pauseUntil) {
        $status.Text = "Paused until $($pauseUntil.ToString('HH:mm'))"
    } else {
        $status.Text = "FIDO2 Lock — active"
    }
})

$notifyIcon.ContextMenuStrip = $contextMenu

# --- Periodic refresh (auto-clear expired pause from tooltip) ----------

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 30000   # 30 seconds
$timer.Add_Tick({ Update-TrayState })
$timer.Start()

# --- Initial state and run --------------------------------------------

Update-TrayState
[System.Windows.Forms.Application]::Run()
