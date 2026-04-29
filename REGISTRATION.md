# Registering a FIDO2 Security Key with Microsoft 365

This guide covers everything needed to register a FIDO2 hardware security key as a sign-in method for a Microsoft 365 / Microsoft Entra ID account — both the admin-side setup and the end-user registration steps.

---

## Prerequisites

### Admin requirements

- Microsoft Entra ID (any edition, including Free — no extra licence required)
- Role: **Authentication Policy Administrator** or **Global Administrator**
- FIDO2 must be enabled in the tenant authentication policy (see Part 1 below)

### User requirements

- An existing Microsoft 365 account
- MFA already configured on the account (Microsoft Authenticator, phone, or a Temporary Access Pass — see note below)
- A supported browser: **Edge, Chrome, or Firefox** (Safari has limited support)
- The FIDO2 key plugged **directly into the PC** — USB hubs and docking stations can cause issues

> **No MFA yet?** An admin can issue a **Temporary Access Pass (TAP)** — a one-time time-limited code — so the user can register their FIDO2 key without first setting up the Authenticator app. See [Part 3](#part-3-optional-temporary-access-pass-for-first-time-setup) below.

---

## Part 1 — Admin: Enable FIDO2 in Microsoft Entra ID

1. Sign in to [https://entra.microsoft.com](https://entra.microsoft.com) as Authentication Policy Administrator or Global Administrator
2. Navigate to **Protection → Authentication methods → Policies**
3. Click **Passkey (FIDO2)**
4. Set **Enable** to **Yes**
5. Under **Include**, choose **All users** or select a specific group
6. On the **Configure** tab, verify the following settings:

| Setting                   | Recommended value                                        |
| ------------------------- | -------------------------------------------------------- |
| Allow self-service set up | Yes                                                      |
| Enforce attestation       | Optional (Yes = only verified key models allowed)        |
| Enforce key restrictions  | No (unless restricting to specific key models by AAGUID) |

7. Click **Save**

> If your tenant has been updated to **passkey profiles**, you will be prompted to opt in. After opting in you cannot opt out — review the settings before confirming. The existing FIDO2 policy migrates automatically to a Default passkey profile.

---

## Part 2 — User: Register the FIDO2 Key

### Step 1 — Go to Security Info

Open a browser and go to:

```
https://aka.ms/mysecurityinfo
```

Sign in with your Microsoft 365 account. If prompted for MFA, complete it now.

### Step 2 — Add a new sign-in method

1. Click **Add sign-in method**
2. From the dropdown, select **Security key**
3. Click **Add**

### Step 3 — Choose key type

Select **USB device** (or NFC if your key supports it).

Click **Next**.

### Step 4 — Windows security prompt

Windows will display a prompt to create a passkey. Click **OK** to authorise the browser to interact with the key.

### Step 5 — Insert the key and set a PIN

1. Insert your FIDO2 key into a USB port **directly on the PC** (not via a hub)
2. If this is the first time using the key, you will be prompted to **create a PIN** — enter it twice and click **OK**
3. **Touch the button** on the security key when the light flashes — this confirms physical presence

### Step 6 — Name the key

Enter a recognisable name (e.g. `Office FIDO2 Key`, `Identive Card`) so you can identify it later if you have multiple methods registered.

Click **Next**, then **Done**.

The key is now listed as a sign-in method under Security info.

---

## Part 3 (Optional) — Temporary Access Pass for First-Time Setup

If the user has no MFA method set up yet, an admin can create a TAP so they can register the FIDO2 key without the Authenticator app.

### Admin: Create a TAP

1. Go to [https://entra.microsoft.com](https://entra.microsoft.com)
2. Navigate to **Users → select the user → Authentication methods**
3. Click **Add authentication method → Temporary Access Pass**
4. Set the expiry and whether it is single-use or multi-use
5. Copy the generated pass and send it securely to the user

### User: Use the TAP

1. Go to [https://aka.ms/mysecurityinfo](https://aka.ms/mysecurityinfo)
2. Sign in with your username and enter the TAP as the password when prompted
3. Proceed with Part 2 above to register the FIDO2 key

---

## Part 4 — Sign In Using the FIDO2 Key

Once registered, the user can sign in to Microsoft 365 without a password:

1. Go to [https://microsoft365.com](https://microsoft365.com) or any M365 app
2. Enter your **email address** and click **Next**
3. On the password screen, click **Sign-in options**
4. Select **Sign in with a Windows Hello or a security key**
5. Insert the FIDO2 key when prompted
6. Enter the PIN, then **touch the key** when the light flashes
7. You are signed in

> **Windows Hello interference:** On Windows 11, the sign-in flow may default to Windows Hello for Business and keep prompting for a PIN instead of the key. If this happens, click **More choices → Security Key**, or cancel, insert the key, and restart the sign-in flow.

---

## Troubleshooting

| Problem                               | Cause                                                    | Fix                                                                                                                       |
| ------------------------------------- | -------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| "Security key" option not available   | FIDO2 not enabled in tenant or not enabled for this user | Admin must enable it in Entra ID authentication policy                                                                    |
| Prompted for MFA but no MFA set up    | Account has no second factor registered                  | Admin issues a Temporary Access Pass (TAP)                                                                                |
| Windows Hello keeps intercepting      | Windows Hello for Business is set as preferred method    | At the sign-in prompt, click **More choices → Security Key**                                                              |
| Key not detected during registration  | Using a USB hub or docking station                       | Plug directly into a USB port on the PC                                                                                   |
| `NotAllowedError` during registration | CTAP2 error or key restrictions blocking this key model  | Check Windows event log: `Microsoft-Windows-WebAuthN/Operational`; verify AAGUID is not blocked in key restriction policy |
| PIN prompt does not appear            | Key already has a PIN set                                | Enter the existing PIN; reset via key management tool if forgotten                                                        |
| Registration works but sign-in fails  | Browser doesn't support WebAuthn properly                | Use Edge or Chrome; avoid IE and older browsers                                                                           |

---

## Managing Registered Keys

Users can view, rename, and remove registered keys at any time:

```
https://aka.ms/mysecurityinfo
```

Admins can view and revoke keys per user at:

```
Entra admin center → Users → [user] → Authentication methods
```

---

## Notes

- A single FIDO2 key can be registered to **multiple Microsoft 365 accounts** — you are not limited to one account per key
- The key PIN is stored **on the key itself**, not in Entra ID — Microsoft has no way to recover a forgotten PIN; the key must be reset (which wipes all credentials stored on it)
- Key restrictions (AAGUID allow/block lists) are enforced at both registration and sign-in time — removing a previously allowed AAGUID will prevent existing registered keys of that model from signing in
