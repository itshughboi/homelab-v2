---
title: "Corosync — Cluster Links / Rings"
---

# Corosync — Cluster Links / Rings

Corosync is the Proxmox cluster communication layer (membership + quorum). It heartbeats over
one or more **links** ("rings"). If a node stops hearing heartbeats, the cluster can **fence**
it (hard reboot) to protect shared state — so link reliability directly affects cluster
stability.

Current state: **single link**, on the Cluster VLAN (20). See VLAN 20 in
[VLANs + VMs.md](../../1-networking/Unifi/Networks/VLANs%20+%20VMs.md).

---

## The risk with one link

If VLAN 20 has *any* problem — switch hiccup, a VLAN-20 misconfig, sustained congestion —
Corosync loses its only path, quorum breaks, and nodes fence. A single fault becomes a
cluster-wide outage. Corosync (knet, PVE 6+) supports up to 8 links specifically to avoid
this; best practice is ≥2 on independent paths.

There's a second, physical issue here: VLAN 20 is *logically* dedicated but **physically
shares the single 2.5 GbE trunk** (`enp42s0`/`vmbr1`) with everything else. So it isn't truly
isolated, and heavy traffic on that NIC can induce heartbeat latency (which is why Corosync
traffic is DSCP-tagged — see [QoS.md](../../1-networking/Unifi/Networks/QoS.md) — good
mitigation, but not isolation).

---

## Adding a virtual second link on the same NIC — honest tradeoffs

You can add `ring1` on the management VLAN (10) while keeping `ring0` on VLAN 20, both riding
`vmbr1` on the one physical NIC.

**What it does NOT fix:** if the NIC, cable, or switch port dies, **both** links die together
— a same-NIC second ring gives *zero* protection against the dominant physical failure modes.
knet treats the links as independent for failover, but it can't make them physically
independent.

**What it DOES help:** a VLAN-20-specific *misconfiguration* (ring1 on VLAN 10 survives), and
— more usefully — **transient VLAN-20 congestion**: if ring0 drops a few heartbeats under a
microburst, knet fails over to ring1 instead of declaring the node lost, which **reduces
false-positive fencing**. On a shared NIC, spurious fencing from latency is the realistic
risk, so this is a reasonable, free hedge.

**Verdict:** optional. It's cheap insurance against false fencing, not real redundancy. The
actual fix is physical separation (next section). If you add it, know exactly what it buys.

### Prerequisite — every node needs both VLANs

Each cluster node needs an IP on **both** VLAN 20 and VLAN 10:

- All node switch ports trunk every VLAN (10/20/30/40), so VLAN 20 frames reach every node.
- **The remaining task is host-side:** pve-srv-1 needs a `vmbr1.20` sub-interface with a
  `10.10.20.1/24` address before it can use a VLAN-20 ring (the switch trunk already allows
  it). Confirm pve-srv-2/3/4 likewise have their `.20` interfaces.

### Config

Edit `/etc/pve/corosync.conf` on **one** node (pmxcfs syncs it cluster-wide). **Bump
`config_version`** on every edit, and double-check before saving — a broken corosync.conf can
take the cluster offline.

```ini
totem {
    version: 2
    cluster_name: homelab
    config_version: <bump this>
    transport: knet
    interface {
        linknumber: 0          # ring0 — Cluster VLAN 20 (primary heartbeat)
    }
    interface {
        linknumber: 1          # ring1 — Management VLAN 10 (backup path)
    }
}

nodelist {
    node {
        name: pve-srv-1
        nodeid: 1
        ring0_addr: 10.10.20.1   # VLAN 20  (add this NIC first — see prerequisite)
        ring1_addr: 10.10.10.1   # VLAN 10
    }
    node {
        name: pve-srv-2
        nodeid: 2
        ring0_addr: 10.10.20.2
        ring1_addr: 10.10.10.2
    }
    # ... pve-srv-3 (.20.3 / .10.3), pve-srv-4 (.20.4 / .10.4)
}
```

After saving, watch `corosync-cfgtool -s` / `pvecm status` — both links should show as
connected on every node.

---

## End goal — physical separation (when the bigger switch arrives)

The size constraint today is a 5-port USW Flex Mini (4 nodes + uplink = full), so a dedicated
Corosync NIC per node has nowhere to plug in. When a larger switch is in place:

- **ring0 → dedicated 1 GbE NIC** per node (the mini PCs' spare onboard 1 GbE is plenty —
  Corosync traffic is tiny). This gives *true* physical isolation: a storage/backup flood on
  the 2.5 GbE NIC can't touch the heartbeat.
- **ring1 → management VLAN** on the 2.5 GbE, as the backup path.

That's the design that actually removes the single-NIC fragility. The virtual ring above is
the interim.

---

## Quorum — no QDevice (by choice)

Running 4 nodes **without** a QDevice. Quorum is 3; the cluster tolerates **1** node failure.

- A 2-2 split (e.g. switch partition) leaves *both* halves below quorum, so both freeze. That
  is the **safe** outcome — no split-brain corruption, just unavailability until a node
  returns.
- A QDevice (on Athena) would raise fault tolerance to 2 and break 2-2 ties, but adds a
  dependency and another moving part — **intentionally skipped** for now.

If the appetite changes later, `corosync-qnetd` on Athena + `pvecm qdevice setup 10.10.10.8`
is the path. Until then, treat "lose 1 node" as the cluster's tolerance.

---

## Related

- Time consistency is critical for Corosync — [NTP.md](../../1-networking/Unifi/Networks/NTP.md)
- VLAN 20 definition + DSCP priority: [VLANs + VMs.md](../../1-networking/Unifi/Networks/VLANs%20+%20VMs.md), [QoS.md](../../1-networking/Unifi/Networks/QoS.md)
