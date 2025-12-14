#!/usr/bin/env bash
set -euo pipefail

# wait_for_ssh.sh <timeout_seconds> <ssh_user> <ssh_key> <ip1> [ip2 ip3 ...]
# Wait until all provided IPs accept an SSH connection for the given user/key.
# Exits 0 if all reachable within timeout, non-zero otherwise.
if [ "$#" -lt 4 ]; then
  echo "Usage: $0 <timeout_seconds> <ssh_user> <ssh_key> <ip1> [ip2 ...]"
  exit 2
fi

TIMEOUT="$1"; shift
SSH_USER="$1"; shift
SSH_KEY="$1"; shift

IPS=("$@")
START_TS=$(date +%s)
END_TS=$((START_TS + TIMEOUT))

echo "Waiting up to ${TIMEOUT}s for SSH on ${#IPS[@]} hosts..."

for ip in "${IPS[@]}"; do
  echo " - Scheduling wait for ${ip}"
done

for ip in "${IPS[@]}"; do
  echo "Waiting for SSH ${SSH_USER}@${ip} ..."
  while true; do
    now=$(date +%s)
    if [ "$now" -gt "$END_TS" ]; then
      echo "Timeout waiting for ${ip}"
      exit 3
    fi

    # quick connect test: try to run true, short ConnectTimeout to avoid long hangs
    ssh -oBatchMode=yes -oStrictHostKeyChecking=no -oConnectTimeout=5 -i "${SSH_KEY}" "${SSH_USER}@${ip}" "exit" >/dev/null 2>&1 && {
      echo "SSH OK: ${ip}"
      break
    }

    sleep 3
  done
done

echo "All hosts are reachable via SSH."
exit 0