# k3s Overview

k3s is up and running. All configs live in Git under `/kubernetes`.
Deployment and cluster management is handled entirely via Ansible playbook run from Semaphore.

---

## Cluster Layout

3 control plane nodes (tainted NoSchedule) + 3 workers across pve-srv-2, 3, and 4.

| VM | Host | Role |
| --- | --- | --- |
| master-1 | pve-srv-2 | Control plane |
| master-2 | pve-srv-3 | Control plane |
| master-3 | pve-srv-4 | Control plane |
| worker-1 | pve-srv-2 | Workloads + Longhorn |
| worker-2 | pve-srv-3 | Workloads + Longhorn |
| worker-3 | pve-srv-4 | Workloads + Longhorn |

All nodes on VLAN 30. Workers dual-homed on VLAN 30/40 for Longhorn storage traffic.

---

## IP Assignments

| Name | IP |
| --- | --- |
| k3s-master-1 | 10.10.30.1 |
| k3s-master-2 | 10.10.30.2 |
| k3s-master-3 | 10.10.30.3 |
| k3s-worker-1 | 10.10.30.11 |
| k3s-worker-2 | 10.10.30.12 |
| k3s-worker-3 | 10.10.30.13 |
| k3s-api-vip | 10.10.30.30 |
| k3s-longhorn-vip | 10.10.30.50 |
| k3s-longhorn-1 | 10.10.30.51 |
| k3s-longhorn-2 | 10.10.30.52 |
| k3s-longhorn-3 | 10.10.30.53 |
| MetalLB range start | 10.10.30.60 |
| traefik-vip | 10.10.30.65 |
| pihole-vip | 10.10.30.69 |
| MetalLB range end | 10.10.30.99 |

---

## Deploying / Re-deploying

Run the k3s Ansible playbook from Semaphore on Athena.

Verify after deploy:
```sh
kubectl get nodes
```
All 6 nodes should show `Ready`.

---

## Longhorn

Distributed storage across worker nodes. Each worker has a dedicated 500 GB SSD.
Longhorn replica sync uses ports 9500–9504 between k3s nodes (intra-VLAN, no firewall rules needed).

---

## GitOps

ArgoCD watches the Gitea `/kubernetes` folder. All app deployments are declarative —
push to Git, ArgoCD syncs the cluster.

Firewall note: k3s nodes cannot initiate connections to Management (VLAN 10).
See [`1-networking/Unifi/Firewall/Rules.md`](../1-networking/Unifi/Firewall/Rules.md) for full k3s rules.
