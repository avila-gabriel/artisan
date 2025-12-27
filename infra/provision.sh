#!/usr/bin/env bash
set -euo pipefail

echo "== verifying systemd =="
if [ "$(ps -p 1 -o comm=)" != "systemd" ]; then
  echo "ERROR: systemd is not PID 1"
  exit 1
fi

echo "== installing base packages =="
apt update
apt install -y \
  git make curl sudo ca-certificates \
  build-essential autoconf rsync

# -------------------------------------------------
# Deploy key ceremony
# -------------------------------------------------
mkdir -p /root/.ssh
chmod 700 /root/.ssh

DEPLOY_KEY="/root/.ssh/id_ed25519"
DEPLOY_KEY_TITLE="artisan-deploy"

if [ ! -f "$DEPLOY_KEY" ]; then
  echo
  echo "== generating deploy key =="
  ssh-keygen -t ed25519 -C "$DEPLOY_KEY_TITLE" -f "$DEPLOY_KEY" -N ""
fi

chmod 600 "$DEPLOY_KEY"

echo
echo "==================================================="
echo "ADD THIS DEPLOY KEY TO GITHUB"
echo
echo "Title:"
echo "  $DEPLOY_KEY_TITLE"
echo
echo "Public key:"
echo "---------------------------------------------------"
cat "${DEPLOY_KEY}.pub"
echo "---------------------------------------------------"
echo
echo "Add it here:"
echo "  https://github.com/avila-gabriel/artisan/settings/keys/new"
echo
echo "When done, press ENTER to continue."
echo "==================================================="
echo

# must read from real TTY
read -r _ </dev/tty

ssh-keyscan github.com >> /root/.ssh/known_hosts

# -------------------------------------------------
# Clone + deploy
# -------------------------------------------------
cd /opt
if [ ! -d artisan ]; then
  git clone git@github.com:avila-gabriel/artisan.git
fi

cd artisan

echo "== bootstrap machine =="
make bootstrap

echo "== deploy application =="
make install

echo "== verifying service =="
systemctl is-active --quiet server

echo
echo "== SUCCESS: deployment complete =="

