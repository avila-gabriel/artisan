#!/usr/bin/env bash
set -euo pipefail

echo
echo "=== Artisan VM Migration Orchestrator ==="
echo

read -rp "Old VM SSH (e.g. root@1.2.3.4): " OLD_VM
read -rp "New VM SSH (e.g. root@5.6.7.8): " NEW_VM

echo
echo "== Connectivity checks =="

ssh -o BatchMode=yes "$OLD_VM" true
ssh -o BatchMode=yes "$NEW_VM" true

echo
read -rp "Proceed with migration? THIS WILL CAUSE DOWNTIME (yes/no): " CONFIRM
[ "$CONFIRM" = "yes" ] || exit 1

echo
echo "== Downtime starts =="

echo "- Stopping server on old VM"
ssh "$OLD_VM" '
  systemctl stop server-blue 2>/dev/null || true
  systemctl stop server-green 2>/dev/null || true
'

echo "- Syncing database old → new"
ssh "$NEW_VM" 'mkdir -p /opt/artisan/data'
rsync -av \
  "$OLD_VM:/opt/artisan/data/data.db" \
  "$NEW_VM:/opt/artisan/data/data.db"

echo
echo "== Starting new VM =="

ssh "$NEW_VM" '
  cd /opt/artisan
  make deploy-existing
'

echo
echo "=== Migration complete ==="
echo "Old VM: stopped"
echo "New VM: live"
echo

