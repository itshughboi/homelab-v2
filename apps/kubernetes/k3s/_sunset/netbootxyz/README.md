# netboot.xyz — SUNSET (reference only)

> [!WARNING] Not deployed
> Netboot/PXE was abandoned — nodes install via [Ventoy USB](../../../../../docs/2-proxmox/provisioning/Ventoy.md).
> This manifest lives under `_sunset/` so the ArgoCD ApplicationSet (which globs
> `apps/kubernetes/k3s/apps/*`) does **not** discover or deploy it. Kept as reference only.

Network boot server for PXE booting operating systems over TFTP/HTTP.

## Overview

| | |
|---|---|
| **Image** | `lscr.io/linuxserver/netbootxyz:latest` |
| **Domain** | `netboot.hughboi.cc` (web UI) |
| **UI Port** | 3000 |
| **TFTP Port** | 69/UDP (LoadBalancer) |
| **Storage** | 2Gi Longhorn (`/config`) + 10Gi Longhorn (`/assets` — ISO cache) |

## Services

Two Services are deployed:

| Service | Type | Purpose |
|---------|------|---------|
| `netbootxyz-ui` | ClusterIP | Web admin UI → Traefik IngressRoute |
| `netbootxyz-tftp` | LoadBalancer | TFTP port 69/UDP → PXE clients |

## Deploy

```bash
kubectl apply -f namespace.yaml
kubectl apply -f pvc.yaml
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
kubectl apply -f ingressroute.yaml
```

After deploy, get the TFTP LoadBalancer IP:
```bash
kubectl get svc netbootxyz-tftp -n netbootxyz
```

Set your router/DHCP to point TFTP server at this IP.

## DHCP Configuration

For PXE booting, configure your router to send DHCP option 66 (TFTP server) pointing to the `netbootxyz-tftp` EXTERNAL-IP. The exact setting depends on your router/DHCP server.

For Unifi: `Settings → Networks → <network> → DHCP → TFTP Server`

## Notes

- Port 69/UDP as a LoadBalancer port requires MetalLB. Verify you have free IPs in the pool.
- The `PORT_RANGE=30000:30010` from Docker compose (used for streaming assets) is omitted — netboot.xyz serves assets over HTTP (port 80) when hosted locally, or directly from netboot.xyz CDN.
- Add `netbootxyz` to the Reflector annotation on the TLS certificate.
- `strategy: Recreate` required for ReadWriteOnce PVCs.
