# 🔐 Proxmox OIDC Integration with Pocket ID

Use these settings to enable Single Sign-On (SSO) and Passkey support for Proxmox VE via Pocket ID.

---

## 1. Pocket ID Configuration
* **Create Application:** Use the OIDC template in Pocket.
* **Client Launch URL:** `https://<YOUR-IP-OR-FQDN>:8006`
* **Allowed User Groups:** > ⚠️ **Note:** If you get an "Unauthorized" error, ensure your OIDC Scopes include `groups`. If issues persist, remove restrictions here and manage access via Proxmox permissions.

## 2. Proxmox Realm Setup
Go to **Datacenter -> Permissions -> Realms -> Add -> OpenID Connect Server**.

| Field                | Configuration                |
| :------------------- | :--------------------------- |
| **Issuer URL**       | `https://pocket.hughboi.cc`  |
| **Realm**            | `pocket` (or preferred name) |
| **Client ID**        | *From Pocket*                |
| **Client Key**       | *From Pocket*                |
| **Autocreate Users** | **Checked** ✅                |
| **Username Claim**   | `username`                   |
| **Scopes**           | `openid email profile`       |
|                      |                              |

## 3. The Provisioning Process
Because Proxmox cannot "pre-sync" users from Pocket, you must follow this two-step process to establish the account and permissions:

### Step A: The Initial Handshake (User Creation)
1. Logout of Proxmox.
2. On the login screen, change the **Realm** to `pocket`.
3. Sign in using your Passkey/Pocket credentials.
4. **Expected Result:** You will log in but see "No Permission" or an empty dashboard. This is normal; Proxmox has now successfully created the user entry in its database.

### Step B: Granting Permissions
1. Sign out and sign back in using the **root@pam** (local admin) account.
2. Navigate to **Datacenter -> Permissions**.
3. Click **Add -> User Permission**.
4. Set **Path** to `/` (or specific resource).
5. Select the newly created user (e.g., `hughboi@pocket`).
6. Set **Role** to `Administrator`.

---

**Now, you can log in exclusively through the Pocket realm with full access.**