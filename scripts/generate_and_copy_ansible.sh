#!/usr/bin/env bash
set -euo pipefail

# generate_and_copy_ansible.sh <terraform_dir> <remote_user>@<ansible_ip> <remote_target_dir> <ssh_key>
# - generates ansible/inventory.ini from terraform output 'vms' (flattens nested ip lists)
# - writes inventory.ini into local ansible/ (overwrites)
# - copies ansible/ to remote atomically (uses .tmp then mv)
# - uploads the SSH key to remote /home/<user>/.ssh/id_ansible (optional, if key present)
#
# Example:
# ./scripts/generate_and_copy_ansible.sh . ubuntu@192.168.11.10 /home/ubuntu/ansible ./secrets/id_ansible

if [ "$#" -ne 4 ]; then
  echo "Usage: $0 <terraform_dir> <remote_user>@<ansible_ip> <remote_target_dir> <ssh_key>"
  exit 2
fi

TF_DIR="$1"
REMOTE="$2"
REMOTE_DIR="$3"
SSH_KEY="$4"

LOCAL_ANSIBLE_DIR="ansible"
LOCAL_INVENTORY="${LOCAL_ANSIBLE_DIR}/inventory.ini"

# Require terraform and jq or python3
if ! command -v terraform >/dev/null 2>&1; then
  echo "terraform required in PATH"
  exit 3
fi
if ! command -v jq >/dev/null 2>&1 && ! command -v python3 >/dev/null 2>&1; then
  echo "jq or python3 required in PATH"
  exit 3
fi

# Ensure terraform dir exists (autodetect fallback)
if [ ! -d "$TF_DIR" ]; then
  echo "Warning: terraform dir '$TF_DIR' not found; attempting autodetect..."
  autodir="$(find . -maxdepth 4 -type f -name '*.tf' -print -quit || true)"
  if [ -n "$autodir" ]; then
    TF_DIR="$(dirname "$autodir")"
    echo "Autodetected terraform dir: $TF_DIR"
  else
    echo "No Terraform files found. Please pass the correct terraform dir."
    exit 4
  fi
fi

echo "Querying terraform output 'vms' in ${TF_DIR}..."
TF_JSON="$(terraform -chdir="$TF_DIR" output -json vms 2>/dev/null || true)"

if [ -z "$TF_JSON" ]; then
  echo "terraform output -json vms failed or returned empty. Ensure terraform apply was run and output 'vms' exists."
  exit 4
fi

# Validate JSON
if command -v jq >/dev/null 2>&1; then
  if ! printf '%s' "$TF_JSON" | jq . >/dev/null 2>&1; then
    echo "terraform output is not valid JSON (jq parse failed). Aborting."
    exit 5
  fi
else
  if ! printf '%s' "$TF_JSON" | python3 -m json.tool >/dev/null 2>&1; then
    echo "terraform output is not valid JSON (python parse failed). Aborting."
    exit 5
  fi
fi

# Generate inventory.ini content and write to local ansible/inventory.ini (overwrite)
mkdir -p "${LOCAL_ANSIBLE_DIR}"

echo "Generating ${LOCAL_INVENTORY} from Terraform output ..."

# Ensure inventory file is emptied before writing to avoid accidental append/increment
# This guarantees the file starts clean even if previous runs left stray content.
if [ -f "${LOCAL_INVENTORY}" ]; then
  : > "${LOCAL_INVENTORY}"
fi

