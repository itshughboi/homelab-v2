### Initial Setup
1. Go to https://pocket.hughboi.cc/setup for initial setup

### App Connection
1. Go to **Settings** -> **Administration** -> **OIDC Clients** -> **Add OIDC Client**
2. Give it a name and put the **Client Launch URL** to be the URL of the FQDN App. Hit save
3. After saving you will be given the Client ID, Client Secret.
4. Click 'Show more details' below the Client Secret to get all of the URL's for issuer, authorization, token, logout, etc. Everything you need for OIDC will be in the more details

### Passkeys
- Upon initial setup you will be asked to setup a Passkey. You can setup either a Passkey within Bitwarden, Touch ID on Macbook, or a Yubikey.
- To add additional passkeys go to **Settings** -> **My Account** -> **Passkeys** -> **Add Passkey**

<br> <br>

### 🔐 Proxmox OIDC Integration with Pocket ID

Use these settings to enable Single Sign-On (SSO) and Passkey support for Proxmox VE via Pocket ID.

#### 1. Pocket ID Configuration
* **Create Application:** Use the OIDC template in Pocket.
* **Client Launch URL:** `https://<YOUR-IP-OR-FQDN>:8006`
* **Allowed User Groups:** > ⚠️ **Note:** If you get an "Unauthorized" error, ensure your OIDC Scopes include `groups`. If issues persist, remove restrictions here and manage access via Proxmox permissions.

#### 2. Proxmox Realm Setup
Go to **Datacenter -> Permissions -> Realms -> Add -> OpenID Connect Server**.

| Field | Configuration |
| :--- | :--- |
| **Issuer URL** | `https://pocket.hughboi.cc` |
| **Realm** | `pocket` (or preferred name) |
| **Client ID** | *From Pocket* |
| **Client Key** | *From Pocket* |
| **Autocreate Users** | **Checked** ✅ |
| **Username Claim** | `username` |
| **Scopes** | `openid email profile` |

#### 3. The Provisioning Process
Because Proxmox cannot "pre-sync" users from Pocket, you must follow this two-step process to establish the account and permissions:

#### Step A: The Initial Handshake (User Creation)
1. Logout of Proxmox.
2. On the login screen, change the **Realm** to `pocket`.
3. Sign in using your Passkey/Pocket credentials.
4. **Expected Result:** You will log in but see "No Permission" or an empty dashboard. This is normal; Proxmox has now successfully created the user entry in its database.

#### Step B: Granting Permissions
1. Sign out and sign back in using the **root@pam** (local admin) account.
2. Navigate to **Datacenter -> Permissions**.
3. Click **Add -> User Permission**.
4. Set **Path** to `/` (or specific resource).
5. Select the newly created user (e.g., `hughboi@pocket`).
6. Set **Role** to `Administrator`.

---

**Now, you can log in exclusively through the Pocket realm with full access.**


<br>

### SMTP Setup

1. Email of admin account HAS to be **notify@mailrise.xyz**. That's how it determines source destination.
2. Go to **Settings** -> **Administration** -> **Application Configuration** -> **SMTP Configuration**

| Setting | Value |
| :--- | :--- |
| **SMTP Host** | 10.10.10.10 |
| **SMTP Port** | 8025 |
| **SMTP From** | *pocket@hughboi.cc* (anything) |
| **Client ID** | *From Pocket* |
