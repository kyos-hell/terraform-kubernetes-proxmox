# Scripts Documentation

## Overview

This project includes 4 helper scripts that automate critical infrastructure setup tasks. These scripts are idempotent and designed to work in automated environments (Terraform provisioners).

| Script | Purpose | Execution |
|--------|---------|-----------|
| `wait_for_ssh.sh` | Poll VMs until SSH is ready | Terraform provisioner |
| `install-ansible.sh` | Install Ansible control node | Remote via SSH |
| `generate_and_copy_ansible.sh` | Create inventory + copy playbooks | Local machine |
| `reboot_and_wait.sh` | Reboot VM and wait for cloud-init | Terraform provisioner |

---

## wait_for_ssh.sh

### Purpose

Ensures all VMs are accessible via SSH before attempting configuration management. Prevents "SSH connection refused" errors during orchestration.

### Usage

```bash
./scripts/wait_for_ssh.sh <timeout_seconds> <ssh_user> <ssh_key> <ip1> [ip2 ip3 ...]
```

### Parameters

| Parameter | Example | Description |
|-----------|---------|-------------|
| `timeout_seconds` | `600` | Maximum seconds to wait (typically 600s = 10 minutes) |
| `ssh_user` | `ubuntu` | Username for SSH login |
| `ssh_key` | `./secrets/ansible_cluster_id_ed25519` | Path to private SSH key |
| `ip1 [ip2...]` | `192.168.1.10 192.168.1.11` | Space-separated list of IPs to check |

### Example

```bash
# Wait up to 10 minutes for SSH on 5 hosts
./scripts/wait_for_ssh.sh 600 ubuntu ./secrets/ansible_cluster_id_ed25519 \
  192.168.1.10 \
  192.168.1.11 \
  192.168.1.12 \
  192.168.1.13 \
  192.168.1.14
```

### How It Works

1. **Initialization**
   - Calculates end time: `now + timeout_seconds`
   - Logs all target IPs

2. **Connection Loop** (for each IP)
   - Attempts SSH connection every 3 seconds
   - Uses `ssh -oBatchMode=yes -oStrictHostKeyChecking=no`
   - Short timeout (5s) to avoid hanging
   - Runs simple `exit` command to verify SSH works

3. **Success Criteria**
   - All IPs accept SSH connection
   - Command completes before timeout
   - Exit code: `0`

4. **Failure Scenarios**
   - Timeout reached → Exit code: `3`
   - SSH error → Exit code: `3`
   - Not enough parameters → Exit code: `2`

### Output

```
Waiting up to 600s for SSH on 5 hosts...
 - Scheduling wait for 192.168.1.10
 - Scheduling wait for 192.168.1.11
 - Scheduling wait for 192.168.1.12
 - Scheduling wait for 192.168.1.13
 - Scheduling wait for 192.168.1.14
Waiting for SSH ubuntu@192.168.1.10 ...
SSH OK: 192.168.1.10
Waiting for SSH ubuntu@192.168.1.11 ...
SSH OK: 192.168.1.11
...
All hosts are reachable via SSH.
```

### Terraform Integration

Used in `wait_and_run_ansible.tf`:

```hcl
resource "null_resource" "wait_for_vms" {
  provisioner "local-exec" {
    command = "${path.module}/scripts/wait_for_ssh.sh 600 ubuntu ${var.ssh_key_path} ${join(' ', values(module.vm[*].ip[0]))}"
  }
  depends_on = [module.vm]
}
```

### Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| Timeout error | VMs slow to boot | Increase timeout to 900s |
| "SSH OK" never appears | Network unreachable | Check network bridge, IP assignment |
| "Permission denied" | Wrong SSH key | Verify key matches public key in cloud-init |
| "Connection refused" | SSH service not running | Check cloud-init completed on VM |

---

## install-ansible.sh

### Purpose

Installs Ansible and dependencies on the control node in an idempotent way. Handles virtual environment setup and collection installation.

### Usage

```bash
# Via direct execution (sudo required)
sudo ./scripts/install-ansible.sh

# Via SSH provisioner
ssh -i key ubuntu@192.168.1.10 "sudo bash -s" < ./scripts/install-ansible.sh

# Via environment variable for specific version
ANSIBLE_VERSION=2.14.4 sudo ./scripts/install-ansible.sh
```

### Parameters

