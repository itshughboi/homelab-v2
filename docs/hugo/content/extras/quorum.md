---
title: "Quorum and QDevice"
---

Typically, you **don’t** need a QDevice (Quorum Device) in a 3-node Proxmox VE cluster. Because Proxmox requires a strict majority of votes to maintain quorum and allow cluster operations, an odd number of nodes (like 3) naturally provides a built-in tie-breaker.

In a standard 3-node setup, you have 3 total votes. Quorum is achieved at $\lfloor 3/2 \rfloor + 1 = 2$ votes. If one node dies, the remaining 2 nodes still have a majority, and the cluster keeps running smoothly.

However, there are a few specific, high-engineering scenarios where adding a QDevice to a 3-node cluster actually makes sense:

### 1. Preparing for an Expected 2-Node Split (Asymmetric Network Failure)

If your 3-node cluster isn't sitting in the same rack, but is instead distributed across separate locations—such as two nodes in a primary data center and one node in a backup office or secondary location—you have a geographic imbalance.

If the network link to the secondary location drops, the primary site still has 2 nodes (and thus quorum). But what if one of those primary nodes fails _while_ the secondary site is isolated? The single remaining primary node will lose quorum and drop your VMs, even though it's perfectly healthy.

Adding an external QDevice (perhaps hosted in a cloud instance or a third, completely independent site) and adjusting vote weights allows the cluster to survive more complex multi-point network partitions.

### 2. Upgrading to a "2 + 1" High-Availability Architecture

Sometimes, a 3-node cluster isn't actually three identical, high-powered servers. If you are using two heavy-duty enterprise nodes to host your actual workloads, and the third node is a weak, low-power machine (like a mini PC or an old thin client) brought in _solely_ to act as a witness for quorum, you are essentially running a 2-node cluster with a physical tie-breaker.

While this works, running a full Proxmox VE stack on that weak third node introduces unnecessary maintenance overhead (OS updates, corosync traffic, web GUI management). In this case, it is often cleaner to configure the cluster as a **2-node cluster + a lightweight QDevice** running on that minimal hardware (or even a container), freeing you from managing a third full PVE node.

### 3. Maintaining Even-Number Fault Tolerance During Maintenance

If you plan to scale your cluster up to 4 nodes in the near future, you will temporarily enter an even-number node state.

- **Without a QDevice:** A 4-node cluster requires 3 votes for quorum. If you lose 2 nodes, your whole cluster splits.
    
- **With a QDevice:** The QDevice brings the total vote count to 5. Quorum is still 3, meaning the cluster can now safely lose any 2 physical nodes without losing quorum.
    

Integrating the QDevice while you are still at 3 nodes establishes the Corosync QNet infrastructure early, making the transition to 4 nodes completely seamless.

---

### Summary of Quorum Behavior

|**Cluster Configuration**|**Total Votes**|**Quorum Required**|**Nodes Allowed to Fail**|
|---|---|---|---|
|**Standard 3-Node**|3|2|1|
|**3-Node + QDevice**|4*|3|1 (but protects specific split-brain layouts)|


> [!NOTE] Vote Adjustment
> Corosync automatically adjusts vote weights when a QDevice is added to an odd number of nodes to prevent a tie (usually giving the QDevice 0 votes unless a tie-breaker is explicitly needed), which is why it doesn't automatically grant a 2-node failure tolerance to a 3-node cluster without specific configuration._



# Quorum and QDevice

---

## TL;DR for a 4-Node Cluster

In a standard 4-node cluster you have 4 votes. Quorum requires 3. If you lose 2 nodes
simultaneously, the cluster splits. A QDevice on Athena brings total votes to 5 — quorum
still requires 3, but you can now safely lose any 2 physical nodes without losing quorum.

Run the QDevice on Athena.

---

## When You Actually Need a QDevice

You typically don't need a QDevice in a 3-node cluster (odd number = natural tie-breaker).
But there are specific scenarios where it makes sense:

### 1. Preparing for a 4-Node Cluster

When you scale from 3 to 4 nodes, you temporarily enter an even-number state.

- **Without QDevice:** A 4-node cluster requires 3 votes. Lose 2 nodes — cluster splits.
- **With QDevice:** Total votes become 5. Quorum still requires 3. The cluster survives
  losing any 2 physical nodes.

Setting up the QDevice while still at 3 nodes establishes the Corosync QNet infrastructure
early, making the 4-node transition seamless.

### 2. Geographic Split Risk

If nodes are distributed across locations (2 at primary site, 1 at secondary), and the
link to the secondary drops while a primary node also fails — the single remaining primary
node loses quorum and drops VMs even though it's perfectly healthy.

An external QDevice (cloud instance or third independent site) with adjusted vote weights
lets the cluster survive more complex multi-point partitions.

### 3. Weak Third Node

If your "third node" is a low-power machine brought in only as a witness (not for workloads),
a lightweight QDevice on that hardware is cleaner than running a full PVE stack on it just
for quorum.

---

## Quorum Behavior Summary

| Cluster Configuration | Total Votes | Quorum Required | Nodes Allowed to Fail |
| --- | --- | --- | --- |
| Standard 3-Node | 3 | 2 | 1 |
| 3-Node + QDevice | 4* | 3 | 1 (but protects specific split-brain layouts) |
| Standard 4-Node | 4 | 3 | 1 |
| 4-Node + QDevice | 5 | 3 | 2 |

> [!NOTE] Vote Adjustment
> Corosync automatically adjusts vote weights when a QDevice is added to an odd number
> of nodes to prevent a tie — usually giving the QDevice 0 votes unless a tie-breaker
> is explicitly needed. This is why a 3-node + QDevice doesn't automatically grant
> 2-node failure tolerance without specific configuration.
