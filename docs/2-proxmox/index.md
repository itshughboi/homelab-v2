# 2. Proxmox

The virtualization platform — bringing nodes into existence and operating the hypervisor.

| Area | Contents |
| --- | --- |
| [provisioning/](provisioning/README.md) | Node install (Ventoy), VM template (Packer), Terraform, cluster formation |
| [pve/](pve/README.md) | Host operations: virtual interfaces, Corosync, GPU passthrough, disk expansion, best practices |

Nodes install via [Ventoy USB](provisioning/Ventoy.md) (netboot/PXE was
[abandoned](../1-networking/Alternative%20Methods/Netboot/README.md)). After install, Ansible
configures bridges/VLANs and joins the cluster; Terraform then provisions the VMs.
