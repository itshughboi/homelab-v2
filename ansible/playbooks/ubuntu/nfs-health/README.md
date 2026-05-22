# nfs-health

Verifies NFS mounts across all hosts are mounted, readable, and writable. Attempts to remount stale mounts and alerts if any fail to recover.

## What it does

Reads `/etc/fstab` on each host, finds all NFS entries, and for each:
1. Checks it's actually mounted (not just in fstab)
2. Runs a read test (detects stale NFS handles)
3. Runs a write test if not mounted read-only
4. Attempts remount if the check fails

Sends ntfy urgent alert if any mount fails to recover.

## Run

```sh
cd ansible/playbooks/ubuntu/nfs-health
ansible-playbook -i <inventory> main.yaml
```

## Schedule

Daily in Semaphore. NFS mounts (TrueNAS shares used by k3s nodes, etcd backup destination, Docker volume backup destination) silently go stale after network interruptions — this catches it before services fail.