| Environment Variable | Example | Description |
|----------------------|---------|-------------|
| `ANSIBLE_VERSION` | `2.14.4` | (Optional) Pin specific version; omit for latest |

### What It Installs

```
Python 3 Virtual Environment
├── ansible (latest or pinned version)
├── pip (upgraded)
├── setuptools & wheel
└── community.general collection

System Wrapper Scripts
├── /usr/local/bin/ansible
└── /usr/local/bin/ansible-playbook

File Permissions
├── /opt/ansible-venv → ubuntu:ubuntu
└── /home/ubuntu/.ansible → ubuntu:ubuntu (700)
```

### Idempotent Design

The script safely runs multiple times:

1. **Skip redundant steps** if Ansible already present
2. **Always fix permissions** for venv and .ansible directory
3. **Always install collections** (with `--force` and error tolerance)
4. **No data loss** - existing configurations preserved

### Step-by-Step Process

```
1. Check if Ansible already installed in /opt/ansible-venv
   ├─→ YES: Skip installation, fix permissions, exit
   └─→ NO: Continue to next step

2. Update apt packages
   └─→ Install: python3-venv, python3-pip, build-essential, etc.

3. Create Python virtual environment at /opt/ansible-venv
   ├─→ Remove any stale venv
   ├─→ Create new venv
   └─→ Upgrade pip, setuptools, wheel

4. Install Ansible into venv
   └─→ If ANSIBLE_VERSION set: pip install ansible==X.Y.Z
       Else: pip install ansible (latest)

5. Create wrapper scripts in /usr/local/bin
   ├─→ /usr/local/bin/ansible
   └─→ /usr/local/bin/ansible-playbook

6. Set venv ownership: ubuntu:ubuntu

7. Ensure ubuntu user directories exist
   ├─→ /home/ubuntu/.ansible/tmp
   └─→ Set permissions (700)

8. Install collections as ubuntu user
   └─→ community.general (best-effort, ignores errors)

9. Fix final permissions for .ansible directory

10. Exit 0 (success)
```

### Output Example

```
2024-12-14T10:25:30Z - Starting ansible install
2024-12-14T10:25:31Z - Updating apt and installing prerequisites
Reading package lists... Done
Setting up python3-venv (3.10.12-1~22.04.2) ...
...
2024-12-14T10:25:45Z - Creating python venv at /opt/ansible-venv
2024-12-14T10:25:52Z - Installing latest ansible into venv
Collecting ansible
...
Successfully installed ansible-2.15.0
2024-12-14T10:25:58Z - Creating wrapper scripts in /usr/local/bin
2024-12-14T10:26:00Z - Setting ownership /opt/ansible-venv => ubuntu:ubuntu
2024-12-14T10:26:00Z - Installing community.general collection (best-effort)
Starting galaxy collection install process
Process install dependency map
...
2024-12-14T10:26:05Z - Done. Ansible should be available...
```

### Verification

```bash
# SSH to control node
ssh -i ./secrets/ansible_cluster_id_ed25519 ubuntu@192.168.1.10

# Check Ansible version
ansible --version
# Expected output:
# ansible [core 2.15.0]
#   config file = None
#   configured module search path = ['/home/ubuntu/.ansible/plugins/modules']
#   ...

# Check wrapper script
/usr/local/bin/ansible --version

# Check collection installed
ansible-galaxy collection list community.general
```

### Terraform Integration

Used in `ansible_install.tf`:

```hcl
resource "null_resource" "install_ansible" {
  provisioner "remote-exec" {
    inline = ["bash -s < ${path.module}/scripts/install-ansible.sh"]
    
    connection {
      type        = "ssh"
      user        = var.ssh_user
      private_key = file(var.ssh_key_path)
      host        = module.vm["ansible-01"].ip[0]
    }
  }
  depends_on = [null_resource.wait_for_vms]
}
```

### Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| "apt-get not found" | Wrong OS | Ensure Ubuntu image (not CentOS/Alpine) |
| "Permission denied" | Not running as sudo | Add `sudo` prefix to command |
| "Broken pipe" | SSH disconnected | Increase timeout, check network |
| Collection install fails | Offline environment | Ignore error (best-effort mode handles this) |
| `/usr/local/bin/ansible` not found | Installation incomplete | Run script again or check logs |

---

## generate_and_copy_ansible.sh

### Purpose

Generates dynamic Ansible inventory from Terraform outputs and copies playbooks/inventory to the control node via SCP.

