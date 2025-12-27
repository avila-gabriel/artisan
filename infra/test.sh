#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------
# Config
# -------------------------------------------------
IMG_URL="https://cloud-images.ubuntu.com/focal/current/focal-server-cloudimg-amd64.img"

BASE_IMG="ubuntu20-base.img"
VM_IMG="ubuntu20-run.img"
SEED_IMG="seed.img"

SSH_PORT=2222
VM_PID=""

HOST_SSH_KEY="${HOME}/.ssh/qemu-artisan-test"

GITHUB_USER="avila-gabriel"
REPO_NAME="artisan"
REPO_URL="git@github.com:${GITHUB_USER}/${REPO_NAME}.git"

DEPLOY_KEY_TITLE="artisan-deploy-test"
DEPLOY_KEY_URL="https://github.com/avila-gabriel/artisan/settings/keys/new"

# Force SSH to never touch known_hosts and to avoid interactive prompts/noise
SSH_OPTS=(
  -i "${HOST_SSH_KEY}"
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o GlobalKnownHostsFile=/dev/null
  -o LogLevel=ERROR
)

# -------------------------------------------------
# Ensure host SSH key exists (for host -> VM access)
# -------------------------------------------------
if [ ! -f "${HOST_SSH_KEY}" ]; then
  echo "== generating temporary host SSH key =="
  mkdir -p "${HOME}/.ssh"
  ssh-keygen -t ed25519 -f "${HOST_SSH_KEY}" -N ""
fi

HOST_SSH_PUB="$(cat "${HOST_SSH_KEY}.pub")"

# -------------------------------------------------
# Cleanup (stateless guarantee)
# -------------------------------------------------
cleanup() {
  echo
  echo "== cleaning up =="
  if [ -n "${VM_PID}" ] && kill -0 "${VM_PID}" 2>/dev/null; then
    kill "${VM_PID}"
    wait "${VM_PID}" || true
  fi
  rm -f "${BASE_IMG}" "${VM_IMG}" "${SEED_IMG}" user-data meta-data
}
trap cleanup EXIT

echo "== infra test: ONE-TIME Ubuntu 20.04 VPS (QEMU, real systemd) =="

# -------------------------------------------------
# Prepare image
# -------------------------------------------------
echo "== downloading Ubuntu cloud image =="
curl -fsSL "${IMG_URL}" -o "${BASE_IMG}"

echo "== creating writable disk =="
qemu-img create -f qcow2 -F qcow2 -b "${BASE_IMG}" "${VM_IMG}"
qemu-img resize "${VM_IMG}" 20G

# -------------------------------------------------
# Cloud-init seed (SSH key auth, no passwords)
# -------------------------------------------------
cat > user-data <<EOF
#cloud-config
users:
  - name: root
    lock_passwd: true
    ssh_authorized_keys:
      - ${HOST_SSH_PUB}
disable_root: false
package_update: true
packages:
  - tzdata
  - git
  - make
  - curl
  - sudo
  - rsync
  - openssh-client
  - ca-certificates
  - build-essential
  - autoconf
EOF

cat > meta-data <<EOF
instance-id: artisan-test
local-hostname: artisan-test
EOF

cloud-localds "${SEED_IMG}" user-data meta-data

# -------------------------------------------------
# Start VM
# -------------------------------------------------
echo "== starting VM =="

qemu-system-x86_64 \
  -enable-kvm \
  -m 4096 \
  -smp 2 \
  -drive file="${VM_IMG}",format=qcow2 \
  -drive file="${SEED_IMG}",format=raw \
  -netdev user,id=net0,hostfwd=tcp::${SSH_PORT}-:22 \
  -device virtio-net-pci,netdev=net0 \
  -nographic \
  -serial none \
  -monitor none &
VM_PID=$!

# -------------------------------------------------
# Wait for SSH
# -------------------------------------------------
echo "== waiting for SSH =="
until ssh "${SSH_OPTS[@]}" -p "${SSH_PORT}" root@localhost true 2>/dev/null; do
  sleep 2
done

echo "== waiting for cloud-init =="
until ssh "${SSH_OPTS[@]}" -p "${SSH_PORT}" root@localhost \
  '[ -f /var/lib/cloud/instance/boot-finished ]' 2>/dev/null; do
  sleep 2
done

# -------------------------------------------------
# REAL VPS FLOW (scripted, with one interactive pause)
# -------------------------------------------------
ssh -tt "${SSH_OPTS[@]}" -p "${SSH_PORT}" root@localhost bash -lc "$(cat <<'REMOTE'
set -euo pipefail

echo "== verifying systemd =="
if [ "$(ps -p 1 -o comm=)" != "systemd" ]; then
  echo "ERROR: systemd is not PID 1"
  exit 1
fi

mkdir -p /root/.ssh
chmod 700 /root/.ssh

echo
echo "== generating deploy key =="
ssh-keygen -t ed25519 -C "artisan-deploy-test" -f /root/.ssh/id_ed25519 -N ""

echo
echo "==================================================="
echo "ADD THIS DEPLOY KEY TO GITHUB"
echo
echo "Title (use exactly this):"
echo "  artisan-deploy-test"
echo
echo "Public key:"
echo "---------------------------------------------------"
cat /root/.ssh/id_ed25519.pub
echo "---------------------------------------------------"
echo
echo "Add it here:"
echo "  https://github.com/avila-gabriel/artisan/settings/keys/new"
echo
echo "When done, press ENTER to continue."
echo "==================================================="
echo

# Read ENTER from the actual TTY so it behaves like Docker
read -r _ </dev/tty

chmod 600 /root/.ssh/id_ed25519
ssh-keyscan github.com >> /root/.ssh/known_hosts

git clone git@github.com:avila-gabriel/artisan.git
cd artisan

echo "== bootstrap machine =="
make bootstrap

echo "== deploy application =="
make install

echo "== verifying service =="
systemctl is-active --quiet server

echo
echo "== SUCCESS: full infra test passed =="
REMOTE
)"

