#!/usr/bin/env bash
set -euo pipefail

# Idempotent installer for Ansible control node on ubuntu
# Usage: sudo ./scripts/install-ansible.sh
# Or: ssh -i key ubuntu@IP "sudo bash -s" < ./scripts/install-ansible.sh

ANSIBLE_VENV_DIR="/opt/ansible-venv"
ANSIBLE_VERSION="${ANSIBLE_VERSION:-}" # optional env var to pin a version, e.g. "2.14.4"
PY_PKGS=(python3-venv python3-pip python3-apt build-essential libssl-dev libffi-dev git)

timestamp() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

echo "$(timestamp) - Starting ansible install"

# If already installed in venv, skip heavy steps but still ensure perms for ~/.ansible
if [ -x "${ANSIBLE_VENV_DIR}/bin/ansible" ]; then
  echo "$(timestamp) - Ansible already present in ${ANSIBLE_VENV_DIR}, skipping installation steps."
else
  echo "$(timestamp) - Updating apt and installing prerequisites"
  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y "${PY_PKGS[@]}"

  echo "$(timestamp) - Creating python venv at ${ANSIBLE_VENV_DIR}"
  rm -rf "${ANSIBLE_VENV_DIR}"
  python3 -m venv "${ANSIBLE_VENV_DIR}"
  "${ANSIBLE_VENV_DIR}/bin/python" -m pip install --upgrade pip setuptools wheel

  if [ -n "${ANSIBLE_VERSION}" ]; then
    echo "$(timestamp) - Installing ansible==${ANSIBLE_VERSION} into venv"
    "${ANSIBLE_VENV_DIR}/bin/pip" install "ansible==${ANSIBLE_VERSION}"
  else
    echo "$(timestamp) - Installing latest ansible into venv"
    "${ANSIBLE_VENV_DIR}/bin/pip" install "ansible"
  fi

  # Create simple wrappers in /usr/local/bin for convenience
  echo "$(timestamp) - Creating wrapper scripts in /usr/local/bin"
  cat > /usr/local/bin/ansible <<'EOF'
#!/usr/bin/env bash
ANSIBLE_VENV_DIR="/opt/ansible-venv"
exec "${ANSIBLE_VENV_DIR}/bin/ansible" "$@"
EOF
  chmod 755 /usr/local/bin/ansible

  cat > /usr/local/bin/ansible-playbook <<'EOF'
#!/usr/bin/env bash
ANSIBLE_VENV_DIR="/opt/ansible-venv"
exec "${ANSIBLE_VENV_DIR}/bin/ansible-playbook" "$@"
EOF
  chmod 755 /usr/local/bin/ansible-playbook

  echo "$(timestamp) - Setting ownership ${ANSIBLE_VENV_DIR} => ubuntu:ubuntu"
  chown -R ubuntu:ubuntu "${ANSIBLE_VENV_DIR}"

  echo "$(timestamp) - Ansible installation completed"
fi

# --- Ensure ubuntu user's local Ansible dirs exist BEFORE running ansible-galaxy ---
USER_HOME="/home/ubuntu"
ANSIBLE_LOCAL_DIR="${USER_HOME}/.ansible"
echo "$(timestamp) - Ensuring ${ANSIBLE_LOCAL_DIR} exists with correct owner/perms before installing collections"
mkdir -p "${ANSIBLE_LOCAL_DIR}/tmp" || true
chown -R ubuntu:ubuntu "${ANSIBLE_LOCAL_DIR}"
chmod 700 "${ANSIBLE_LOCAL_DIR}"
# ensure ubuntu can create tmp
sudo -u ubuntu -H bash -c "mkdir -p '${ANSIBLE_LOCAL_DIR}/tmp' || true"

# Optional: install common collections (best-effort) as ubuntu user
echo "$(timestamp) - Installing community.general collection (best-effort as ubuntu user)"
# Run the galaxy install with the venv's ansible-galaxy binary under the ubuntu user
sudo -u ubuntu -H bash -c "${ANSIBLE_VENV_DIR}/bin/ansible-galaxy collection install community.general --force || true"

echo "$(timestamp) - Ensuring ${ANSIBLE_LOCAL_DIR} ownership/perms (final check)"
chown -R ubuntu:ubuntu "${ANSIBLE_LOCAL_DIR}"
chmod 700 "${ANSIBLE_LOCAL_DIR}"

echo "$(timestamp) - Permissions fixed for ${ANSIBLE_LOCAL_DIR}"
echo "$(timestamp) - Done. Ansible should be available via /usr/local/bin/ansible and /usr/local/bin/ansible-playbook"
exit 0