# Terraform + Bind9 DNS Integration

Reference: https://registry.terraform.io/providers/hashicorp/dns/latest/docs

---

## Purpose

When standing up VMs with Terraform, this integration automatically creates DNS records
for each resource — no need to SSH into the Bind9 server and edit zone files manually.
Gives you git control, declarative state, and rebuildable DNS.

> Probably not worth the setup overhead at current scale. Cool to know how to do,
> and worth implementing if Terraform VM provisioning becomes heavy.

---

## TSIG Key Authentication

TSIG (RFC 8945) authenticates dynamic DNS updates between Terraform and Bind9.

**1. Generate the key** (run inside the Bind9 container):
```sh
tsig-keygen -a hmac-sha256
```
Use at least SHA256. Do not use MD5 — considered insecure.

**2. Save the output** to `/etc/bind/named.conf.key` in the Bind9 config directory.
   Set correct permissions on this file.

**3. Include it in `named.conf`:**
```sh
include "/etc/bind/named.conf.key";
```

---

## Bind9 Dynamic Update Policy

Add an `update-policy` to allow TSIG-authenticated dynamic updates to a zone:

```sh
zone "hughboi.cc" {
    type master;
    file "/etc/bind/zones/db.hughboi.cc";
    update-policy { grant tsig-key zonesub any; };
};
```

The key name `tsig-key` must match the name defined in `named.conf.key`.

Restart the container to apply.

---

## Terraform Setup

```sh
git clone https://github.com/itshughboi/iac.git
cd /iac/terraform/bind9

terraform init
terraform plan
terraform apply
```

**Test:**
```sh
dig proxmox.hughboi.cc
```
Should resolve to 4 IPs (10.10.10.1–4) via DNS Round Robin.

---

## rndc — Merge Journal to Zone File

When Bind9 accepts dynamic updates, it writes them to a journal file (`.jnl`).
The zone file itself isn't updated until you explicitly merge. Tool: `rndc`

**Add `rndc.conf`** to Bind9 config directory:
```sh
include "/etc/bind/named.conf.key";

options {
    default-key "tsig-key";
    default-server 127.0.0.1;
    default-port 953;
}
```

**Enable in `named.conf.options`:**
```sh
controls {
    inet 127.0.0.1 port 953
    allow { 127.0.0.1; } keys { "tsig-key"; };
};
```

**Run the merge:**
```sh
docker exec -it <bind9-container> /bin/sh
rndc sync
```

**Automation:** Use Ansible to periodically run `rndc sync`. Not critical because the
journal file is persistent — it won't go away. This is just for viewability/tidiness.

---

## Security Note

The `.tf` files for Bind9 contain the TSIG key reference. Store securely — a leaked
TSIG key allows DNS spoofing against your zone.

Encrypt with SOPS before pushing to Gitea.
See [`04_Infrastructure_as_Code/03_Secrets_SOPS.md`](Secrets_SOPS.md).
