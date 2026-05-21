#!/usr/bin/env bash
set -euo pipefail

VM_NAME="${VM_NAME:-win-target}"
SSH_TARGET="${SSH_TARGET:-}"
REMOTE_DIR="${REMOTE_DIR:-C:/NeoOptimizeLab}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "[*] NeoOptimize win-target lab harness"
echo "[*] Repo: $ROOT_DIR"
echo "[*] VM  : $VM_NAME"

if ! command -v virsh >/dev/null 2>&1; then
  echo "[!] virsh tidak ditemukan di host ini."
  exit 1
fi

echo
echo "[*] virsh status"
virsh dominfo "$VM_NAME" | sed 's/^/    /'

echo
echo "[*] QEMU guest agent check"
if virsh qemu-agent-command "$VM_NAME" '{"execute":"guest-info"}' >/tmp/neo_qga.json 2>/tmp/neo_qga.err; then
  echo "    OK: QEMU guest agent tersedia"
  cat /tmp/neo_qga.json | sed 's/^/    /'
else
  echo "    WARN: QEMU guest agent belum tersedia"
  sed 's/^/    /' /tmp/neo_qga.err || true
fi

echo
echo "[*] DHCP leases"
for net in default target-zone; do
  if virsh net-info "$net" >/dev/null 2>&1; then
    echo "    [$net]"
    virsh net-dhcp-leases "$net" | sed 's/^/      /'
  fi
done

if [[ -z "$SSH_TARGET" ]]; then
  echo
  echo "[i] SSH_TARGET belum diisi, jadi test eksekusi Windows dilewati."
  echo "    Contoh:"
  echo "    SSH_TARGET='Administrator@10.10.10.120' tools/Invoke-WinTargetLabTest.sh"
  exit 0
fi

if ! command -v ssh >/dev/null 2>&1 || ! command -v scp >/dev/null 2>&1; then
  echo "[!] ssh/scp tidak tersedia di host ini."
  exit 1
fi

echo
echo "[*] Testing SSH to $SSH_TARGET"
ssh -o BatchMode=yes -o ConnectTimeout=8 "$SSH_TARGET" "powershell -NoProfile -Command \"\$PSVersionTable.PSVersion.ToString()\""

echo
echo "[*] Preparing remote directory $REMOTE_DIR"
ssh "$SSH_TARGET" "powershell -NoProfile -Command \"New-Item -Path '$REMOTE_DIR' -ItemType Directory -Force | Out-Null\""

echo
echo "[*] Copying NeoOptimize to win-target"
scp -r "$ROOT_DIR"/* "$SSH_TARGET:$REMOTE_DIR/"

echo
echo "[*] Running self-test"
ssh "$SSH_TARGET" "powershell -NoProfile -ExecutionPolicy RemoteSigned -File '$REMOTE_DIR/tools/Invoke-NeoOptimizeSelfTest.ps1'"

echo
echo "[*] Running agent audit"
ssh "$SSH_TARGET" "powershell -NoProfile -ExecutionPolicy RemoteSigned -File '$REMOTE_DIR/NeoOptimizeAgent.ps1' -Mode Audit -NoOpen"

echo
echo "[OK] Lab test selesai. Report berada di $REMOTE_DIR/reports/agent pada VM."
