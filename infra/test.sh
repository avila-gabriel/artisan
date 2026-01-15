#!/usr/bin/env bash
set -euo pipefail

IMG_URL="https://cloud-images.ubuntu.com/focal/current/focal-server-cloudimg-amd64.img"

BASE_IMG="ubuntu20-base.img"
VM_IMG="ubuntu20-run.img"
SEED_IMG="seed.img"

ENV_CACHE_FILE=".env_mtime.cache"

SSH_PORT=2222
while ss -ltn | awk '{print $4}' | grep -q ":${SSH_PORT}$"; do
  SSH_PORT=$((SSH_PORT + 1))
done

VM_PID=""

HOST_SSH_KEY="${HOME}/.ssh/qemu-artisan-test"

SSH_OPTS=(
  -i "${HOST_SSH_KEY}"
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o GlobalKnownHostsFile=/dev/null
  -o LogLevel=ERROR
)

ENV_MTIME="$(stat -c '%Y' Makefile infra/* | sort -n | tail -n 1)"

CACHE_HIT=false
if [ -f "${ENV_CACHE_FILE}" ] && [ "$(cat "${ENV_CACHE_FILE}")" = "${ENV_MTIME}" ]; then
  CACHE_HIT=true
fi

if [ ! -f "${HOST_SSH_KEY}" ]; then
  mkdir -p "${HOME}/.ssh"
  ssh-keygen -t ed25519 -f "${HOST_SSH_KEY}" -N ""
fi

HOST_SSH_PUB="$(cat "${HOST_SSH_KEY}.pub")"

cleanup() {
  if [ -n "${VM_PID}" ] && kill -0 "${VM_PID}" 2>/dev/null; then
    kill "${VM_PID}"
    wait "${VM_PID}" 2>/dev/null || true
  fi
  if [ "${CACHE_HIT}" = false ]; then
    rm -f "${BASE_IMG}" "${SEED_IMG}" user-data meta-data
  fi
}
trap cleanup EXIT

if [ "${CACHE_HIT}" = false ]; then
  curl -fsSL "${IMG_URL}" -o "${BASE_IMG}"
  qemu-img create -f qcow2 -F qcow2 -b "${BASE_IMG}" "${VM_IMG}"
  qemu-img resize "${VM_IMG}" 20G

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
fi

QEMU_ARGS=(
  -enable-kvm
  -m 4096
  -smp 2
  -drive file="${VM_IMG}",format=qcow2
  -netdev user,id=net0,hostfwd=tcp::${SSH_PORT}-:22
  -device virtio-net-pci,netdev=net0
  -nographic
  -serial none
  -monitor none
)

if [ "${CACHE_HIT}" = false ]; then
  QEMU_ARGS+=( -drive file="${SEED_IMG}",format=raw )
fi

qemu-system-x86_64 "${QEMU_ARGS[@]}" &
VM_PID=$!

until ssh "${SSH_OPTS[@]}" -p "${SSH_PORT}" root@localhost true 2>/dev/null; do
  sleep 2
done

if [ "${CACHE_HIT}" = false ]; then
  until ssh "${SSH_OPTS[@]}" -p "${SSH_PORT}" root@localhost \
    '[ -f /var/lib/cloud/instance/boot-finished ]' 2>/dev/null; do
    sleep 2
  done
fi

if [ "${CACHE_HIT}" = false ]; then
  scp -P "${SSH_PORT}" "${SSH_OPTS[@]}" \
    infra/host-init.sh root@localhost:/root/host-init.sh

  ssh "${SSH_OPTS[@]}" -p "${SSH_PORT}" root@localhost \
    chmod +x /root/host-init.sh

  ssh -tt "${SSH_OPTS[@]}" -p "${SSH_PORT}" root@localhost \
    /root/host-init.sh

  echo "${ENV_MTIME}" > "${ENV_CACHE_FILE}"
fi

ssh -tt "${SSH_OPTS[@]}" -p "${SSH_PORT}" root@localhost

