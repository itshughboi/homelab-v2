# kube-vip

Control-plane VIP for k3s HA. Runs as a DaemonSet on control-plane nodes only and keeps the API server reachable at a single stable IP regardless of which master is active.

## Overview

| | |
|---|---|
| **Version** | `ghcr.io/kube-vip/kube-vip:v0.8.2` |
| **Mode** | ARP (L2) |
| **VIP** | `10.10.30.30` (k3s-api-vip) |
| **Port** | 6443 |
| **Scope** | Control-plane only (`svc_enable: false`) |

`svc_enable` is disabled — MetalLB handles LoadBalancer service IPs. kube-vip only manages the control-plane VIP.

## How It Works

kube-vip uses leader election (`vip_leaderelection: true`) among the three control-plane nodes. The leader broadcasts a gratuitous ARP for the VIP, so all clients (workers, kubectl, external) use the same IP. If the leader fails, another master takes over and re-broadcasts within seconds.

Lease timings (fast failover):
- `vip_leaseduration: 5s`
- `vip_renewdeadline: 3s`
- `vip_retryperiod: 1s`

## Before You Apply

Fill in the two placeholders in [daemonset.yaml](daemonset.yaml):

| Placeholder | Value |
|-------------|-------|
| `$interface` | The NIC facing your LAN on the masters (e.g. `eth0`) |
| `$vip` | `10.10.30.30` |

```bash
# Quick in-place substitution (do not commit the result with real values)
sed -i 's/\$interface/eth0/g; s/\$vip/10.10.30.30/g' daemonset.yaml
```

## Deploy

kube-vip must exist before the k3s cluster is fully bootstrapped — it's typically applied during the Ansible k3s install playbook. To apply manually after the fact:

```bash
kubectl apply -f daemonset.yaml
```

Verify the VIP is responding:

```bash
kubectl --server=https://10.10.30.30:6443 cluster-info
```

## Notes

- The DaemonSet runs with `hostNetwork: true` and requires `NET_ADMIN` + `NET_RAW` capabilities to manage ARP.
- `tolerations: [{effect: NoSchedule}, {effect: NoExecute}]` ensures it runs on tainted control-plane nodes.
- Node affinity targets both `node-role.kubernetes.io/master` and `node-role.kubernetes.io/control-plane` for compatibility.
