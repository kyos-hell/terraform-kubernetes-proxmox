# Troubleshooting — Terraform + Ansible + Kubernetes Lab

This document is a consolidated troubleshooting guide collecting issues encountered during deployment, how to diagnose them, and reliable fixes to apply.

## Table of Contents

- [TL;DR](#tldr)
- [Issues Observed](#issues-observed)
- [Cloud-init Race Condition](#cloud-init-race-condition)
- [Terraform Parsing Issues](#terraform-parsing-issues)
- [SSH and Known Hosts](#ssh-and-known-hosts)
- [Quick Verification Checklist](#quick-verification-checklist)
- [Next Improvements](#next-improvements)

---

## TL;DR

**Main failure modes encountered:**

1. **Wrong line endings (CRLF/LF)** in Terraform provisioner scripts
2. **Cloud-init race condition** causing `/home/ubuntu/.ssh/id_ansible` to be root-owned
3. **SSH host key verification failures** due to incomplete `known_hosts` on control node
4. **Terraform reboot timeout** waiting for guest agent after requested reboot

**Reliable solution implemented:**

- ✅ Normalize all line endings (convert CRLF → LF)
- ✅ Use systemd oneshot service deployed via cloud-init to fix SSH permissions
- ✅ Use `scripts/reboot_and_wait.sh` to guarantee cloud-init completion before Terraform continues
- ✅ Pre-populate `known_hosts` on control node with all host keys
- ✅ Distribute Ansible public key to all worker nodes

---

## Issues Observed

### Issue 0: ArgoCD Pods Not Ready (v-0.0.3+)

**Symptom:**
```
Pending or CrashLoopBackOff pods in argocd namespace
argocd-server-* pods stuck in Pending
```

**Root Cause:**
- CRDs not fully established before deployment
- Insufficient cluster resources (CPU/Memory available)
- Network connectivity issues pulling images
- Webhook configurations not ready

**Solution:**
- Verify CRDs are installed: `kubectl api-resources | grep argocd`
- Check pod logs: `kubectl logs -n argocd -f <pod-name>`
- Ensure minimum 2GB free memory available on nodes
- Wait 2-5 minutes for controller pods to reach Running state
- Check events: `kubectl describe pod -n argocd <pod-name>`

**Implementation:**
```bash
# Full ArgoCD diagnostics
kubectl get pods -n argocd
kubectl describe pod -n argocd argocd-server-xxxxx
kubectl logs -n argocd argocd-server-xxxxx --tail=100
kubectl get events -n argocd --sort-by='.lastTimestamp'
```

---

### Issue 0b: MetalLB IPAddressPool Not Available (v-0.0.3+)

**Symptom:**
```
IPAddressPool remains in Pending status
LoadBalancer services stay in <pending>
```

**Root Cause:**
- Speaker pods not running
- L2Advertisement not configured
- IP range conflicts with existing network devices
- Network interface not properly configured

**Solution:**
- Verify speaker pods: `kubectl get pods -n metallb-system -l app.kubernetes.io/component=speaker`
- Check L2Advertisement: `kubectl get l2advertisement -n metallb-system`
- Verify IP range doesn't conflict: `ip addr show` on nodes
- Check controller logs: `kubectl logs -n metallb-system -f metallb-controller-xxxxx`

**Implementation:**
```bash
# Full MetalLB diagnostics
kubectl get pods -n metallb-system
kubectl get ipaddresspool -n metallb-system -o yaml
kubectl get l2advertisement -n metallb-system -o yaml
kubectl describe ipaddresspool -n metallb-system default
kubectl logs -n metallb-system -f metallb-controller-xxxxx
```

---

### Issue 1: Disk Resize Mismatch

**Symptom:**
- VM disk resize incomplete or slow I/O
- Filesystem shows incorrect size

**Root Cause:**
- Clone default size differs from target storage expectations
- Resize step not aligned with storage backend

**Solution:**
- Explicitly match system disk size to storage pool size
- Verify resize is completed before cloud-init continues

**Implementation:**
```hcl
system_disk = {
  storage = "local"
  size    = 50  # GB, must match template size
}
```

---

### Issue 2: Terraform VM Reboot Timeout

**Symptom:**
```
Error: Timeout waiting for guest agent to report status
```

**Root Cause:**
- Proxmox guest agent or network not ready when Terraform expects it
- Reboot option causes state transitions that cloud-init doesn't finish within timeout
- Terraform reports "ready" before cloud-init actually finishes

**Solution:**
- Remove explicit reboot from Terraform VM resource
- Use controlled reboot+wait sequence via `scripts/reboot_and_wait.sh`
- This avoids false "ready" signals from Proxmox

**Implementation:**
```hcl
# Don't do this:
resource "proxmox_virtual_environment_vm" "vm" {
  started = true  # Don't reboot here
  # ...
}

# Instead, use reboot_and_wait.sh after VM is created
null_resource "reboot_vm" {
  provisioner "local-exec" {
    command = "${path.module}/scripts/reboot_and_wait.sh ${vm_ip} ${ssh_key} ${ssh_user}"
  }
}
```

---

### Issue 3: SSH Key Indentation in Cloud-init

**Symptom:**
- Private key embedded in user_data template has incorrect indentation
- SSH key file is malformed on guest

**Root Cause:**
- Multi-line interpolation in Terraform template requires exact indentation
- String replacement introduces incorrect newlines

**Solution:**
- Use proper Terraform formatting expression for multi-line strings:

```hcl
ssh_priv_indented = each.value.role == "ansible" ? 
  format("%s%s", "      ", 
    replace(tls_private_key.ansible.private_key_openssh, "\n", "\n      ")
  ) : ""
```

This properly indents each line of the private key when inserted into user_data YAML.

---

## Cloud-init Race Condition

### Observed Problem

**Symptom:**
```bash
$ ls -la /home/ubuntu/.ssh/
-rw------- 1 root   root      3434 Dec 14 10:23 id_ansible
```

The SSH key file is owned by `root:root` instead of `ubuntu:ubuntu`, causing:
- Ansible SSH connection failures
- Permission denied when ubuntu tries to use the key
- Intermittent failures (sometimes works, sometimes fails)

### Why It Happened

Cloud-init runs in multiple phases:

1. **cloud-init-local** (early, before networking)
2. **cloud-init** (after networking, root user)
3. **cloud-final** (final, runs user scripts)

Our initial deployment wrote the SSH key as root during the cloud-init phase. Later phases expected the `ubuntu` user to own it, but:
- Ownership changes might run before the file exists
- Cloud-init could re-run modules and reset ownership
- Different Ubuntu images have different timing

### What We Tried

| Approach | Result | Issue |
|----------|--------|-------|
| Systemd oneshot at boot | Worked but flaky | Race if cloud-init re-runs |
| `After=cloud-final.target` | Better | Still subject to timing issues |
| Numeric UID in cloud-init | Robust | Not portable across image versions |

### Final Solution: Defensive Systemd Oneshot

Deploy a systemd service via cloud-init that:
1. Waits for ubuntu user to exist
2. Fixes `.ssh` ownership and permissions
3. Populates a minimal `known_hosts`

**Cloud-init user_data snippet:**

```yaml
write_files:
  - path: /usr/local/bin/fix-ssh-owner.sh
    owner: root:root
    permissions: '0755'
    content: |
      #!/bin/sh
      # Wait for ubuntu user to exist, then fix .ssh ownership and permissions
      for i in $(seq 1 120); do
        id ubuntu >/dev/null 2>&1 && break || sleep 1
      done
      
      mkdir -p /home/ubuntu/.ssh || true
      chown -R ubuntu:ubuntu /home/ubuntu/.ssh || true
      chmod 700 /home/ubuntu/.ssh || true
      
      if [ -f /home/ubuntu/.ssh/id_ansible ]; then
        chmod 600 /home/ubuntu/.ssh/id_ansible || true
        chown ubuntu:ubuntu /home/ubuntu/.ssh/id_ansible || true
      fi
      
      # Populate known_hosts defensively for master node
      ssh-keyscan -H 192.168.1.11 >> /home/ubuntu/.ssh/known_hosts 2>/dev/null || true
      chown ubuntu:ubuntu /home/ubuntu/.ssh/known_hosts || true

  - path: /etc/systemd/system/fix-ssh-owner.service
    owner: root:root
    permissions: '0644'
    content: |
      [Unit]
      Description=Fix /home/ubuntu/.ssh ownership and permissions
      After=cloud-final.target network.target local-fs.target
      Wants=network-online.target

      [Service]
      Type=oneshot
      ExecStart=/usr/local/bin/fix-ssh-owner.sh
      RemainAfterExit=yes

      [Install]
      WantedBy=cloud-final.target

runcmd:
  - systemctl daemon-reload
  - systemctl enable fix-ssh-owner.service
  - systemctl start fix-ssh-owner.service
```

**Why this works:**
- ✅ Simple to deploy (just cloud-init write_files)
- ✅ Runs late (After=cloud-final.target) to ensure ubuntu user exists
- ✅ Idempotent (safe to run multiple times)
- ✅ Fixes most permission issues

**Why we still use reboot+wait:**
Because this is a mitigation, we added a robust reboot+wait sequence (see below) to guarantee the guest finishes cloud-init and the systemd service runs before Terraform continues.

### Reboot and Wait Script

**Purpose:** Safely reboot a VM and wait for cloud-init to complete

**Location:** `scripts/reboot_and_wait.sh`

**Usage:**
```bash
./scripts/reboot_and_wait.sh <VM_IP> <SSH_KEY> [SSH_USER] [SSH_PORT] [CLOUDINIT_TIMEOUT]
```

**Example:**
```bash
./scripts/reboot_and_wait.sh 192.168.1.11 ./secrets/ansible_cluster_id_ed25519 ubuntu 22 600
```

**What it does:**
1. Remove stale known_hosts entries (prevents "Host key changed" error)
2. Trigger reboot via SSH
3. Wait for SSH to drop (max 60s)
4. Wait for SSH to come back (max 300s)
5. Wait for cloud-init status --wait (max CLOUDINIT_TIMEOUT)
6. Log all output to `.terraform_reboot_logs/reboot_IP_*.log`

**Script:**

```bash
#!/usr/bin/env bash
set -euo pipefail

# Usage: reboot_and_wait.sh <VM_IP> <SSH_KEY_PATH> <SSH_USER> [SSH_PORT] [CLOUDINIT_TIMEOUT_SECONDS]
VM_IP="${1:-}"
SSH_KEY="${2:-}"
SSH_USER="${3:-ubuntu}"
SSH_PORT="${4:-22}"
CLOUDINIT_TIMEOUT="${5:-600}"

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

# Remove stale known_hosts entries
ssh-keygen -f "${HOME}/.ssh/known_hosts" -R "${VM_IP}" >>"$LOGFILE" 2>&1 || true
ssh-keygen -f "/root/.ssh/known_hosts" -R "${VM_IP}" >>"$LOGFILE" 2>&1 || true

echo "$(timestamp) - Triggering reboot on ${VM_IP} as ${SSH_USER}" | tee -a "$LOGFILE"
ssh ${SSH_OPTS} -i "${SSH_KEY}" "${SSH_USER}@${VM_IP}" "sudo reboot" >>"$LOGFILE" 2>&1 || true

# Wait for SSH to drop
echo "$(timestamp) - Waiting for SSH to drop..." | tee -a "$LOGFILE"
for i in $(seq 1 60); do
  if ssh ${SSH_OPTS} -i "${SSH_KEY}" "${SSH_USER}@${VM_IP}" "true" >/dev/null 2>&1; then
    sleep 1
  else
    echo "$(timestamp) - SSH is down (after ${i}s)" | tee -a "$LOGFILE"
    break
  fi
done

# Wait for SSH to come back
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

# Wait for cloud-init to finish
echo "$(timestamp) - Waiting for cloud-init to finish (timeout ${CLOUDINIT_TIMEOUT}s)..." | tee -a "$LOGFILE"
if ssh ${SSH_OPTS} -i "${SSH_KEY}" "${SSH_USER}@${VM_IP}" \
   "command -v timeout >/dev/null 2>&1 && timeout ${CLOUDINIT_TIMEOUT} sudo cloud-init status --wait || sudo cloud-init status --wait" \
   >>"$LOGFILE" 2>&1; then
  echo "$(timestamp) - cloud-init finished on ${VM_IP}" | tee -a "$LOGFILE"
else
  # Check status and dump logs
  if ssh ${SSH_OPTS} -i "${SSH_KEY}" "${SSH_USER}@${VM_IP}" "sudo cloud-init status --long" >>"$LOGFILE" 2>&1; then
    echo "$(timestamp) - cloud-init status checked after failure; proceed" | tee -a "$LOGFILE"
  else
    echo "$(timestamp) - WARNING: cloud-init did not finish within ${CLOUDINIT_TIMEOUT}s" | tee -a "$LOGFILE"
    ssh ${SSH_OPTS} -i "${SSH_KEY}" "${SSH_USER}@${VM_IP}" \
      "sudo tail -n 200 /var/log/cloud-init.log || true" >>"$LOGFILE" 2>&1 || true
    echo "$(timestamp) - Exiting with error due to cloud-init timeout" | tee -a "$LOGFILE"
    exit 3
  fi
fi

echo "$(timestamp) - Reboot+cloud-init wait completed for ${VM_IP}" | tee -a "$LOGFILE"
exit 0
```

**Integration with Terraform:**

```hcl
resource "null_resource" "reboot_and_wait" {
  for_each = local.vms_map

  provisioner "local-exec" {
    command = "${path.module}/scripts/reboot_and_wait.sh ${module.vm[each.key].ip} ${var.ssh_key_path} ${var.ssh_user}"
  }

  depends_on = [module.vm]
}
```

---

## Terraform Parsing Issues

### Problems Encountered

#### 1. Invalid Terraform References in local-exec

**Symptom:**
```
Error: Invalid reference
  |
  | resource "null_resource" "example":
  |   provisioner "local-exec" {
  |     command = <<-EOT
  |       for ip in ${var.ips}
  |       EOT
  |   }
|
This object does not have an attribute named "ips"
```

**Root Cause:**
- Terraform tries to parse `${...}` as Terraform interpolations
- Shell `${...}` patterns are evaluated by Terraform, not the shell
- This breaks shell variable substitution

**Solution:**
- Use `$${var_name}` to escape the `$` for shell (one level up)
- Or build the command in a local and avoid complex interpolations
- Or use base64-encoded scripts

```hcl
# ❌ DON'T
local-exec {
  command = "for ip in ${var.ips}; do echo $ip; done"
}

# ✅ DO (escape for shell)
local-exec {
  command = "for ip in ${var.ips}; do echo $$ip; done"
}

# ✅ DO (use locals, simpler)
locals {
  ip_list = join(" ", var.ips)
}
local-exec {
  command = "for ip in ${local.ip_list}; do true; done"
}
```

#### 2. CRLF Line Endings

**Symptom:**
```
set: pipefail: nom d'option non valable
bash: syntax near '(' 
```

**Root Cause:**
- Files have Windows line endings (CRLF, `\r\n`)
- Bash interprets `\r` as a character, breaking syntax

**Solution:**
- Convert all files to LF (Unix line endings)
- Check and normalize before deploying

```bash
# Convert CRLF to LF
dos2unix terraform/*.tf scripts/*.sh

# Or with sed
sed -i 's/\r$//' terraform/*.tf scripts/*.sh

# Verify (should output nothing)
grep -l $'\r' terraform/*.tf scripts/*.sh
```

#### 3. Shell History Expansion

**Symptom:**
```
bash: !": event not found
```

**Root Cause:**
- Unescaped `!` in shell commands triggers history expansion
- Especially problematic in heredocs with special characters

**Solution:**
- Escape `!` as `\!` or use `set +H` to disable history expansion
- Avoid complex heredocs; use base64 instead

```bash
# ❌ DON'T (history expansion fails)
cat << 'EOF'
if [ $? != 0 ]; then
  echo "Failed!"
fi
EOF

# ✅ DO (escape exclamation)
cat << 'EOF'
if [ $? != 0 ]; then
  echo "Failed\!"
fi
EOF

# ✅ DO (disable history)
set +H
# ... heredoc ...
set -H
```

### Best Practices

| Practice | Reason |
|----------|--------|
| **Normalize EOLs first** | Prevents `\r` in scripts breaking bash |
| **Use short local-exec commands** | Easier to read, less error-prone |
| **Build commands in locals** | Terraform can evaluate once, shell gets clean string |
| **Use base64 for complex scripts** | Avoids all quoting/interpolation issues |
| **Set `set -euo pipefail`** | Fails fast on errors, helps catch issues |

---

## SSH and Known Hosts

### Problem: Host Key Verification Failed

**Symptom:**
```
FAILED - not reachable: "Host key verification failed for ansible-01 from k8s-master-01"
```

**Root Cause:**
- `known_hosts` on control node (`ansible-01`) is incomplete or missing
- Some host entries missing ECDSA/ED25519 keys
- Control node's identity key not authorized on worker nodes

### Solution 1: Pre-populate known_hosts

**Script:** `scripts/generate_and_copy_ansible.sh` can generate known_hosts before running playbook

**Manual approach:**

```bash
# SSH to control node
ssh -i ./secrets/ansible_cluster_id_ed25519 ubuntu@192.168.1.10

# Populate known_hosts with all host keys
for ip in 192.168.1.11 192.168.1.12 192.168.1.13 192.168.1.14; do
  ssh-keyscan -t rsa,ecdsa,ed25519 $ip >> ~/.ssh/known_hosts
done

# Verify
cat ~/.ssh/known_hosts
```

**Terraform approach:**

```hcl
resource "null_resource" "populate_known_hosts" {
  provisioner "local-exec" {
    command = <<-EOT
      ansible_ip="${local.ansible_ip}"
      ssh_opts="-oBatchMode=yes -oStrictHostKeyChecking=no -oConnectTimeout=5 -i ${var.ssh_key_path}"
      
      # Create temp file with host keys
      temp_hosts=$(mktemp)
      for ip in ${join(" ", [for vm in var.vms : vm.ip if vm.role != "ansible"])}; do
        ssh-keyscan -t rsa,ecdsa,ed25519 $ip >> $temp_hosts 2>/dev/null || true
      done
      
      # Copy to control node
      scp $ssh_opts $temp_hosts ubuntu@$ansible_ip:/tmp/known_hosts_update
      
      # Append to known_hosts on control node
      ssh $ssh_opts ubuntu@$ansible_ip "cat /tmp/known_hosts_update >> ~/.ssh/known_hosts && sort -u ~/.ssh/known_hosts > ~/.ssh/known_hosts.tmp && mv ~/.ssh/known_hosts.tmp ~/.ssh/known_hosts"
      
      rm -f $temp_hosts
    EOT
  }
  
  depends_on = [module.vm]
}
```

### Solution 2: Distribute Public Key to Workers

**Ensure all nodes can SSH each other:**

```hcl
resource "null_resource" "distribute_pubkey" {
  for_each = { for vm in var.vms : vm.name => vm if vm.role != "ansible" }

  provisioner "local-exec" {
    command = <<-EOT
      ssh_key="${var.ssh_key_path}"
      ssh_user="${var.ssh_user}"
      pub_key_path="${var.ssh_key_path}.pub"
      
      if [ -f "$pub_key_path" ]; then
        pub_key=$(cat "$pub_key_path")
        ssh -oBatchMode=yes -oStrictHostKeyChecking=no -i "$ssh_key" \
          "$ssh_user@${each.value.ip}" \
          "echo '$pub_key' >> ~/.ssh/authorized_keys && sort -u ~/.ssh/authorized_keys > ~/.ssh/authorized_keys.tmp && mv ~/.ssh/authorized_keys.tmp ~/.ssh/authorized_keys"
      fi
    EOT
  }

  depends_on = [module.vm, null_resource.reboot_and_wait]
}
```

### Solution 3: Ansible Configuration

**In ansible.cfg:**

```ini
[defaults]
host_key_checking = False      # Disable for bootstrap (accept new keys)
# OR
host_key_file = ~/.ssh/known_hosts

[ssh_connection]
ssh_args = -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
```

**Or in playbook:**

```yaml
- name: Configure SSH
  hosts: all
  gather_facts: false
  tasks:
    - name: Scan and add host keys
      delegate_to: localhost
      run_once: true
      local_action:
        module: shell
        cmd: |
          for ip in {{ groups['all'] | join(' ') }}; do
            ssh-keyscan -t rsa,ecdsa,ed25519 $ip >> ~/.ssh/known_hosts 2>/dev/null || true
          done
```

---

## Quick Verification Checklist

### Pre-Deployment

- [ ] Convert line endings: `dos2unix terraform/*.tf scripts/*.sh`
- [ ] Verify no CRLF: `grep -r $'\r' . --exclude-dir=.git --exclude-dir=.terraform`
- [ ] Make scripts executable: `chmod +x scripts/*.sh`
- [ ] Create terraform.tfvars with correct values
- [ ] Verify SSH key permissions: `chmod 0600 secrets/ansible_cluster_id_ed25519`

### Post-Deployment

- [ ] Verify SSH key ownership on control node:
  ```bash
  ssh -i ./secrets/ansible_cluster_id_ed25519 ubuntu@192.168.1.10 \
    "stat -c '%U:%G %a %n' /home/ubuntu/.ssh/id_ansible"
  # Should show: ubuntu:ubuntu 600 /home/ubuntu/.ssh/id_ansible
  ```

- [ ] Verify known_hosts populated:
  ```bash
  ssh -i ./secrets/ansible_cluster_id_ed25519 ubuntu@192.168.1.10 \
    "cat ~/.ssh/known_hosts | wc -l"
  # Should show > 0
  ```

- [ ] Test SSH from control to workers:
  ```bash
  ssh -i ./secrets/ansible_cluster_id_ed25519 ubuntu@192.168.1.10 \
    "ssh -i ~/.ssh/id_ansible ubuntu@192.168.1.11 'hostname'"
  # Should show: k8s-master-01
  ```

- [ ] Check cloud-init logs on all VMs:
  ```bash
  ssh -i ./secrets/ansible_cluster_id_ed25519 ubuntu@192.168.1.11 \
    "sudo cloud-init status"
  # Should show: done
  ```

### Re-running Specific Terraform Steps

If deployment partially fails, re-run specific targets:

```bash
# Reboot all VMs and wait for cloud-init
terraform apply -target='null_resource.reboot_and_wait'

# Populate known_hosts
terraform apply -target='null_resource.populate_known_hosts'

# Distribute public key
terraform apply -target='null_resource.distribute_pubkey'

# Run Ansible playbook
terraform apply -target='null_resource.run_playbook'
```

---

## Next Improvements

### Code Organization

- ✅ Move long shell logic into `scripts/` directory
- ✅ Call short one-liner `local-exec` from Terraform
- ✅ Makes scripts testable outside Terraform

### CI/CD Integration

- Add linting: `shellcheck scripts/*.sh`
- Add CRLF check: `git diff --cached | grep -P "^\+.*\r$"` (detects Windows EOL)
- Add syntax validation: `terraform validate` in CI

### Robustness

- Implement exponential backoff for SSH retries (instead of fixed sleep)
- Add metrics collection (reboot duration, cloud-init timing)
- Document expected timing for different image sizes/types

### Security

- Use encrypted backend for Terraform state (S3 + KMS, Terraform Cloud, etc.)
- Rotate SSH keys periodically (every 6-12 months)
- Rotate Proxmox API tokens (every 3-6 months)
- Implement audit logging for infrastructure changes

### Automation

- Build a `Makefile` with targets: `make validate`, `make plan`, `make apply`, `make destroy`
- Implement GitOps workflow (automatically apply on Git push)
- Add post-deployment health checks (curl API endpoints, verify cluster health)

---

## References

- [Cloud-init Documentation](https://cloud-init.io/)
- [Terraform Local-exec Provisioner](https://www.terraform.io/language/resources/provisioners/local-exec)
- [Proxmox API Provider (bpg/proxmox)](https://registry.terraform.io/providers/bpg/proxmox/latest/docs)
- [SSH Known Hosts](https://man.openbsd.org/ssh_config#known_hosts)
- [Bash Troubleshooting](https://www.gnu.org/software/bash/manual/html_node/The-Set-Builtin.html)
- See [scripts.md](scripts.md) for script references
- See [terraform.md](terraform.md) for Terraform configuration details

---

**Version:** 1.0
