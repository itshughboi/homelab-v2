#!/usr/bin/env bash
# Install the disk-usage-report cron job on the host (dock-prod). Runs the report
# hourly as root (du needs root for some paths) and logs to /var/log/disk-usage.log,
# which Alloy ships to Loki. Idempotent — safe to re-run.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$SCRIPT_DIR/disk-usage-report.sh"
DEST=/usr/local/bin/disk-usage-report.sh
CRON=/etc/cron.d/disk-usage-report

sudo install -m 0755 "$SRC" "$DEST"
sudo tee "$CRON" >/dev/null <<EOF
# Hourly disk-usage breakdown -> /var/log/disk-usage.log -> Loki (managed by homelab repo)
17 * * * * root $DEST
EOF
sudo chmod 0644 "$CRON"
echo "Installed: $DEST + $CRON (runs hourly at :17)"
echo "Run once now:  sudo $DEST && tail /var/log/disk-usage.log"
