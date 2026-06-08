# Proxmox Backup Server (PBS)

Reference: https://forums.lawrencesystems.com/t/proxmox-backup-server-on-truenas/26483

PBS runs as a Debian LXC container on pve-srv-1. Its datastore lives on a TrueNAS NFS share.

---

## Step 1 — Create the Dataset in TrueNAS

Use a **Generic** dataset to avoid the locking mechanisms of SMB or NFS presets,
which can interfere with how containers handle file ownership.

1. Log into the TrueNAS Web UI
2. Navigate to **Datasets** in the left sidebar
3. Select the parent pool
4. Click **Add Dataset** (top right)
5. Name: `pbs-storage`
6. Dataset Preset: **Generic**
7. Click **Save**

---

## Step 2 — Create Subdirectory and Set ACLs

Working in a subdirectory prevents PBS from conflicting with special folders
and lets you limit permissions precisely. Run in the **TrueNAS Shell**:

```sh
cd /mnt/tank/pbs-storage/
mkdir datastore1

# Set backup owner for container
chown -R 2147000035:2147000035 datastore1

# Apply access ACL and default ACL (inheritance)
setfacl -m u:2147000035:rwx,d:u:2147000035:rwx datastore1
```

The UID `2147000035` is the mapped container user for the backup role inside PBS.

---

## Step 3 — Create the Debian Container in Proxmox

Create a Debian 13 LXC container in Proxmox. Then open the container shell and run:

**Optional: install bash completion**
```sh
apt update && apt install -y bash-completion
cat << 'EOF' >> ~/.bashrc
if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
fi
EOF
source .bashrc
```

**Set root password:**
```sh
passwd root
```

**Prepare the environment:**
```sh
apt update && apt upgrade -y
apt install -y wget curl gnupg2 ca-certificates
```

---

## Step 4 — Install PBS

**Download Proxmox key:**
```sh
wget https://enterprise.proxmox.com/debian/proxmox-release-trixie.gpg \
  -O /etc/apt/trusted.gpg.d/proxmox-release-trixie.gpg
```

**Create the repository file:**
```sh
cat <<EOF > /etc/apt/sources.list.d/pbs-no-subscription.sources
Types: deb
URIs: http://download.proxmox.com/debian/pbs
Suites: trixie
Components: pbs-no-subscription
Signed-By: /etc/apt/trusted.gpg.d/proxmox-release-trixie.gpg
EOF
```

**Install:**
```sh
apt update && apt upgrade
apt install -y proxmox-backup-server
```

---

## Step 5 — Access Web UI

1. Get the container IP: `ip -4 -brief address show`
2. Navigate to `https://<CONTAINER_IP>:8007`
3. Ignore the self-signed SSL warning
4. Login: `root` / your password / Realm: **Linux PAM**

---

## Testing Permissions

If you need to verify the ACL setup is correct:

```sh
sudo -u backup touch /mnt/pbs/datastore1/testfile
```

If it succeeds, clean up:
```sh
rm /mnt/pbs/datastore1/testfile
```