### Usage

```bash
./scripts/generate_and_copy_ansible.sh <terraform_dir> <remote_user>@<ansible_ip> <remote_target_dir> <ssh_key>
```

### Parameters

| Parameter | Example | Description |
|-----------|---------|-------------|
| `terraform_dir` | `.` | Directory containing Terraform files |
| `remote_user@ansible_ip` | `ubuntu@192.168.1.10` | SSH login for control node |
| `remote_target_dir` | `/home/ubuntu/ansible` | Where to copy playbooks on remote |
| `ssh_key` | `./secrets/ansible_cluster_id_ed25519` | Private key for SSH |

### Example

```bash
./scripts/generate_and_copy_ansible.sh . ubuntu@192.168.1.10 /home/ubuntu/ansible \
  ./secrets/ansible_cluster_id_ed25519
```

### How It Works

```
1. Validate Parameters
   ├─→ Check all 4 parameters provided
   └─→ Check terraform and (jq or python3) available

2. Locate Terraform Directory
   ├─→ Verify dir exists
   └─→ Auto-detect if not found

3. Query Terraform State
   ├─→ Run: terraform -chdir=TF_DIR output -json vms
   └─→ Parse JSON output from terraform apply

4. Validate JSON
   ├─→ Try jq, fallback to python3
   └─→ Exit if JSON invalid

5. Generate inventory.ini
   ├─→ Parse terraform output
   ├─→ Extract hostname and IP
   ├─→ Create Ansible inventory format
   └─→ Write to: ./ansible/inventory.ini

6. Copy Files to Remote
   ├─→ Create /home/ubuntu/ansible/.tmp on remote
   ├─→ SCP entire ansible/ directory to .tmp
   └─→ Atomic move: mv .tmp ansible (replaces existing)

7. Upload SSH Key (Optional)
   └─→ If SSH_KEY provided: SCP to /home/ubuntu/.ssh/id_ansible
```

### Generated inventory.ini

**Input (Terraform output):**
```hcl
{
  "ansible-01": {
    "fqdn": "ansible-01.k8s.local",
    "ip": ["192.168.1.10"],
    "vm_id": 100
  },
  "k8s-master-01": {
    "fqdn": "k8s-master-01.k8s.local",
    "ip": ["192.168.1.11"],
    "vm_id": 101
  },
  ...
}
```

**Output (generated inventory.ini):**
```ini
[all]

ansible-01 ansible_host=192.168.1.10
k8s-master-01 ansible_host=192.168.1.11
k8s-worker-01 ansible_host=192.168.1.12
k8s-worker-02 ansible_host=192.168.1.13
k8s-worker-03 ansible_host=192.168.1.14

[all:vars]
ansible_python_interpreter=/usr/bin/python3
ansible_ssh_private_key_file=/home/ubuntu/.ssh/id_ansible
ansible_user=ubuntu
```

### Output Example

```
Querying terraform output 'vms' in .
Generating ./ansible/inventory.ini from Terraform output ...
Successfully wrote 187 bytes to ./ansible/inventory.ini
Uploading to ubuntu@192.168.1.10:/home/ubuntu/ansible...
Copying ansible/ recursively to remote...
Local: rsa AAAAB3Nza...
Remote: Receiving 5 files...
Successfully copied ansible directory to ubuntu@192.168.1.10:/home/ubuntu/ansible
```

### Requirements

**Local machine must have:**
- `terraform` binary in PATH
- `jq` (preferred) or `python3` for JSON parsing
- `ssh` and `scp` clients
- SSH key with permissions `0600`

**Remote control node must have:**
- SSH server running
- Ubuntu user accessible
- `/home/ubuntu` writable

### Terraform Integration

Used in `wait_and_run_ansible.tf`:

```hcl
resource "null_resource" "copy_ansible" {
  provisioner "local-exec" {
    command = "${path.module}/scripts/generate_and_copy_ansible.sh . ubuntu@${module.vm["ansible-01"].ip[0]} /home/ubuntu/ansible ${var.ssh_key_path}"
  }
  depends_on = [null_resource.install_ansible]
}
```

### Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| "terraform required in PATH" | terraform not installed | Install Terraform |
| "jq or python3 required" | Neither JSON parser available | Install jq or python3 |
| "terraform dir not found" | Wrong path provided | Use correct terraform directory |
| "terraform output -json vms failed" | terraform apply not run | Run `terraform apply` first |
| "SCP: Permission denied" | SSH key issues | Verify key permissions (0600) |
| "Atomic move failed" | Remote filesystem issues | Check remote disk space |

