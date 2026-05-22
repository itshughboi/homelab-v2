# BIND9 Terraform

Manages DNS A records in a self-hosted BIND9 instance via the [hashicorp/dns](https://registry.terraform.io/providers/hashicorp/dns/latest/docs) provider, which uses RFC 2136 dynamic DNS updates authenticated with a TSIG key.

> **Status:** Reference/optional. At homelab scale, managing a handful of DNS records in Terraform has marginal benefit over editing zone files directly. The main value is if you're provisioning many hosts with Terraform and want DNS records to appear automatically. Currently only the `proxmox` round-robin A record is defined here.

---

## What it manages

| Record | Type | Value | Purpose |
|--------|------|-------|---------|
| `proxmox.hughboi.cc` | A (round-robin) | 10.10.10.1–4 | Single entry point for the Proxmox cluster UI |

Per-node A records (`pve-srv-1.hughboi.cc` etc.) are managed as UniFi DNS overrides in `terraform/unifi/essentials/dns-records.tf`.

---

## Prerequisites

### 1. Generate a TSIG key on the BIND9 host

```bash
# If running BIND9 in Docker, exec into the container:
docker exec -it bind9 /bin/sh

tsig-keygen -a hmac-sha256 tsig-key
```

Output looks like:
```
key "tsig-key" {
    algorithm hmac-sha256;
    secret "base64encodedkeyhere==";
};
```

### 2. Configure BIND9 to accept dynamic updates

In your BIND9 config, add the key and allow zone updates:

```
# named.conf.key (included by named.conf)
key "tsig-key" {
    algorithm hmac-sha256;
    secret "base64encodedkeyhere==";
};

# Zone definition (in named.conf or named.conf.local)
zone "hughboi.cc" {
    type master;
    file "/etc/bind/zones/db.hughboi.cc";
    update-policy { grant tsig-key zonesub any; };
};
```

Restart BIND9 to apply.

### 3. Configure `credentials.tfvars`

```bash
cp credentials.tfvars.example credentials.tfvars
$EDITOR credentials.tfvars    # fill in server IP and TSIG key secret
```

`credentials.tfvars` is in `.gitignore` — never commit it.

---

## Usage

```bash
cd terraform/bind9

terraform init
terraform plan
terraform apply -var-file=credentials.tfvars

# Verify:
dig proxmox.hughboi.cc @10.10.10.X    # should return all 4 Proxmox IPs
```

---

## Merge journal to zone file

BIND9 writes dynamic updates to a journal file (`.jnl`). To merge it into the zone file (for readability):

```bash
docker exec -it bind9 rndc sync
```

Or set up the `rndc` control socket in `named.conf.options`:

```
controls {
    inet 127.0.0.1 port 953
    allow { 127.0.0.1; } keys { "tsig-key"; };
};
```

---

## Extending

To add a new record when provisioning a host with Terraform, add to `dns.tf`:

```hcl
resource "dns_a_record_set" "my-host" {
  zone      = "hughboi.cc."
  name      = "my-host"
  addresses = ["10.10.10.X"]
  ttl       = 300
}
```

Run `terraform apply -var-file=credentials.tfvars` and the record appears immediately without restarting BIND9.
