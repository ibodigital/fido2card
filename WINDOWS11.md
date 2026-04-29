# Windows 11 Group Policy — FIDO2 Security Key at Login Screen

This guide covers how to make the FIDO2 security key credential provider visible and usable on the Windows 11 login and lock screen, using Group Policy (GPO) and/or registry settings. It also covers how to optionally set the security key as the default or only sign-in method.

---

## Prerequisites

- Windows 11 (Windows 10 20H1 or later also supported)
- Device must be **Microsoft Entra joined** or **Microsoft Entra hybrid joined** — pure on-premises AD-only domain join is not supported for FIDO2 Windows login
- FIDO2 key already registered to the user's Microsoft 365 / Entra ID account (see `FIDO2-M365-Registration.md`)
- Updated Group Policy ADMX templates (`CredentialProviders.admx`) — included in Windows 11 by default
- Local administrator or Domain Administrator rights to apply policy

> **On-premises AD only (no Entra ID)?** FIDO2 Windows login is not supported in a pure on-premises Active Directory environment without Entra ID. In that scenario, the key can only be used for browser-based authentication, not Windows login.

---

## Part 1 — Enable Security Key Sign-In via Group Policy

This is the core setting that activates the FIDO Credential Provider on the Windows login screen.

### Using Local Group Policy Editor (single machine)

1. Press `Win + R`, type `gpedit.msc`, right-click and choose **Run as administrator**
2. Navigate to:
    ```
    Computer Configuration
    └── Administrative Templates
        └── System
            └── Logon
    ```
3. Double-click **Turn on security key sign-in**
4. Select **Enabled**
5. Click **OK**
6. Restart the machine

### Using Domain Group Policy (Active Directory)

1. Open **Group Policy Management Console** (`gpmc.msc`) on a domain controller or admin workstation
2. Create a new GPO or edit an existing one targeted at the relevant OU
3. Navigate to the same path:
    ```
    Computer Configuration
    └── Policies
        └── Administrative Templates
            └── System
                └── Logon
    ```
4. Enable **Turn on security key sign-in**
5. Link the GPO to the target OU
6. Run `gpupdate /force` on the target machine, or wait for the next policy refresh cycle
7. Restart the machine

### Using Registry (if GPO path is unavailable)

Run the following in an elevated PowerShell or Command Prompt:

```powershell
REG ADD "HKLM\SOFTWARE\policies\Microsoft\FIDO" /v EnableFIDODeviceLogon /t REG_DWORD /d 1 /f
```

To verify it was applied:

```powershell
Get-ItemProperty "HKLM:\SOFTWARE\policies\Microsoft\FIDO"
```

---

## Part 2 — Verify the Credential Provider is Registered

After enabling the policy and restarting, confirm the FIDO credential provider is present in the registry:

```powershell
Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\Credential Providers" |
    Get-ItemProperty |
    Select-Object PSChildName, '(default)' |
    Sort-Object '(default)'
```

Look for this entry:

| GUID                                     | Provider                                |
| ---------------------------------------- | --------------------------------------- |
| `{F8A1793B-7873-4046-B2A7-1F318747F427}` | FIDO Credential Provider (Security Key) |