---

## reboot_and_wait.sh

### Purpose

Safely reboots a VM and waits for cloud-init to complete. Ensures VM is fully initialized before attempting configuration management.

### Usage

```bash
./scripts/reboot_and_wait.sh <vm_ip> <ssh_key> <ssh_user> [ssh_port] [cloudinit_timeout]
```

### Parameters

| Parameter | Default | Example | Description |
|-----------|---------|---------|-------------|
| `vm_ip` | (required) | `192.168.1.11` | IP address of VM to reboot |
| `ssh_key` | (required) | `./secrets/ansible_cluster_id_ed25519` | Private SSH key |
| `ssh_user` | `ubuntu` | `ubuntu` | SSH login username |
| `ssh_port` | `22` | `22` | SSH port number |
| `cloudinit_timeout` | `600` | `900` | Seconds to wait for cloud-init (max) |

### Example

```bash
# Standard reboot with default timeouts
./scripts/reboot_and_wait.sh 192.168.1.11 ./secrets/ansible_cluster_id_ed25519 ubuntu

# With extended cloud-init timeout (15 minutes)
./scripts/reboot_and_wait.sh 192.168.1.11 ./secrets/ansible_cluster_id_ed25519 ubuntu 22 900

# With custom SSH port
./scripts/reboot_and_wait.sh 192.168.1.11 ./secrets/ansible_cluster_id_ed25519 ubuntu 2222
```

### How It Works

```
1. Initialization
   ├─→ Validate parameters provided
   ├─→ Create log directory: .terraform_reboot_logs/
   └─→ Log file: reboot_192.168.1.11_YYYYMMDDTHHMMSSZ.log

2. Remove known_hosts entries
   ├─→ ssh-keygen -f ~/.ssh/known_hosts -R VM_IP
   └─→ ssh-keygen -f /root/.ssh/known_hosts -R VM_IP
       (Avoids "Host key changed" errors)

3. Trigger Reboot
   └─→ ssh -i KEY SUSER@IP "sudo reboot"
       (Connection may drop immediately)

4. Wait for SSH to Drop (60 seconds max)
   └─→ Poll every 1 second
       When SSH no longer responds → Step 5

5. Wait for SSH to Come Back (300 seconds max)
   ├─→ Poll every 2 seconds
   ├─→ When SSH responds → Step 6
   └─→ If timeout: Exit 1 (failure)

6. Wait for cloud-init to Complete
   ├─→ Command: cloud-init status --wait
   ├─→ Timeout: CLOUDINIT_TIMEOUT seconds (default 600s)
   ├─→ If timeout: Show last 200 lines of log
   └─→ If failed: Exit 3

7. Success
   └─→ Exit 0
```

### Log Output

```
2024-12-14T10:35:00Z - START reboot_and_wait for 192.168.1.11
2024-12-14T10:35:00Z - Removing existing known_hosts entries for 192.168.1.11 (local)
2024-12-14T10:35:00Z - Triggering reboot on 192.168.1.11 as ubuntu
2024-12-14T10:35:02Z - Waiting for SSH to drop...
2024-12-14T10:35:05Z - SSH is down (after 3s)
2024-12-14T10:35:05Z - Waiting for SSH to come back...
2024-12-14T10:35:25Z - SSH is back (after 18s)
2024-12-14T10:35:25Z - Waiting for cloud-init to finish on 192.168.1.11 (timeout 600s)...
2024-12-14T10:35:45Z - cloud-init reported finished (or returned) on 192.168.1.11
2024-12-14T10:35:45Z - Reboot+cloud-init wait completed for 192.168.1.11
2024-12-14T10:35:45Z - LOG saved to .terraform_reboot_logs/reboot_192.168.1.11_20241214T103500Z.log
```

### Terraform Integration

Used in `reboot_local_exec_with_script.tf`:

```hcl
resource "null_resource" "reboot_kubernetes_after_playbook" {
  provisioner "local-exec" {
    command = "${path.module}/scripts/reboot_and_wait.sh ${module.vm[key].ip[0]} ${var.ssh_key_path} ${var.ssh_user} 22 600"
  }
  depends_on = [null_resource.run_playbook]
}
```

