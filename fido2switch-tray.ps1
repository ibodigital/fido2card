# fido2switch-tray.ps1
# Runs in the user's desktop session at logon.
# System tray icon for the user-switching variant: shows the currently
# recorded card UID and lets the user pause auto-disconnect.

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$basePath        = "C:\ProgramData\fido2switch"
$pauseFile       = Join-Path $basePath "pause-until.txt"
$currentCardFile = Join-Path $basePath "current-card.txt"

if (-not (Test-Path $basePath)) {
    [System.Windows.Forms.MessageBox]::Show(
        "FIDO2 Switch service is not installed. Tray app cannot start.",
        "FIDO2 Switch", "OK", "Error") | Out-Null
    exit 1
}

# --- Tray icon setup ----------------------------------------------------

$notifyIcon = New-Object System.Windows.Forms.NotifyIcon
$notifyIcon.Icon = [System.Drawing.SystemIcons]::Shield
$notifyIcon.Text = "FIDO2 Switch — active"
$notifyIcon.Visible = $true

$contextMenu = New-Object System.Windows.Forms.ContextMenuStrip

# --- Helpers ------------------------------------------------------------

function Set-Pause($minutes) {
    try {
        $until = (Get-Date).AddMinutes($minutes)
        Set-Content -Path $pauseFile -Value $until.ToString("o") -Force
        $notifyIcon.ShowBalloonTip(
            2000,
            "FIDO2 Switch paused",
            "Tapping a different card will not disconnect the session until $($until.ToString('HH:mm')).",
            [System.Windows.Forms.ToolTipIcon]::Warning)
        Update-TrayState
    } catch {
        [System.Windows.Forms.MessageBox]::Show(
            "Could not write pause file: $_",
            "FIDO2 Switch", "OK", "Error") | Out-Null
    }
}

function Clear-Pause {
    if (Test-Path $pauseFile) {
        Remove-Item $pauseFile -Force -ErrorAction SilentlyContinue
    }
    $notifyIcon.ShowBalloonTip(
        2000,
        "FIDO2 Switch active",
        "Tapping a different card will disconnect the active session.",
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

function Get-CurrentCard {
    if (-not (Test-Path $currentCardFile)) { return $null }
    try {
        $uid = (Get-Content $currentCardFile -Raw).Trim()
        if ($uid) { return $uid }
    } catch { }
    return $null
}

function Update-TrayState {
    $pauseUntil = Get-PauseStatus
    $card       = Get-CurrentCard
    $cardLabel  = if ($card) { "card $card" } else { "no card recorded" }

    if ($pauseUntil) {
        $notifyIcon.Text = "FIDO2 Switch — paused until $($pauseUntil.ToString('HH:mm')) ($cardLabel)"
        $notifyIcon.Icon = [System.Drawing.SystemIcons]::Warning
    } else {
        $notifyIcon.Text = "FIDO2 Switch — active ($cardLabel)"
        $notifyIcon.Icon = [System.Drawing.SystemIcons]::Shield
    }
    # NotifyIcon.Text is capped at 127 chars on older shells.
    if ($notifyIcon.Text.Length -gt 127) {
        $notifyIcon.Text = $notifyIcon.Text.Substring(0, 127)
    }
}

# --- Menu ---------------------------------------------------------------

$status   = $contextMenu.Items.Add("FIDO2 Switch — active")
$status.Enabled = $false
$cardItem = $contextMenu.Items.Add("Current card: —")
$cardItem.Enabled = $false
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

$contextMenu.Add_Opening({
    $pauseUntil = Get-PauseStatus
    if ($pauseUntil) {
        $status.Text = "Paused until $($pauseUntil.ToString('HH:mm'))"
    } else {
        $status.Text = "FIDO2 Switch — active"
    }
    $card = Get-CurrentCard
    if ($card) {
        $cardItem.Text = "Current card: $card"
    } else {
        $cardItem.Text = "Current card: —"
    }
})

$notifyIcon.ContextMenuStrip = $contextMenu

# --- Periodic refresh --------------------------------------------------

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 5000   # 5 seconds — current card changes are interactive
$timer.Add_Tick({ Update-TrayState })
$timer.Start()

# --- Initial state and run --------------------------------------------

Update-TrayState
[System.Windows.Forms.Application]::Run()