if command -v jq >/dev/null 2>&1; then
  {
    printf "[all]\n\n"
    printf '%s\n' "$TF_JSON" | jq -r '
      to_entries[] |
      .key as $name |
      (.value.ip // []) as $ips |
      ($ips | flatten(2) | map(select(test("^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$")))) as $addrs |
      ($addrs | map(select(. != "127.0.0.1")) | .[0] // $addrs[0] // "UNKNOWN") as $ip |
      "\($name) ansible_host=\($ip)"
    '
    printf "\n[all:vars]\nansible_python_interpreter=/usr/bin/python3\nansible_ssh_private_key_file=/home/ubuntu/.ssh/id_ansible\nansible_user=ubuntu\n"
  } > "${LOCAL_INVENTORY}"
else
  # python fallback: use TF_JSON through env var to avoid heredoc stdin conflict
  TF_JSON_ESC="$TF_JSON" TF_JSON="$TF_JSON_ESC" python3 - <<'PY' > "${LOCAL_INVENTORY}"
import os, json, sys
def find_ip(val):
    if isinstance(val, str):
        return val
    if isinstance(val, list):
        flat=[]
        def flatten(x):
            if isinstance(x, list):
                for e in x:
                    flatten(e)
            else:
                flat.append(x)
        flatten(val)
        candidates=[e for e in flat if isinstance(e,str) and e.count('.')==3]
        if candidates:
            for c in candidates:
                if not c.startswith('127.'):
                    return c
            return candidates[0]
        return None
    if isinstance(val, dict):
        for key in ('ip','ips','address','addresses','public_ip','private_ip','ipv4'):
            if key in val:
                return find_ip(val[key])
        for k,v in val.items():
            if isinstance(v,str) and v.count('.')==3 and not v.startswith('127.'):
                return v
    return None

data = json.loads(os.environ.get('TF_JSON','{}'))
print("[all]\n")
if isinstance(data, dict):
    for k,m in data.items():
        ip = None
        if isinstance(m, dict):
            ip = find_ip(m.get('ip') if 'ip' in m else m)
        if not ip:
            ip = find_ip(m) or 'UNKNOWN'
        print(f"{k} ansible_host={ip}")
print("\n[all:vars]")
print("ansible_python_interpreter=/usr/bin/python3")
print("ansible_ssh_private_key_file=/home/ubuntu/.ssh/id_ansible")
print("ansible_user=ubuntu")
PY
fi

echo "Local inventory written to ${LOCAL_INVENTORY}:"
sed -n '1,200p' "${LOCAL_INVENTORY}"

# Normalize SSH key permissions locally (optional but helpful)
if [ -f "${SSH_KEY}" ]; then
  chmod 600 "${SSH_KEY}" || true
fi

# Ensure local ansible directory exists and strip CRLFs
if [ ! -d "${LOCAL_ANSIBLE_DIR}" ]; then
  echo "Local '${LOCAL_ANSIBLE_DIR}/' directory not found. Create it before running this script."
  exit 6
fi
find "${LOCAL_ANSIBLE_DIR}" -type f \( -iname '*.sh' -o -iname '*.yml' -o -iname '*.yaml' -o -iname '*.py' -o -iname '*.cfg' -o -iname '*.ini' -o -iname '*.txt' -o -iname '*.json' \) -print0 | xargs -0 -r sed -i 's/\r$//'

# Prepare remote parent directory: try normal mkdir, fallback to sudo mkdir+chown
REMOTE_USER="${REMOTE%%@*}"
REMOTE_HOST="${REMOTE##*@}"
REMOTE_PARENT="$(dirname "${REMOTE_DIR}")"

echo "Ensuring remote parent ${REMOTE_PARENT} exists and is writable by ${REMOTE_USER}..."
# attempt normal mkdir
ssh -i "${SSH_KEY}" -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null "${REMOTE}" "mkdir -p '${REMOTE_PARENT}'" >/dev/null 2>&1 || true
# check writability; if not writable, try sudo create+chown (uses passwordless sudo)
ssh -i "${SSH_KEY}" -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null "${REMOTE}" bash -c "'
if [ ! -w \"${REMOTE_PARENT}\" ]; then
  sudo mkdir -p \"${REMOTE_PARENT}\" || true
  sudo chown -R ${REMOTE_USER}:${REMOTE_USER} \"${REMOTE_PARENT}\" || true
fi
'" >/dev/null 2>&1 || true

# Optionally copy the SSH key to the control node so ansible can connect to hosts
if [ -f "${SSH_KEY}" ]; then
  echo "Copying SSH key to remote ${REMOTE_HOST}:/home/${REMOTE_USER}/.ssh/id_ansible (will overwrite if exists)..."
  scp -i "${SSH_KEY}" -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null "${SSH_KEY}" "${REMOTE}:${REMOTE_PARENT}/.ssh/id_ansible" >/dev/null 2>&1 || true
  # ensure proper perms and owner
  ssh -i "${SSH_KEY}" -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null "${REMOTE}" "sudo chown ${REMOTE_USER}:${REMOTE_USER} '${REMOTE_PARENT}/.ssh/id_ansible' 2>/dev/null || true; sudo chmod 600 '${REMOTE_PARENT}/.ssh/id_ansible' 2>/dev/null || true" >/dev/null 2>&1 || true
fi

# Copy ansible/ to remote as .tmp
echo "Copying ${LOCAL_ANSIBLE_DIR}/ to remote ${REMOTE}:${REMOTE_DIR}.tmp ..."
scp -r -i "${SSH_KEY}" -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null "${LOCAL_ANSIBLE_DIR}" "${REMOTE}:${REMOTE_DIR}.tmp"

# Move into place and set ownership/perms on remote (atomic-ish)
echo "Moving ${REMOTE_DIR}.tmp -> ${REMOTE_DIR} on remote and fixing permissions..."
ssh -i "${SSH_KEY}" -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null "${REMOTE}" "sudo rm -rf '${REMOTE_DIR}.old' || true; if [ -d '${REMOTE_DIR}' ]; then sudo mv '${REMOTE_DIR}' '${REMOTE_DIR}.old' || true; fi; sudo mv '${REMOTE_DIR}.tmp' '${REMOTE_DIR}' && sudo chown -R ${REMOTE_USER}:${REMOTE_USER} '${REMOTE_DIR}' || true; sudo find '${REMOTE_DIR}' -type d -print0 | sudo xargs -0 -r chmod 755 || true; sudo find '${REMOTE_DIR}' -type f -print0 | sudo xargs -0 -r chmod 644 || true"

# If inventory file exists locally we already wrote it into ansible/, it should be uploaded by scp above.
echo "Done. Remote ${REMOTE}:${REMOTE_DIR} should contain the ansible control files."
exit 0