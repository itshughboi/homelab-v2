---
title: "TrueNAS Networking — Bridge Interface"
---

# TrueNAS Networking — Bridge Interface

Always assign the IP to a **bridge (`br0`)**, never directly to the physical NIC. Then if you
swap the underlying interface later (NIC failure/upgrade), you remap the bridge once instead of
reconfiguring every NFS share, iSCSI target, and container attached to it.

**System → Network → Interfaces:**
1. Note the current interface name.
2. 3 dots → Edit → **remove the IP** → **Save**.
   > Do NOT hit "Test Changes" — just Save.
3. **Add Interface**:
   - Type: **Bridge**
   - Name: `br0`
   - IP: the same IP as before
   - Bridge Members: the original interface name

Everything attached to `br0` keeps working when the physical NIC underneath it changes.
