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

# Force SSH to never touch known_hosts and avoid prompts
SSH_OPTS=(
  -i "${HOST_SSH_KEY}"
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o GlobalKnownHostsFile=/dev/null
  -o LogLevel=ERROR
)

# -------------------------------------------------
# Ensure host SSH key exists (host -> VM)
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
# REAL VPS FLOW (THIS IS THE POINT)
# -------------------------------------------------
echo "== copying provision.sh into VM =="

scp -P "${SSH_PORT}" \
  "${SSH_OPTS[@]}" \
  infra/provision.sh \
  root@localhost:/root/provision.sh

ssh "${SSH_OPTS[@]}" -p "${SSH_PORT}" root@localhost \
  chmod +x /root/provision.sh

echo "== running provision.sh inside VM =="

ssh -tt "${SSH_OPTS[@]}" -p "${SSH_PORT}" root@localhost \
  /root/provision.sh

