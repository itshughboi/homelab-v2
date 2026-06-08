Terraform is used for two specific things where declarative state is actually useful:

- **Proxmox VM provisioning** — cloning the Cloud-Init template into named VMs
- **Bind9 DNS integration** — automatically creating DNS records when VMs are provisioned

Both of these are in the IAC repo under `/terraform/`. For the Unifi/network management
piece, Terraform is archived — see `_archive/Terraform_Unifi.md` if you need to reference
the old approach.