If it is missing, the ADMX policy template may not have applied correctly — see [Troubleshooting](#troubleshooting).

---

## Part 3 — Set Security Key as the Default Sign-In Option (Optional)

This makes the security key tile appear first on the login screen without the user having to click "Sign-in options".

### Via Group Policy

Navigate to:

```
Computer Configuration
└── Administrative Templates
    └── System
        └── Logon
            └── Assign a default credential provider
```

Set to **Enabled** and enter the FIDO credential provider GUID:

```
{F8A1793B-7873-4046-B2A7-1F318747F427}
```

### Via Registry

```powershell
REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\System" `
    /v DefaultCredentialProvider `
    /t REG_SZ `
    /d "{F8A1793B-7873-4046-B2A7-1F318747F427}" /f
```

---

## Part 4 — Remove Other Sign-In Options (Optional)

To force users to sign in only with the security key — for example on shared workstations or kiosk devices — you can exclude other credential providers.

> ⚠️ **Warning:** Disabling the password credential provider also breaks RDP, remote support tools, and Run As. Only do this on dedicated devices where those scenarios are not needed.

### Well-known Credential Provider GUIDs

| GUID                                     | Provider                    |
| ---------------------------------------- | --------------------------- |
| `{F8A1793B-7873-4046-B2A7-1F318747F427}` | FIDO2 Security Key          |
| `{60b78e88-ead8-445c-9cfd-0b87f74ea6cd}` | Password                    |
| `{8AF662BF-65A0-4D0A-A540-A338A999D36F}` | Fingerprint (Windows Hello) |
| `{8fd7e19c-3bf7-489b-a72c-846ab3678c96}` | Smartcard                   |
| `{94596c7e-3744-41ce-893e-bbf09122f76a}` | Smartcard PIN               |
| `{BEC09223-B018-416D-A0AC-523971B639F5}` | PIN (Windows Hello)         |
| `{cb82ea12-9f71-446d-89e1-8d0924e1256e}` | Picture Password            |

### Exclude a provider via Group Policy

Navigate to:

```
Computer Configuration
└── Administrative Templates
    └── System
        └── Logon
            └── Exclude credential providers
```

Set to **Enabled** and enter the GUIDs to exclude, comma-separated. For example, to remove password and smartcard:

```
{60b78e88-ead8-445c-9cfd-0b87f74ea6cd},{8fd7e19c-3bf7-489b-a72c-846ab3678c96}
```

### Exclude via Registry

```powershell
# Example: disable password provider
$guid = "{60b78e88-ead8-445c-9cfd-0b87f74ea6cd}"
$path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\Credential Providers\$guid"
New-ItemProperty -Path $path -Name "Disabled" -Value 1 -PropertyType DWORD -Force
```

---

## Part 5 — What the User Sees After Configuration

Once the policy is applied and the machine is restarted:

1. At the Windows login or lock screen, a **key icon** appears alongside other sign-in options
2. The user clicks **Sign-in options** and selects the key icon (or it appears automatically if set as default)
3. A prompt appears: **"Insert your security key"**
4. The user inserts the card into the Identive SCR33xx reader
5. A PIN prompt appears — the user enters the key PIN
6. Windows authenticates against Entra ID and the session opens

If the card is already inserted before the lock screen appears, Windows will prompt for PIN immediately.

---

## Troubleshooting

| Problem                                                       | Cause                                                         | Fix                                                                                                       |
| ------------------------------------------------------------- | ------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| "Turn on security key sign-in" setting not visible in gpedit  | ADMX template too old                                         | Ensure Windows is updated to 20H1 or later; on domain, update Central Store with latest ADMX files        |
| Security key option not visible on login screen after restart | Policy not applied or FIDO credential provider not registered | Run `gpresult /r` to verify policy applied; check registry path in Part 2                                 |
| Device not Entra joined                                       | Machine is pure on-premises AD only                           | FIDO2 Windows login requires Entra ID (joined or hybrid joined)                                           |
| PIN prompt does not appear after inserting card               | Smart Card service not running                                | Run `Start-Service SCardSvr` as Administrator                                                             |
| Login screen shows key option but authentication fails        | Key not registered to this user's Entra ID account            | Verify registration at `aka.ms/mysecurityinfo`                                                            |
| Windows Hello PIN keeps intercepting instead of key           | Windows Hello for Business is the default provider            | On the login screen, click **Sign-in options → Security Key**; or set FIDO as default provider per Part 3 |
| RDP stopped working after excluding password provider         | Password credential provider was disabled                     | Re-enable `{60b78e88-ead8-445c-9cfd-0b87f74ea6cd}` or do not exclude it on machines used for RDP          |
| `gpupdate /force` shows no errors but setting is not applied  | GPO scope excludes the machine or user                        | Check GPO WMI filters, security filtering, and OU targeting in GPMC                                       |

---

## Summary of Registry Keys

For reference, all relevant registry keys in one place:

```powershell
# Enable FIDO device logon
REG ADD "HKLM\SOFTWARE\policies\Microsoft\FIDO" /v EnableFIDODeviceLogon /t REG_DWORD /d 1 /f

# Set FIDO as default credential provider
REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\System" /v DefaultCredentialProvider /t REG_SZ /d "{F8A1793B-7873-4046-B2A7-1F318747F427}" /f

# Verify both
Get-ItemProperty "HKLM:\SOFTWARE\policies\Microsoft\FIDO"
Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" | Select-Object DefaultCredentialProvider
```
