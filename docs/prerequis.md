# Prerequisites - Kubernetes on Proxmox with Terraform and Ansible

## Table of Contents

1. [System Requirements](#system-requirements)
2. [Infrastructure Prerequisites](#infrastructure-prerequisites)
3. [Proxmox Prerequisites](#proxmox-prerequisites)
4. [Local Environment Setup](#local-environment-setup)
5. [Software Dependencies](#software-dependencies)
6. [Network Configuration](#network-configuration)
7. [SSH Key Preparation](#ssh-key-preparation)
8. [Credentials and Authentication](#credentials-and-authentication)
9. [VM Template Preparation](#vm-template-preparation)
10. [Storage and Disk Requirements](#storage-and-disk-requirements)
11. [Pre-Deployment Checklist](#pre-deployment-checklist)
12. [Troubleshooting Prerequisites Issues](#troubleshooting-prerequisites-issues)

---

## System Requirements

### Proxmox VE Hypervisor

| Requirement | Specification | Notes |
|-------------|---------------|-------|
| **OS** | Proxmox VE 7.x or 8.x | Must be installed and operational |
| **Hardware** | x86-64 processor with virtualization support | Intel VT-x or AMD-V required |
| **RAM** | Minimum 64 GB total | For hosting 5 VMs (1×2GB + 1×4GB + 3×4GB) |
| **Storage** | Minimum 500 GB | For system + 5 VM disks + snapshots |
| **Network** | 1 Gbps or higher | For inter-node and inter-VM communication |
| **Management IP** | Static IP address | For Terraform API access |

### Local Development Machine

| Requirement | Specification | Notes |
|-------------|---------------|-------|
| **OS** | Linux, macOS, or Windows (WSL2) | Must support Terraform and Ansible |
| **Terraform** | >= 1.0 | IaC orchestration |
| **Ansible** | >= 2.9, recommended 2.13+ | Configuration management |
| **SSH Client** | OpenSSH or compatible | For remote VM access |
| **Git** | Latest stable | Version control and cloning the project |
| **Python** | 3.8+ | For Ansible and utilities |
| **Bash/Shell** | bash 4+ or compatible | For deployment scripts |

---

## Infrastructure Prerequisites

### Proxmox Cluster Configuration

#### 1. **Proxmox Node Name**
   - **Default Node**: `pve-node-01` (example, configured in `variables.tf`)
   - **Verify with**:
     ```bash
     pvesh get /nodes --output=json | jq '.[] | .node'
     ```
   - **Variable**: `target_node` in `variables.tf`

#### 2. **Proxmox Management Network**
   - Access to Proxmox Web UI and REST API
   - Default port: **8006** (HTTPS)
   - Example URL: `https://192.168.1.100:8006/` (replace with your Proxmox IP)
   - Network connectivity from local machine to Proxmox VE

#### 3. **Proxmox Storage Access**
   - Local storage pool for VM disks
   - Default: **"local"** (configured in `variables.tf`)
   - Minimum available space:
     - **System disk**: 50 GB per VM × 5 VMs = 250 GB
     - **Buffer/Snapshots**: 100+ GB
   - Verify storage:
     ```bash
     pvesh get /storage --output=json
     ```

#### 4. **Network Bridge Configuration**
   - **Bridge Name**: `vmbr0` (example, configured in `variables.tf`)
   - **Purpose**: VM network interface bridge
   - **Network Range**: `192.168.1.0/24` (example, configurable)
   - **Gateway**: `192.168.1.1` (example, configurable)
   - **VLAN Tag**: (optional, depends on your setup)
   - Verify bridge:
     ```bash
     ip link show vmbr0
     ```

### VM Host Resources

#### VMs to be Created

| VM Name | Role | CPUs | RAM | Storage | IP Address |
|---------|------|------|-----|---------|------------|
| `ansible-01` | Bastion/Control | 1 | 2 GB | 50 GB | 192.168.1.10 |
| `k8s-master-01` | Kubernetes Master | 2 | 4 GB | 50 GB | 192.168.1.11 |
| `k8s-worker-01` | Kubernetes Worker | 2 | 4 GB | 50 GB | 192.168.1.12 |
| `k8s-worker-02` | Kubernetes Worker | 2 | 4 GB | 50 GB | 192.168.1.13 |
| `k8s-worker-03` | Kubernetes Worker | 2 | 4 GB | 50 GB | 192.168.1.14 |

**Note**: Replace IP addresses with values from your actual network range

**Total Resources Required**:
- **CPUs**: 9 cores (or 5 with overcommit)
- **RAM**: 18 GB total
- **Storage**: 250 GB (minimum)

#### Resource Overallocation

Kubernetes can tolerate some resource overcommitment:
- 1:2 overcommit ratio is typical (allocate 2× more than physical available)
- Example: 64 GB physical RAM can support ~128 GB allocated across VMs
- Monitor with `top` or Proxmox dashboard

---

## Proxmox Prerequisites

### Proxmox API Access

#### 1. **API Token Creation**

**Create a new API token in Proxmox Web UI**:
1. Navigate to: `Proxmox Web UI` → `Datacenter` → `API Tokens`
2. Click "Add" button
3. Configure:
   - **User**: Select or create a user (e.g., `terraform@pve`)
   - **Token ID**: Give it a name (e.g., `terraform-token`)
   - **Expiration**: Set expiration date (or leave empty for no expiry)
   - **Privileges**: Leave default for now (will restrict later if needed)
4. **IMPORTANT**: Copy the **Token Value** immediately (shown only once)
   - Format: `USER@REALM!TOKENID=SECRET`
   - Example: `terraform@pve!terraform-token=abc123def456ghi789jkl012`

#### 2. **API Endpoint Configuration**

- **URL Format**: `https://PROXMOX_IP:8006/`
- **Example**: `https://0.0.0.0:8006/`
- **Verification**:
  ```bash
  curl -k https://51.75.54.137:8006/api2/json/version
  ```

#### 3. **SSL Certificate Consideration**

- **Default**: Proxmox uses self-signed certificates
- **Terraform Configuration**: `insecure = true` allows self-signed certs
- **Production**: Consider valid certificates for security

### Proxmox User Permissions

Ensure your API user has permissions to:
- **Create VMs** (Proxmox > Permissions > VM Creation)
- **Access Storage** (Proxmox > Permissions > Storage)
- **Read/Write Snippets** (for cloud-init templates)
- **SSH Access** (via `root` user, as configured in providers.tf)

**Verify permissions**:
```bash
pvesh get /access/users/terraform@pve --output=json
```

### Proxmox SSH Configuration

The Terraform provider connects to Proxmox via SSH for certain operations:

| Configuration | Value | Notes |
|---------------|-------|-------|
| **SSH User** | `root` | Configured in `providers.tf` |
| **SSH Port** | 22 (default) | Standard SSH port |
| **SSH Agent** | Enabled | Terraform uses SSH agent for authentication |
| **SSH Key** | Local machine key | Must be accessible to SSH agent |

**Setup SSH agent**:
- **Linux/macOS**: SSH agent usually runs by default
- **Windows WSL2**: Ensure SSH agent is running:
  ```bash
  eval $(ssh-agent -s)
  ssh-add ~/.ssh/id_rsa
  ```
- **Windows PowerShell**: Use Windows SSH service or WSL2

---

## Local Environment Setup

### Prerequisites Installation by OS

#### Linux (Ubuntu/Debian)

```bash
# Update package lists
sudo apt-get update

# Install Terraform
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
sudo apt-get install terraform

# Install Ansible
sudo apt-get install ansible

# Install SSH client
sudo apt-get install openssh-client

# Install Python 3 and pip
sudo apt-get install python3 python3-pip

# Install Git
sudo apt-get install git
```

#### macOS

```bash
# Using Homebrew
brew install terraform
brew install ansible
brew install openssh
brew install python3
brew install git

# Or using MacPorts
sudo port install terraform ansible openssh python39 git
```

#### Windows (WSL2 recommended)

```bash
# Install WSL2 first, then use Ubuntu/Debian steps above

# OR manually download and add to PATH:
# - Terraform: https://www.terraform.io/downloads
# - Ansible: pip install ansible
# - Git: https://git-scm.com/download/win
```

### Verification Commands

```bash
# Verify Terraform installation
terraform -v
# Expected: Terraform v1.x.x or higher

# Verify Ansible installation
ansible --version
# Expected: ansible 2.9+ or higher

# Verify SSH
ssh -V
# Expected: OpenSSH_x.x

# Verify Python
python3 --version
# Expected: Python 3.8 or higher

# Verify Git
git --version
# Expected: git version 2.x or higher
```

---

## Software Dependencies

### Terraform Providers

The following providers are required and will be auto-downloaded by Terraform:

| Provider | Version | Source | Role |
|----------|---------|--------|------|
| **proxmox** | 0.42.0 | `bpg/proxmox` | Proxmox API interaction |
| **tls** | ~> 4.0 | `hashicorp/tls` | SSH key generation |
| **local** | ~> 2.0 | `hashicorp/local` | Local file operations |
| **random** | ~> 3.4 | `hashicorp/random` | Random UUID generation |

**Auto-installation**:
```bash
cd /path/to/projet-terraform-k8s
terraform init  # Downloads and installs providers automatically
```

### Terraform Version Constraint

```hcl
terraform {
  required_version = ">= 1.0"
}
```

**Check your Terraform version**:
```bash
terraform version
```

### Ansible Collections

The Ansible playbook uses built-in modules; no special collections required.

**Optional**: Install ansible-core (minimal) or full Ansible distribution:
```bash
# Option 1: Full Ansible
pip install ansible

# Option 2: Minimal ansible-core
pip install ansible-core>=2.13

# Verify
ansible --version
```

### Kubernetes Components

These are **NOT** installed locally; they are deployed to VMs via:
- **Cloud-init** (Ubuntu package manager)
- **Ansible playbook** (kubeadm, kubectl)

**Installed on VMs**:
  - `containerd` 1.x
  - `kubeadm` 1.29.x
  - `kubectl` 1.29.x
  - `kubelet` 1.29.x
  - `Calico` CNI (configured for VXLAN overlay by default)

---

## Network Configuration

### IP Address Planning

#### Host Network (Proxmox)
- **Network Range**: `192.168.1.0/24` (example, adjust for your network)
- **Gateway**: `192.168.1.1` (example, adjust for your network)
- **CIDR Prefix**: `/24` (configurable)
- **Available IPs**: `192.168.1.1 - 192.168.1.254` (example range)

#### Assigned IPs (Default)

| Hostname | IP Address | Role |
|----------|-----------|------|
| ansible-01 | 192.168.1.10 | Bastion/Control |
| k8s-master-01 | 192.168.1.11 | Master |
| k8s-worker-01 | 192.168.1.12 | Worker |
| k8s-worker-02 | 192.168.1.13 | Worker |
| k8s-worker-03 | 192.168.1.14 | Worker |

#### Pod Network (Kubernetes Overlay)
- **Pod CIDR**: 10.233.64.0/18 (Calico IPPool configured by Ansible)
- **IPPool blockSize**: /26 (Calico will allocate /26 blocks to nodes by default)
- **CNI**: Calico (VXLAN overlay — Ansible creates an IPPool with vxlanMode: Always)

### Network Requirements

#### 1. **Connectivity Between VMs**
  - All VMs must reach each other via host network (192.168.1.0/24)
   - No firewall rules should block inter-VM traffic
   - Test with: `ping` between VMs

#### 2. **Connectivity to Proxmox Host**
   - VMs must reach Proxmox host network gateway
   - Required for cloud-init, package downloads, etc.

#### 3. **Internet Access**
   - VMs require outbound Internet access for:
     - Ubuntu package updates
     - Kubernetes image pulls
     - Container registry access (Docker Hub, etc.)
   - Required for cloud-init `apt-get update/install`

#### 4. **Local Machine to Proxmox**
   - Local Terraform machine must reach Proxmox API (port 8006)
   - Test with:
     ```bash
     curl -k https://PROXMOX_IP:8006/api2/json/version
     ```

#### 5. **DNS Resolution**
   - VMs hostname resolution (optional, but recommended)
   - Domain: `training.local` (configurable)
   - Each VM FQDN: `{name}.{domain}` (e.g., `ansible-01.training.local`)
   - Configure in local `/etc/hosts` (Linux/macOS) or `C:\Windows\System32\drivers\etc\hosts` (Windows):
    ```
    192.168.1.10 ansible-01.training.local ansible-01
    192.168.1.11 k8s-master-01.training.local k8s-master-01
    192.168.1.12 k8s-worker-01.training.local k8s-worker-01
    192.168.1.13 k8s-worker-02.training.local k8s-worker-02
    192.168.1.14 k8s-worker-03.training.local k8s-worker-03
    ```

### Port Requirements

| Service | Port | Protocol | From | To | Notes |
|---------|------|----------|------|-----|-------|
| Proxmox API | 8006 | HTTPS | Local machine | Proxmox host | Terraform access |
| SSH | 22 | TCP | Local machine | All VMs | SSH access |
| Kubernetes API | 6443 | HTTPS | All nodes + local | Master | K8s control plane |
| kubelet | 10250 | HTTPS | Master + nodes | Nodes | Node communication |
| etcd | 2379-2380 | TCP | Master | Master | State store |
| Calico VXLAN | 4789 | UDP | All nodes | All nodes | Calico VXLAN overlay (FELIX_VXLANPORT)
| Service NodePort | 30000-32767 | TCP/UDP | External | All nodes | Kubernetes services |

---

## SSH Key Preparation

### SSH Key Generation (Automatic via Terraform)

Terraform automatically generates SSH keys using the `tls_private_key` resource:

```hcl
resource "tls_private_key" "cluster" {
  algorithm = "ED25519"
}
```

**Behavior**:
- Generates an **ED25519** key pair (modern, efficient)
- Private key stored in `./secrets/ansible_cluster_id_ed25519` (local)
- Public key distributed to all VMs via cloud-init
- ED25519 is preferred over RSA for performance and security

### SSH Key Manual Setup (Optional)

If you prefer to use an **existing SSH key**:

#### 1. **Generate a Key (if you don't have one)**

```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ""
# Or RSA (legacy):
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
```

#### 2. **Store Public Key for Cloud-init**

The public key must be available to Terraform during `terraform apply`:
- Terraform reads it from the generated key
- Or you can provide it manually

#### 3. **SSH Agent Configuration**

Ensure SSH agent is running and your key is loaded:

**Linux/macOS**:
```bash
# Start SSH agent
eval $(ssh-agent -s)

# Add your key
ssh-add ~/.ssh/id_ed25519

# Verify
ssh-add -l  # List loaded keys
```

**Windows (WSL2)**:
```bash
# Same as Linux in WSL2 terminal
eval $(ssh-agent -s)
ssh-add ~/.ssh/id_ed25519
```

**Windows (PowerShell)**:
```powershell
# Ensure Windows SSH agent service is running
Get-Service ssh-agent | Start-Service -ErrorAction SilentlyContinue

# Add key (if using OpenSSH from Git or Windows SSH)
ssh-add C:\Users\YourUser\.ssh\id_ed25519
```

### SSH Key Storage

| Location | Purpose | Permissions |
|----------|---------|-------------|
| `./secrets/ansible_cluster_id_ed25519` | Private key (generated) | `0600` (rw-------) |
| `./secrets/` | Secret storage directory | Git-ignored |
| Local SSH agent | In-memory key | Required for auth |

**Important**: 
- Private key should **never** be committed to Git
- Directory `secrets/` should be in `.gitignore`
- Restrict file permissions: `chmod 0600 ./secrets/*`

---

## Credentials and Authentication

### Proxmox API Credentials

#### Required Variables

In `variables.tf` or `terraform.tfvars`:

```hcl
variable "proxmox_endpoint" {
  type    = string
  default = "https://51.75.54.137:8006/"
}

variable "api_token" {
  type      = string
  sensitive = true
  # Example: "terraform@pve!terraform-token=a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5"
}
```

#### How to Provide Credentials

**Option 1: terraform.tfvars File** (Recommended)

```bash
# Create file: terraform.tfvars
cat > terraform.tfvars << 'EOF'
proxmox_endpoint = "https://your:8006/"
api_token        = "terraform@pve!terraform-token=your-token"
EOF

# Restrict permissions
chmod 0600 terraform.tfvars
```

**Option 2: Environment Variables**

```bash
export PROXMOX_VE_ENDPOINT="https://your:8006"
export PROXMOX_VE_API_TOKEN="terraform@pve!terraform-token=your-token"

terraform plan
```

**Option 3: Command-Line Arguments**

```bash
terraform plan \
  -var="proxmox_endpoint=https://your:8006/" \
  -var="api_token=terraform@pve!terraform-token=..."
```

**Security Recommendations**:
- ✅ Use `terraform.tfvars` with `.gitignore` rule
- ✅ Use environment variables in CI/CD
- ❌ Avoid hardcoding in `.tf` files
- ❌ Never commit secrets to Git
- ✅ Mark sensitive variables with `sensitive = true`

### SSH Credentials

#### SSH User for VMs

Default SSH user for cloud-init:
```hcl
variable "ssh_user" {
  type    = string
  default = "ubuntu"
}
```

**Add to `terraform.tfvars` if needed**:
```hcl
ssh_user = "ubuntu"  # Must match cloud-init user
```

#### SSH Private Key Path

```hcl
variable "ssh_key_path" {
  type    = string
  default = "./secrets/ansible_cluster_id_ed25519"
}
```

**Ensure this file is accessible**:
- Generated automatically by Terraform (via `write_private_key.tf`)
- Permissions must be `0600`: `chmod 600 ./secrets/ansible_cluster_id_ed25519`
- SSH agent must have the key loaded

### Application-Level Credentials

#### Ansible Control Node

An optional `vm_user` variable can be used:
```hcl
variable "vm_user" {
  type      = string
  sensitive = true
  default   = "sysadmin"
}
```

This user is **not currently** configured via cloud-init (template uses root).
**Can be added** to `cloud-init/user_data.tpl` if needed for security.

---

## VM Template Preparation

### Ubuntu VM Template Requirements

The Terraform project expects a **pre-built Ubuntu VM template** in Proxmox.

#### Template Specifications

| Requirement | Specification | Notes |
|-------------|---------------|-------|
| **OS** | Ubuntu 20.04 LTS or 22.04 LTS | Standard cloud-init image |
| **Size** | 50+ GB system disk | Must match `system_disk.size` |
| **Cloud-init** | Enabled | Required for user-data injection |
| **SSH** | OpenSSH server installed | Pre-installed in Ubuntu images |
| **Tools** | Minimal (no Kubernetes) | Ansible installs K8s components |
| **Template Tag** | At least `["template"]` | Terraform filters by tag |

#### Template Location in Proxmox

**Template should be marked as template**:
1. In Proxmox Web UI → Virtual Machines
2. Right-click VM → Convert to Template
3. Add tags: `template`, `test` (configurable via `template_tag`)

#### VM Template Search in Terraform

```hcl
data "proxmox_virtual_environment_vms" "template" {
  filters = [{
    name   = "tags"
    values = ["template", var.template_tag]  # Matches both "template" AND "test"
  }]
}
```

**Default filter**: `["template", "test"]`
- Change `template_tag` variable if your template uses different tags

#### Creating a Template (if needed)

1. **Download Ubuntu cloud image** for Proxmox:
   ```bash
   cd /var/lib/vz/template/iso/
   wget https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img
   ```

2. **Create VM from image**:
   - Use Proxmox Web UI or CLI
   - Set VM ID, assign 50 GB disk
   - Leave unconfigured (cloud-init will handle)
   - Add tags: `template`, `test`

3. **Mark as Template**:
   - In Proxmox Web UI: Right-click VM → Convert to Template

4. **Verify**:
   ```bash
   pvesh get /nodes/lab-training-day/qemu --output=json | grep template
   ```

### Template Tag Configuration

**Modify if your template has different tags**:

```hcl
# In terraform.tfvars or -var flag:
template_tag = "prod"  # Instead of "test"

# Or in variables.tf if you want to change defaults
variable "template_tag" {
  default = "prod"
}
```

---

## Storage and Disk Requirements

### Storage Pool Configuration

#### Primary Storage (Local)

Default storage pool: **"local"**

```hcl
variable "system_disk" {
  type = object({
    storage = string
    size    = number
  })
  default = {
    storage = "local"
    size    = 50  # GB
  }
}
```

**Verify storage pool**:
```bash
pvesh get /storage --output=json | jq '.[] | select(.storage == "local")'
```

**Required capacity**:
- 5 VMs × 50 GB system disk = 250 GB
- Plus buffer for snapshots = +100 GB
- **Minimum**: 350 GB available in "local" storage

### Additional Disks (Optional)

If you need additional data disks per VM:

```hcl
variable "additionnal_disks" {
  type = list(object({
    storage = string
    size    = number
  }))
  default = []  # No additional disks by default
}
```

**Example with additional disks**:
```hcl
# In terraform.tfvars:
additionnal_disks = [
  {
    storage = "local"
    size    = 100  # 100 GB
  },
  {
    storage = "local"
    size    = 200  # 200 GB
  }
]
```

### Cloud-init Snippet Storage

Cloud-init templates are stored as **Proxmox snippets**:
- Location: Proxmox storage (usually "local")
- Path: `/var/lib/vz/snippets/`
- Created by: `proxmox_virtual_environment_file.cloud_init_*` resources

**Verify snippets**:
```bash
ls /var/lib/vz/snippets/ | grep cloud-init
```

### Disk Performance Considerations

| Factor | Recommendation | Impact |
|--------|---|---|
| **Storage Type** | SSD or NVMe | Faster VM boot, better I/O |
| **Filesystem** | ext4 or ZFS | ext4 simpler, ZFS has compression |
| **Cache Setting** | `writeback` | Better throughput (less safe) |
| **Disk Controller** | virtio-scsi | Better than IDE, less overhead |

---

## Pre-Deployment Checklist

### Infrastructure Checklist

- [ ] **Proxmox VE installed and running**
  - Accessible at: `https://PROXMOX_IP:8006/`
  - Version: 7.x or 8.x

- [ ] **Proxmox node available**
  - Node name: `pve-node-01` (example, use your actual node name)
  - Verify: `pvesh get /nodes`

- [ ] **Network bridge configured**
  - Bridge: `vmbr0` (example, use your actual bridge name)
  - Verify: `ip link show vmbr0`

- [ ] **Storage pool available**
  - Pool: `local` (or your configured pool)
  - Verify: `pvesh get /storage`
  - Free space: > 350 GB

- [ ] **API token created**
  - Format: `user@realm!tokenid=tokensecret`
  - Has required permissions

- [ ] **VM template prepared**
  - Ubuntu 20.04 LTS or 22.04 LTS
  - Cloud-init enabled
  - Tagged with `template` and `ubuntu` (adjust `template_tag` in variables if different)
  - System disk: 50 GB
  - Located at: `/var/lib/vz/template/qemu/` on Proxmox host

### Local Environment Checklist

- [ ] **Terraform installed**
  - Version: >= 1.0
  - Verify: `terraform -v`

- [ ] **Ansible installed**
  - Version: >= 2.9
  - Verify: `ansible --version`

- [ ] **SSH client configured**
  - SSH agent running
  - SSH key pair available
  - SSH key accessible: `~/.ssh/id_ed25519` or custom path

- [ ] **Git installed**
  - Verify: `git --version`

- [ ] **Python 3 installed**
  - Version: >= 3.8
  - Verify: `python3 --version`

- [ ] **Project cloned**
  - Location: `/path/to/projet-terraform-k8s`
  - Verify: `ls -la /path/to/projet-terraform-k8s/`

### Configuration Checklist

- [ ] **terraform.tfvars created**
  - Contains: `proxmox_endpoint`, `api_token`
  - Permissions: `0600`
  - Not committed to Git

- [ ] **SSH key available**
  - Path: `./secrets/ansible_cluster_id_ed25519` (or configured path)
  - Permissions: `0600`
  - Added to SSH agent: `ssh-add -l | grep ed25519`

- [ ] **.gitignore configured**
  - Includes: `terraform.tfvars`, `secrets/`, `.terraform/`
  - Verify: `cat .gitignore`

- [ ] **Network connectivity verified**
  - Proxmox reachable from local machine
  - Test: `curl -k https://PROXMOX_IP:8006/api2/json/version`
  - All planned IP addresses available

- [ ] **IP address conflicts checked**
  - No existing VMs using 192.168.1.10-14
  - No DHCP conflicts on subnet
  - Gateway 192.168.1.1 reachable

### Pre-Apply Verification

Before running `terraform apply`, verify with dry-run:

```bash
# Change to project directory
cd /path/to/projet-terraform-k8s

# Initialize Terraform
terraform init

# Validate configuration
terraform validate

# Plan the deployment (dry-run)
terraform plan -out=tfplan

# Review the plan output
# Check for any errors or unexpected changes
```

**Expected output**: Shows 5 VMs to be created + related resources

---

## Troubleshooting Prerequisites Issues

### Common Issues and Solutions

#### 1. **Terraform Provider Not Found**

**Error**:
```
Error: Provider hashicorp/proxmox not found
```

**Solution**:
```bash
# Run terraform init to download providers
terraform init

# Clear cache and reinitialize
rm -rf .terraform
terraform init
```

#### 2. **API Token Authentication Failed**

**Error**:
```
Error: invalid authentication data
```

**Solution**:
1. Verify token format: `user@realm!tokenid=secret`
2. Check token exists in Proxmox Web UI
3. Verify token hasn't expired
4. Test with curl:
   ```bash
   curl -k -H "Authorization: PVEAPIToken=<token>" \
     https://PROXMOX_IP:8006/api2/json/version
   ```

#### 3. **Network Bridge Not Found**

**Error**:
```
Error: bridge vmbr2 not found
```

**Solution**:
1. List available bridges on Proxmox:
   ```bash
   ip link show | grep vmbr
   ```
2. Update `network_bridge` variable to correct bridge name
3. Or create the bridge if missing:
   ```bash
   # In Proxmox
   ip link add vmbr2 type bridge
   ```

#### 4. **Storage Pool Not Found**

**Error**:
```
Error: storage local not found
```

**Solution**:
1. List available storage pools:
   ```bash
   pvesh get /storage
   ```
2. Update `system_disk.storage` variable to correct pool name

#### 5. **VM Template Not Found**

**Error**:
```
Error: no templates found
```

**Solution**:
1. Verify template exists in Proxmox:
   ```bash
   pvesh get /nodes/lab-training-day/qemu --output=json
   ```
2. Check template is marked as template (not regular VM)
3. Verify template has required tags:
   ```bash
   pvesh get /nodes/lab-training-day/qemu/VMID/config --output=json | grep tags
   ```
4. Update `template_tag` variable to match your template's tags

#### 6. **SSH Key Permission Denied**

**Error**:
```
Error: ssh: private key has wrong permissions
```

**Solution**:
```bash
# Fix SSH key permissions
chmod 0600 ./secrets/ansible_cluster_id_ed25519

# Verify
ls -la ./secrets/ansible_cluster_id_ed25519
# Should show: -rw------- (600)
```

#### 7. **SSH Agent Not Working**

**Error**:
```
Error: ssh: could not connect to SSH agent
```

**Solution**:

**Linux/macOS**:
```bash
# Start SSH agent
eval $(ssh-agent -s)

# Add key
ssh-add ~/.ssh/id_ed25519

# Verify
ssh-add -l
```

**Windows WSL2**:
```bash
# In WSL2 terminal
eval $(ssh-agent -s)
ssh-add ~/.ssh/id_ed25519
```

**Windows PowerShell**:
```powershell
# Start SSH agent service
Start-Service ssh-agent -ErrorAction SilentlyContinue

# Add key (if using OpenSSH)
ssh-add C:\Users\YourUser\.ssh\id_ed25519
```

#### 8. **Terraform Backend Not Configured**

**Error**:
```
Error: local.tfstate file not found
```

**Solution**:
```bash
# Run terraform init to create backend
terraform init

# Or manually create empty state file
touch terraform.tfstate
```

#### 9. **Variables Not Recognized**

**Error**:
```
Error: variable <var> not set
```

**Solution**:
1. Create `terraform.tfvars` file:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```
2. Or provide via environment:
   ```bash
   export TF_VAR_proxmox_endpoint="..."
   ```
3. Or via command-line:
   ```bash
   terraform plan -var="proxmox_endpoint=..."
   ```

#### 10. **DNS Resolution Issues**

**Error**:
```
Error: could not resolve proxmox host
```

**Solution**:
1. Test DNS resolution:
   ```bash
   nslookup PROXMOX_HOSTNAME
   dig PROXMOX_HOSTNAME
   ```
2. Use IP address instead of hostname in `proxmox_endpoint`
3. Configure `/etc/hosts` or DNS server entries

#### 11. **Network Timeouts**

**Error**:
```
Error: connection timeout to API
```

**Solution**:
1. Verify network connectivity:
   ```bash
   ping PROXMOX_IP
   telnet PROXMOX_IP 8006
   ```
2. Check firewall rules
3. Verify Proxmox service running:
   ```bash
   pvesh get /version
   ```

#### 12. **SSL Certificate Verification Error**

**Error**:
```
Error: certificate verify failed
```

**Solution**:
- Terraform is already configured with `insecure = true` in `providers.tf`
- If error persists, ensure curl works:
  ```bash
  curl -k https://PROXMOX_IP:8006/api2/json/version
  ```

### Verification Commands

```bash
# Proxmox connectivity
curl -k -H "Authorization: PVEAPIToken=<token>" \
  https://PROXMOX_IP:8006/api2/json/version

# Local Terraform
terraform -v
terraform init
terraform validate

# Local Ansible
ansible --version
ansible-inventory --list

# Local SSH
ssh-add -l
ssh -i ./secrets/ansible_cluster_id_ed25519 ubuntu@192.168.1.10

# Network
ping PROXMOX_IP
ping 192.168.1.1  # Or your gateway
traceroute 192.168.1.1
```

---

## References

- [Proxmox VE Documentation](https://pve.proxmox.com/wiki/Main_Page)
- [Proxmox Terraform Provider](https://registry.terraform.io/providers/bpg/proxmox/latest)
- [Terraform Documentation](https://www.terraform.io/docs)
- [Ansible Documentation](https://docs.ansible.com/)
- [Kubernetes Official Docs](https://kubernetes.io/docs/)
- [kubeadm Setup Guide](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/)
- [Containerd Documentation](https://github.com/containerd/containerd)
- [Calico CNI](https://github.com/projectcalico/calico)
- [cloud-init Documentation](https://cloud-init.io/)
- [SSH Best Practices](https://infosec.mozilla.org/guidelines/openssh)

---


