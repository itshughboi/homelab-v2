# Cluster Decommission (Break-Glass)

> [!CAUTION]
> These commands permanently remove cluster configuration. Only run on the node
> you wish to keep as a standalone server (pve-srv-1) after all other nodes
> have been powered down.

---

## When to Use This

- Cluster has lost quorum and cannot recover
- You need to rebuild the cluster from scratch
- You're converting a clustered node back to standalone for testing

---

## Steps

### 1. Stop Cluster Communication

Stops the services that allow nodes to talk to each other and sync files.

```sh
systemctl stop pve-cluster corosync
```

### 2. Force Local Filesystem Access

Proxmox stores its config in a database (`pmxcfs`). When a cluster fails, this database
locks. This command forces it to mount in "Local Mode" so you can edit it.

```sh
pmxcfs -l
```

### 3. Delete Cluster Identity

Removes the "map" and "keys" that make this node think it's part of a cluster.

```sh
rm -rf /etc/corosync/*
rm /etc/pve/corosync.conf
```

### 4. Purge Ghost Nodes

Removes config directories for nodes being wiped. Cleans up the sidebar in the Web UI.

```sh
rm -rf /etc/pve/nodes/<node-name>
# Repeat for each ghost node
```

### 5. Re-initialize Standalone Mode

Kills the manual filesystem process and restarts the Proxmox cluster service
in its new, solo configuration.

```sh
killall pmxcfs
systemctl start pve-cluster
```

### 6. Refresh Web Interface

Restarts the API and web server to ensure the "Linux PAM" login realm and
solo node view appear correctly.

```sh
systemctl restart pveproxy pvestatd
```

---

## Verification

```sh
pvecm status
```

Should return an error saying the config does not exist. This is the correct
status for a non-clustered node.
