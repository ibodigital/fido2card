# How to verify the GUID is present on the target machine

If you still want to confirm it's registered, run this in an Administrator PowerShell on the Windows 11 box. It lists every credential provider with its friendly name so you can see the FIDO one:

```
$base = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\Credential Providers'
Get-ChildItem $base | ForEach-Object {
$clsid = $\_.PSChildName
$name = (Get-ItemProperty "HKLM:\SOFTWARE\Classes\CLSID\$clsid" -EA SilentlyContinue).'(default)'
[PSCustomObject]@{ GUID = $clsid; Name = $name }
} | Sort-Object Name | Format-Table -AutoSize
You should see a row named "FIDO Credential Provider" with exactly the GUID already in the script. If it's there, the GUID is fine.
```

# The likely real causes

FIDO2 security-key sign-in to Windows has hard requirements beyond these registry keys. The most common reasons it silently doesn't work:

- The device must be Microsoft Entra ID (Azure AD) joined or Hybrid-joined. This is the big one. FIDO2 key sign-in to Windows is not supported for local accounts or pure on-prem AD (hybrid needs cloud Kerberos configured). Check with dsregcmd /status — look for AzureAdJoined : YES.

- The security key must be registered as a sign-in method on the user's Entra account (via https://myaccount.microsoft.com → Security info → add Security key, or Passkey). The key being plugged in isn't enough; the credential must be enrolled against that account.

- The Entra tenant must allow FIDO2 as an authentication method (Authentication methods policy → FIDO2 security key = Enabled).
  Enrollment didn't refresh — even after the script, a full restart (not just sign-out) is needed, and the key option only appears on the sign-in screen after clicking the sign-in options icon.

So the next diagnostic step isn't finding a different GUID — it's running dsregcmd /status to confirm the machine is Entra-joined and verifying the key is enrolled on the account. Want me to add a join-status / enrollment check to the script so it warns when those prerequisites are missing?
