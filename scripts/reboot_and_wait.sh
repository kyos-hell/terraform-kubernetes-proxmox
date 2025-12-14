#!/usr/bin/env bash
set -euo pipefail

# Usage: reboot_and_wait.sh <VM_IP> <SSH_KEY_PATH> <SSH_USER> [SSH_PORT] [CLOUDINIT_TIMEOUT_SECONDS]
VM_IP="${1:-}"
SSH_KEY="${2:-}"
SSH_USER="${3:-ubuntu}"
SSH_PORT="${4:-22}"
CLOUDINIT_TIMEOUT="${5:-600}"  # seconds to wait for cloud-init

if [ -z "$VM_IP" ] || [ -z "$SSH_KEY" ] || [ -z "$SSH_USER" ]; then
  echo "Usage: $0 <VM_IP> <SSH_KEY_PATH> <SSH_USER> [SSH_PORT] [CLOUDINIT_TIMEOUT_SECONDS]"
  exit 2
fi

LOGDIR="${PWD}/.terraform_reboot_logs"
mkdir -p "$LOGDIR"
LOGFILE="${LOGDIR}/reboot_${VM_IP}_$(date -u +"%Y%m%dT%H%M%SZ").log"

SSH_OPTS="-oBatchMode=yes -oStrictHostKeyChecking=no -oConnectTimeout=5 -p ${SSH_PORT}"

timestamp() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

echo "$(timestamp) - START reboot_and_wait for ${VM_IP}" | tee -a "$LOGFILE"

# Remove any existing known_hosts entries for this IP on the local controller and root (best-effort).
# This avoids host key mismatch when re-running the workflow.
echo "$(timestamp) - Removing existing known_hosts entries for ${VM_IP} (local)" | tee -a "$LOGFILE"
ssh-keygen -f "${HOME}/.ssh/known_hosts" -R "${VM_IP}" >>"$LOGFILE" 2>&1 || true
ssh-keygen -f "/root/.ssh/known_hosts" -R "${VM_IP}" >>"$LOGFILE" 2>&1 || true

echo "$(timestamp) - Triggering reboot on ${VM_IP} as ${SSH_USER}" | tee -a "$LOGFILE"
# attempt reboot via ssh; may fail if SSH connection closes immediately
ssh ${SSH_OPTS} -i "${SSH_KEY}" "${SSH_USER}@${VM_IP}" "sudo reboot" >>"$LOGFILE" 2>&1 || true

# wait for SSH to drop
echo "$(timestamp) - Waiting for SSH to drop..." | tee -a "$LOGFILE"
for i in $(seq 1 60); do
  if ssh ${SSH_OPTS} -i "${SSH_KEY}" "${SSH_USER}@${VM_IP}" "true" >/dev/null 2>&1; then
    sleep 1
  else
    echo "$(timestamp) - SSH is down (after ${i}s)" | tee -a "$LOGFILE"
    break
  fi
done

# wait for SSH to come back
echo "$(timestamp) - Waiting for SSH to come back..." | tee -a "$LOGFILE"
for i in $(seq 1 300); do
  if ssh ${SSH_OPTS} -i "${SSH_KEY}" "${SSH_USER}@${VM_IP}" "echo SSH_OK" >/dev/null 2>&1; then
    echo "$(timestamp) - SSH is back (after ${i}s)" | tee -a "$LOGFILE"
    break
  fi
  sleep 2
  if [ "$i" -eq 300 ]; then
    echo "$(timestamp) - ERROR: SSH did not come back within timeout (300s)" | tee -a "$LOGFILE"
    exit 1
  fi
done

# Wait for cloud-init to finish on the VM with a remote timeout to avoid infinite dots
echo "$(timestamp) - Waiting for cloud-init to finish on ${VM_IP} (timeout ${CLOUDINIT_TIMEOUT}s)..." | tee -a "$LOGFILE"
# use 'timeout' on the remote command to ensure it terminates after CLOUDINIT_TIMEOUT
# We run via ssh and wrap the remote command with timeout (POSIX /usr/bin/timeout)
if ssh ${SSH_OPTS} -i "${SSH_KEY}" "${SSH_USER}@${VM_IP}" "command -v timeout >/dev/null 2>&1 && timeout ${CLOUDINIT_TIMEOUT} sudo cloud-init status --wait || sudo cloud-init status --wait" >>"$LOGFILE" 2>&1; then
  echo "$(timestamp) - cloud-init reported finished (or returned) on ${VM_IP}" | tee -a "$LOGFILE"
else
  # either timeout expired or cloud-init returned non-zero
  # test exit reason: re-run a quick status check
  if ssh ${SSH_OPTS} -i "${SSH_KEY}" "${SSH_USER}@${VM_IP}" "sudo cloud-init status --long" >>"$LOGFILE" 2>&1; then
    echo "$(timestamp) - cloud-init status checked after failure; proceed" | tee -a "$LOGFILE"
  else
    echo "$(timestamp) - WARNING: cloud-init did not finish cleanly within ${CLOUDINIT_TIMEOUT}s; check logs" | tee -a "$LOGFILE"
    echo "$(timestamp) - Tail of remote cloud-init log (last 200 lines):" | tee -a "$LOGFILE"
    ssh ${SSH_OPTS} -i "${SSH_KEY}" "${SSH_USER}@${VM_IP}" "sudo tail -n 200 /var/log/cloud-init.log || true" >>"$LOGFILE" 2>&1 || true
    # We choose to continue, but return non-zero to make Terraform fail and force investigation.
    echo "$(timestamp) - Exiting with error due to cloud-init timeout" | tee -a "$LOGFILE"
    exit 3
  fi
fi

echo "$(timestamp) - Reboot+cloud-init wait completed for ${VM_IP}" | tee -a "$LOGFILE"
echo "$(timestamp) - LOG saved to ${LOGFILE}"
exit 0