### Exit Codes

| Code | Meaning | Resolution |
|------|---------|------------|
| 0 | Success | VM rebooted and cloud-init finished |
| 1 | SSH timeout | VM hung; check in Proxmox console |
| 2 | Missing parameter | Provide all 2-5 parameters |
| 3 | Cloud-init timeout | Check `/var/log/cloud-init.log` on VM |

### Log Location

All reboot logs stored in: `.terraform_reboot_logs/`

```bash
# View latest reboot log
tail -f .terraform_reboot_logs/reboot_*.log

# Search for error in all logs
grep -r "ERROR\|WARNING" .terraform_reboot_logs/
```

### Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| "SSH timeout waiting" | VM unresponsive | Check VM in Proxmox, verify network |
| "cloud-init timeout" | Cloud-init hanging | SSH and check `/var/log/cloud-init.log` |
| "Host key changed" | known_hosts stale | Script auto-removes; if persists, manual: `ssh-keygen -R IP` |
| "Permission denied (publickey)" | SSH key invalid | Verify key matches public key on VM |
| "Reboot command hangs" | SSH session stuck | Normal; timeout handles this after 60s |

### Performance Notes

**Typical timings:**
- SSH drop: 1-5 seconds
- SSH comeback: 15-30 seconds
- Cloud-init completion: 30-90 seconds
- **Total**: 1-2 minutes per VM

**Can be slow if:**
- Slow network (package downloads)
- Cloud-init has many tasks
- VM specs too low for workload

---

## Best Practices

### 1. Always Check terraform.tfvars

Before running scripts, ensure you have:

```bash
# Must exist and be readable
cat terraform.tfvars | grep -E "proxmox_endpoint|api_token"

# Must not expose secrets in logs
grep -r "terraform.tfvars" .gitignore
```

### 2. Use Example Files

Reference the output of `terraform output`:

```bash
terraform output -json vms | jq '.[] | .ip'
```

### 3. Monitor Script Execution

```bash
# Watch script output in real-time
./scripts/wait_for_ssh.sh 600 ubuntu ./secrets/id_key IP1 IP2 | tee wait_ssh.log

# Check exit code
echo $?  # 0 = success, non-0 = failure
```

### 4. Logs for Debugging

All scripts create detailed logs:

```bash
# Cloud-init logs on VM
ssh ubuntu@IP "sudo tail -f /var/log/cloud-init-output.log"

# Reboot logs locally
ls .terraform_reboot_logs/

# Terraform logs
export TF_LOG=DEBUG
terraform apply
```

### 5. Idempotency

All scripts safely run multiple times:

- `wait_for_ssh.sh` → Retries; no state
- `install-ansible.sh` → Skips if already installed
- `generate_and_copy_ansible.sh` → Overwrites inventory
- `reboot_and_wait.sh` → Always reboots

---

## Integration Summary

| Script | Called From | When | Purpose |
|--------|------------|------|---------|
| wait_for_ssh.sh | wait_and_run_ansible.tf | After VM creation | Ensure SSH ready |
| install-ansible.sh | ansible_install.tf | Before playbook | Setup control node |
| generate_and_copy_ansible.sh | wait_and_run_ansible.tf | Before playbook | Deploy inventory |
| reboot_and_wait.sh | reboot_local_exec_with_script.tf | After playbook | Final reboot |

---

## Security Considerations

⚠️ **Important:**

1. **SSH Keys**
   - Never commit keys to Git
   - Keep permissions: `chmod 600`
   - Store securely (`./secrets/` directory)

2. **API Tokens**
   - Use `terraform.tfvars` (gitignored)
   - Don't echo tokens in logs
   - Rotate regularly

3. **Script Permissions**
   - Mark scripts executable: `chmod +x scripts/*.sh`
   - Only trusted users should run scripts
   - Audit logs for sensitive data

4. **Cloud-init Data**
   - Snippets stored on Proxmox
   - Contains SSH public key + configuration
   - Delete snippets after deployment if sensitive

---

## References

- [Terraform Provisioners](https://www.terraform.io/language/resources/provisioners/syntax)
- [Ansible Documentation](https://docs.ansible.com/)
- [SSH Key Management](https://man.openssh.com/)
- [Cloud-init](https://cloud-init.io/)

---


**Tested On**: Ubuntu 20.04 LTS, Ubuntu 22.04 LTS
