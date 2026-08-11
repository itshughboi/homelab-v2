#!/usr/bin/env bash
# Log a disk-usage breakdown to /var/log/disk-usage.log so it ships to Loki (Alloy
# tails /var/log/*log). When the DiskSpaceLow/Critical Prometheus alert fires, you
# can then see WHAT is using space in Grafana (Explore: {job="dock-prod_varlogs"}
# |= "disk-usage") instead of SSHing in to run du by hand.
#
# Installed via /etc/cron.d/disk-usage-report (see install-disk-usage-report.sh).
set -euo pipefail

LOG=/var/log/disk-usage.log
TS="$(date -Is)"

{
  echo "disk-usage $TS === filesystem ==="
  df -h / | awk 'NR==2 {printf "disk-usage %s root: %s used of %s (%s), %s free\n", "'"$TS"'", $3, $2, $5, $4}'

  echo "disk-usage $TS === top /home/hughboi/data (app data) ==="
  du -sh /home/hughboi/data/* 2>/dev/null | sort -rh | head -15 \
    | sed "s/^/disk-usage $TS /"

  echo "disk-usage $TS === top /home/hughboi (home) ==="
  du -sh /home/hughboi/* 2>/dev/null | sort -rh | head -10 \
    | sed "s/^/disk-usage $TS /"

  echo "disk-usage $TS === docker overlay/volumes ==="
  du -sh /var/lib/docker/volumes 2>/dev/null | sed "s/^/disk-usage $TS /"
} >> "$LOG" 2>&1

# Keep the log small (it's shipped to Loki anyway).
tail -n 2000 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
