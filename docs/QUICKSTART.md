# Quickstart

Assumes networking (UniFi VLANs, firewall) is already up.

---

## 1. Laptop Prerequisites

```sh
ssh-keygen -t ed25519 -C "homelab-mac" -f ~/.ssh/homelab-mac_id_ed25519
```

```sh
git clone https://github.com/itshughboi/homelab-v2.git
cd homelab-v2
```

---

## 2. Prepare the Install USB

Per node (TOMLs live in `bootstrap/netbootxyz/assets/proxmox/pve-srv-X.toml` —
copy an existing one, update `hostname`, `cidr`, and `disk`):

```sh
# On pve-srv-1 (has the amd64 tooling)
proxmox-auto-install-assistant prepare-iso proxmox-ve_9.1-1.iso \
  --fetch-from iso --answer-file pve-srv-X.toml --output pve-srv-X-auto.iso
```

Copy the prepared ISO(s) onto a Ventoy USB. See
[provisioning/Ventoy.md](2-proxmox/provisioning/Ventoy.md) for the full method.

---

## 3. Boot the Node

1. Plug into its **permanent trunk port** on the USW Flex Mini (VLAN 10) — no VLAN 99, no cable move
2. Boot from the Ventoy USB → pick `pve-srv-X-auto.iso` → **Automated Installation**
3. Wait for login prompt at `https://10.10.10.X:8006`
4. Verify: `ssh root@10.10.10.X`

Repeat for each node. Then form the cluster:

```sh
# On pve-srv-1
pvecm create homelab

# On pve-srv-2, 3, 4
pvecm add 10.10.10.1

# Verify
pvecm status
```

---

## 4. Build VM Template

```sh
cd ansible/playbooks/proxmox/vm-template-refresh/
ansible-playbook main.yaml -i inventory.yaml
```

Template 9999 must exist on pve-srv-1 before Terraform runs.

---

## 5. Provision VMs with Terraform

```sh
cd terraform/proxmox/
cp terraform.tfvars.example terraform.tfvars
# Fill in: proxmox_api_url, proxmox_api_token, ssh_public_key
terraform init
terraform apply
```

---

## 6. Bootstrap Athena

```sh
cd ansible/playbooks/ubuntu/bootstrap-athena/
ansible-playbook main.yaml -i inventory.yaml
```

Athena (`10.10.10.8`) runs Traefik, Gitea, Semaphore, Bind9. All remaining Ansible runs from Semaphore after this.

---

## 7. k3s

From Semaphore, run the `kubernetes/k3s/new` playbook.

```sh
# Verify from any node or your Mac
kubectl get nodes
```

---

## Done

| Service | URL |
| --- | --- |
| Proxmox | `https://10.10.10.1:8006` |
| Athena / Traefik | `https://athena.hughboi.cc` |
| Semaphore | `https://semaphore.hughboi.cc` |
| UniFi | `https://10.10.10.10:8443` |
| k3s dashboard | via kubectl or Traefik ingress |
