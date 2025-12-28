# Terraform Variables — Reference Documentation

This document provides a comprehensive reference for all input variables in the root Terraform module. These variables control the provisioning of infrastructure on Proxmox VE and the configuration of the Kubernetes cluster.

## Table of Contents

- [Overview](#overview)
- [Variable Categories](#variable-categories)
- [Proxmox Configuration](#proxmox-configuration)
- [SSH Configuration](#ssh-configuration)
- [VM Configuration](#vm-configuration)
- [Storage Configuration](#storage-configuration)
- [Network Configuration](#network-configuration)
- [VM Definitions](#vm-definitions)
- [Output Control](#output-control)
- [Setting Variables](#setting-variables)
- [Variable Validation](#variable-validation)
- [Examples](#examples)

---

## Overview

Variables are defined in `variables.tf` and can be overridden via:

1. **terraform.tfvars** (file, recommended for lab/local)
2. **Command-line flags** (`-var=name=value`)
3. **Environment variables** (`TF_VAR_name=value`)
4. **Default values** (if defined in variables.tf)

All variables have sensible defaults suitable for a typical lab setup. Production deployments should override most values.

---

## Variable Categories

| Category | Variables | Purpose |
|----------|-----------|---------|
| **Proxmox** | endpoint, api_token, target_node | Connect to and target Proxmox infrastructure |
| **SSH** | ssh_key_path, ssh_user | VM access and authentication |
| **VM Config** | domain, vm_tags, template_tag, vm_user | VM naming, tagging, user management |
| **Storage** | system_disk, additionnal_disks | Disk sizing and placement |
| **Network** | network_bridge, network_prefix, gateway_ipv4 | VM networking setup |
| **VM List** | vms | Define all VMs to create (names, IPs, specs) |
| **Output** | write_private_key_local | Control local file generation |

---

## Proxmox Configuration

### proxmox_endpoint

**Type:** `string`  
**Sensitive:** No  
**Required:** Yes (has default, but should be overridden)

**Description:**  
Proxmox VE API endpoint URL (https protocol)

**Default:**
```hcl
"https://your-proxmox:8006/"
```

**Example (Override):**
```hcl
proxmox_endpoint = "https://192.168.1.100:8006/"
```

**Notes:**
- Must include protocol (`https://`)
- Must include port (usually `8006`)
- Can also be set via environment variable: `PROXMOX_VE_ENDPOINT`
- API requires HTTPS; self-signed certificates are accepted via Terraform provider config

**How to Find:**
1. Open Proxmox Web UI in browser (e.g., `https://192.168.1.100:8006/`)
2. Note the URL and port
3. Use that as the endpoint

---

### api_token

**Type:** `string`  
**Sensitive:** Yes (marked as sensitive, not logged)  
**Required:** Yes (no default)

**Description:**  
Authentication token for Proxmox API access

**Format:**
```
user@realm!tokenid=secret
```

**Example:**
```hcl
api_token = "terraform@pam!terraform-token=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
```

**⚠️ SECURITY WARNING:**
- **NEVER commit** this to Git (use .gitignore)
- **NEVER log** this value
- Store in `terraform.tfvars` with permissions `0600`
- Rotate every 3-6 months
- Delete in Proxmox Web UI when rotating

**How to Create:**
1. Login to Proxmox Web UI as root or privileged user
2. Navigate to **Datacenter → Permissions → API Tokens**
3. Click **Add**
4. Fill in:
   - **User:** root@pam (or your user)
   - **Token ID:** terraform-token
   - **Privilege Separation:** Enable if you want restricted permissions
5. Click **Add**
6. Copy the full token (you won't see it again)
7. Note the token in format: `user@realm!tokenid=secret`

**Environment Variable:**
```bash
export TF_VAR_api_token="terraform@pam!terraform-token=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
terraform apply
```

---

### target_node

**Type:** `string`  
**Sensitive:** No  
**Required:** No (has default)

**Description:**  
Name of the Proxmox node where VMs will be created

**Default:**
```hcl
"pve-node-01"  # Generic example
```

**Example (Override):**
```hcl
target_node = "pve-01"
```

**Notes:**
- This is the node **name** in Proxmox, not hostname
- All VMs will be created on this single node
- For multi-node setups, would need to extend the module

**How to Find:**
1. Open Proxmox Web UI
2. Navigate to **Datacenter → Nodes**
3. Note the node name in the list (e.g., "pve-01", "proxmox-lab", etc.)

---

### target_node_domain

**Type:** `string`  
**Sensitive:** No  
**Required:** No (optional)

**Description:**  
Domain name of the Proxmox node (optional, for hostname resolution)

**Default:**
```hcl
""  # Empty string (not used)
```

**Example (Override):**
```hcl
target_node_domain = "proxmox.local"
```

**Notes:**
- This variable is defined but not currently used in the main configuration
- Reserved for future use (e.g., DNS resolution of Proxmox node)
- Can be omitted or set to empty string

---

## SSH Configuration

### ssh_key_path

**Type:** `string`  
**Sensitive:** No  
**Required:** No (has default)

**Description:**  
Path to the SSH private key used for VM access

**Default:**
```hcl
"./secrets/ansible_cluster_id_ed25519"
```

**Example (Override):**
```hcl
ssh_key_path = "./secrets/my_key_ed25519"
```

**Notes:**
- Must be an **ED25519** private key (generated by Terraform's `tls_private_key` resource)
- Should be in **OpenSSH format**
- Must have permissions `0600` (readable only by owner)
- Should be in `.gitignore` (never commit to Git)
- Used for SSH provisioning and Ansible playbook execution

**How It's Generated:**
- Terraform's `tls_private_key` resource generates this automatically
- If `write_private_key_local = true`, it's written to this path
- If `write_private_key_local = false`, only stored in Terraform state

**Usage:**
```bash
# SSH to a VM
ssh -i ./secrets/ansible_cluster_id_ed25519 ubuntu@192.168.1.11

# Ansible playbook
ansible-playbook -i inventory.ini playbook.yml --private-key=./secrets/ansible_cluster_id_ed25519
```

---

### ssh_user

**Type:** `string`  
**Sensitive:** No  
**Required:** No (has default)

**Description:**  
Default SSH user for connecting to VMs

**Default:**
```hcl
"ubuntu"
```

**Example (Override):**
```hcl
ssh_user = "admin"
```

**Notes:**
- This is the OS user created by cloud-init on each VM
- Must exist on the VM before SSH connection works
- Used in Terraform provisioners and Ansible inventory
- Usually determined by the cloud-init configuration and base image

**Important:**
- If using Ubuntu images: typically `ubuntu`
- If using Debian images: typically `admin` or `debian`
- If using CentOS/RHEL: typically `centos` or `ec2-user`
- Match this to what cloud-init creates on your image

---

## VM Configuration

### domain

**Type:** `string`  
**Sensitive:** No  
**Required:** No (has default)

**Description:**  
DNS domain suffix for VM FQDNs

**Default:**
```hcl
"k8s.local"  # Generic example (was "training.local")
```

**Example (Override):**
```hcl
domain = "cluster.example.com"
```

**Notes:**
- Used to construct FQDN: `vm_name.domain` (e.g., `k8s-master-01.k8s.local`)
- Passed to cloud-init metadata
- Set as hostname on each VM
- Should match your network's DNS domain (or be a local domain for lab)

**For Lab Environments:**
- Use `.local` TLD (e.g., `k8s.local`, `lab.local`)
- Will not be registered in public DNS
- Requires local DNS or `/etc/hosts` entries for resolution

---

### vm_tags

**Type:** `list(string)`  
**Sensitive:** No  
**Required:** No (has default)

**Description:**  
Tags to apply to all created VMs in Proxmox

**Default:**
```hcl
["ubuntu"]
```

**Example (Override):**
```hcl
vm_tags = ["ubuntu", "k8s", "prod"]
```

**Notes:**
- Tags are used in Proxmox for VM organization and filtering
- All created VMs will have these tags
- Can be used for resource grouping and cost allocation
- Does not affect VM functionality, only Proxmox management

**Common Tags:**
- `ubuntu` — Ubuntu-based VMs
- `k8s` — Kubernetes cluster VMs
- `prod` — Production VMs
- `lab` — Lab/test VMs
- `managed-by-terraform` — For cost tracking

---

### template_tag

**Type:** `string`  
**Sensitive:** No  
**Required:** No (has default)

**Description:**  
Tag used to identify the VM template to clone from

**Default:**
```hcl
"template"  # Generic example
```

**Example (Override):**
```hcl
template_tag = "ubuntu-20.04"
```

**Notes:**
- Terraform data source `proxmox_virtual_environment_vms` uses this to find the template
- Template must have tags: `["template", "<value of template_tag>"]`
- All VMs are cloned from this template
- The template itself must be properly prepared:
  - Cloud-init enabled
  - Proper disk size
  - Tagged correctly in Proxmox

**How It Works:**
```hcl
data "proxmox_virtual_environment_vms" "template" {
  node_name = var.target_node
  tags      = ["template", var.template_tag]  # Looks for both tags
}
```

**To Create a Template:**
1. Create a VM with Ubuntu cloud image
2. Configure cloud-init support
3. Resize disk to desired size (50GB recommended)
4. Tag with `["template"]` in Proxmox
5. Tag with your custom tag (e.g., `["ubuntu-20.04"]`)
6. Set it as a template

---

### vm_user

**Type:** `string`  
**Sensitive:** Yes (marked as sensitive)  
**Required:** No (has default)

**Description:**  
Username to create via cloud-init on each VM

**Default:**
```hcl
"ubuntu"  # Generic example
```

**Example (Override):**
```hcl
vm_user = "adminuser"
```

**Notes:**
- This user is created by cloud-init during VM initialization
- Not the SSH user (that's `ssh_user` variable)
- Marked as sensitive to avoid logging
- Should have sudoers permissions for automation tasks
- Cloud-init must include logic to create this user and configure SSH

**Important:**
- Must match the user that cloud-init creates
- Must have passwordless sudo for Ansible playbooks
- SSH key distribution depends on this user's home directory

**Cloud-init Integration:**
In `cloud-init/user_data.tpl`:
```yaml
system_info:
  distro: ubuntu
users:
  - name: ${vm_user}
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    ssh-authorized-keys:
      - ${ssh_public_key}
```

---

## Storage Configuration

### system_disk

**Type:** `object({storage = string, size = number})`  
**Sensitive:** No  
**Required:** No (has default)

**Description:**  
System disk configuration (storage pool and size)

**Default:**
```hcl
{
  storage = "local"
  size    = 50  # GB
}
```

**Example (Override):**
```hcl
system_disk = {
  storage = "local-lvm"
  size    = 100
}
```

**Field Descriptions:**

| Field | Type | Example | Notes |
|-------|------|---------|-------|
| `storage` | string | `local` | Storage pool name in Proxmox |
| `size` | number | `50` | Disk size in GB |

**Storage Pool Options:**
- `local` — Default local storage
- `local-lvm` — LVM-backed storage (more flexible)
- Any custom pool configured in Proxmox

**Sizing Recommendations:**

| Role | Minimum | Recommended |
|------|---------|-------------|
| Ansible control node | 20GB | 30GB |
| Kubernetes master | 30GB | 50GB |
| Kubernetes worker | 30GB | 50GB |

**Notes:**
- Size must match or exceed the template's disk size
- Disk is automatically resized during VM creation
- Can be increased post-deployment via Proxmox
- Cannot be decreased (delete and recreate VM)

---

### additionnal_disks

**Type:** `list(object({storage = string, size = number}))`  
**Sensitive:** No  
**Required:** No (has default)

**Description:**  
Additional data disks to attach to VMs (for persistent data, etcd, etc.)

**Default:**
```hcl
[]  # Empty list (no additional disks)
```

**Example (Override):**
```hcl
additionnal_disks = [
  {
    storage = "local-lvm"
    size    = 100  # 100GB data disk
  },
  {
    storage = "local-lvm"
    size    = 50   # 50GB backup disk
  }
]
```

**Field Descriptions:**

| Field | Type | Example | Notes |
|-------|------|---------|-------|
| `storage` | string | `local-lvm` | Storage pool for this disk |
| `size` | number | `100` | Disk size in GB |

**Notes:**
- Additional disks are attached to **all** VMs (same list)
- Disks must be formatted and mounted manually (cloud-init/Ansible)
- Useful for persistent volumes, etcd storage, container registries
- Can be omitted or set to empty list if not needed

**Use Cases:**
- **Persistent volumes for Kubernetes:** Extra disk for local storage
- **etcd dedicated storage:** For production Kubernetes
- **Container registry:** Local Docker/container registry
- **Monitoring data:** Prometheus, Grafana persistent data

---

## Network Configuration

### network_bridge

**Type:** `string`  
**Sensitive:** No  
**Required:** No (has default)

**Description:**  
Proxmox bridge used for the main network interface on all VMs

**Default:**
```hcl
"vmbr0"  # Generic example (was "vmbr2")
```

**Example (Override):**
```hcl
network_bridge = "vmbr1"
```

**Notes:**
- This is the Proxmox bridge name, **not** the VM interface name
- All VMs connect to this bridge
- Must exist in Proxmox network configuration
- For multi-network setups, would need to extend the module

**Finding Available Bridges:**

SSH to Proxmox host and run:
```bash
ip link show | grep bridge
# or
cat /etc/network/interfaces | grep bridge
```

**Common Bridges:**
- `vmbr0` — First bridge (default)
- `vmbr1` — Second bridge
- `vmbr100` — VLAN bridge

**Network Configuration:**
Verify the bridge is configured:
```bash
# On Proxmox host
ip addr show vmbr0
# Should show an IP address and be UP
```

---

### network_prefix

**Type:** `number`  
**Sensitive:** No  
**Required:** No (has default)

**Description:**  
CIDR prefix length for VM network (subnet mask)

**Default:**
```hcl
24  # /24 = 255.255.255.0 (256 addresses)
```

**Example (Override):**
```hcl
network_prefix = 25  # /25 = 255.255.255.128 (128 addresses)
```

**Common Values:**

| Prefix | Netmask | Hosts | Use Case |
|--------|---------|-------|----------|
| 24 | 255.255.255.0 | 254 | Lab, small deployment |
| 25 | 255.255.255.128 | 126 | Medium deployment |
| 26 | 255.255.255.192 | 62 | Small deployment |
| 23 | 255.255.254.0 | 510 | Large deployment |

**Notes:**
- Must match the actual network in your infrastructure
- Determines how many VMs can exist on the same network
- Used in cloud-init network configuration
- Should match your physical network setup

**Example Network Planning:**

For `/24` network (192.168.1.0/24):
```
Network:     192.168.1.0
Gateway:     192.168.1.1
Usable:      192.168.1.2 - 192.168.1.254
Broadcast:   192.168.1.255

VMs:
- ansible-01:     192.168.1.10
- k8s-master-01:  192.168.1.11
- k8s-worker-01:  192.168.1.12
- k8s-worker-02:  192.168.1.13
- k8s-worker-03:  192.168.1.14
```

---

### gateway_ipv4

**Type:** `string`  
**Sensitive:** No  
**Required:** No (has default)

**Description:**  
Default IPv4 gateway for VM network

**Default:**
```hcl
"192.168.1.1"  # Generic example
```

**Example (Override):**
```hcl
gateway_ipv4 = "192.168.100.1"
```

**Notes:**
- This is the gateway IP on your physical network
- All VMs will use this as their default route
- Must be the actual router/gateway on your network
- Used in cloud-init network configuration

**Finding Your Gateway:**

On Linux/macOS:
```bash
ip route | grep default
# Shows: default via 192.168.1.1 dev eth0
```

On Windows:
```cmd
ipconfig
# Look for "Default Gateway" line
```

**Network Setup Example:**

```
Physical Network:
  - Network:  192.168.1.0/24
  - Gateway:  192.168.1.1 (your router)
  - Bridge:   vmbr0

Terraform Config:
  - network_bridge = "vmbr0"
  - gateway_ipv4 = "192.168.1.1"
  - network_prefix = 24
  - VM IPs: 192.168.1.10-14
```

---


## MetalLB — Playbook-Managed Address Range

This project does not expose a Terraform/Ansible variable for the MetalLB address pool. The MetalLB `IPAddressPool` is rendered directly by the Ansible playbook.

To change the MetalLB range, edit `ansible/playbook.yml` and modify the `addresses:` entry in the task named **"Créer la configuration MetalLB (IPAddressPool et L2Advertisement)"**. Example snippet in the playbook:

```yaml
spec:
  addresses:
  - 192.168.1.21-192.168.1.31
```

Notes:
- Ensure the chosen range is on the same L2 network as your nodes when using L2 mode.
- Avoid overlapping with DHCP or other static IP assignments.


## VM Definitions

### vms

**Type:** `list(object({name = string, ip = string, cpu = number, memory = number, role = string}))`  
**Sensitive:** No  
**Required:** No (has default)

**Description:**  
List of all VMs to create, with their specifications

**Default:**
```hcl
[
  {
    name   = "ansible-01"
    ip     = "192.168.1.10"
    cpu    = 1
    memory = 2048
    role   = "ansible"
  },
  {
    name   = "k8s-master-01"
    ip     = "192.168.1.11"
    cpu    = 2
    memory = 4096
    role   = "master"
  },
  {
    name   = "k8s-worker-01"
    ip     = "192.168.1.12"
    cpu    = 2
    memory = 4096
    role   = "worker"
  },
  {
    name   = "k8s-worker-02"
    ip     = "192.168.1.13"
    cpu    = 2
    memory = 4096
    role   = "worker"
  },
  {
    name   = "k8s-worker-03"
    ip     = "192.168.1.14"
    cpu    = 2
    memory = 4096
    role   = "worker"
  }
]
```

### VM Object Fields

| Field | Type | Required | Example | Notes |
|-------|------|----------|---------|-------|
| `name` | string | Yes | `k8s-master-01` | VM hostname (no dots or underscores) |
| `ip` | string | Yes | `192.168.1.11` | Static IPv4 address |
| `cpu` | number | Yes | `2` | Number of vCPU cores |
| `memory` | number | Yes | `4096` | Memory in MB |
| `role` | string | Yes | `master` | VM role/purpose (used by Ansible) |

### Field Details

**name**
- Becomes VM hostname
- Used in FQDN: `{name}.{domain}` (e.g., `k8s-master-01.k8s.local`)
- Should be DNS-safe (no spaces, special chars except `-`)
- Maximum 253 characters

**ip**
- Must be unique within the subnet
- Must be within the network defined by `network_bridge` and `network_prefix`
- Cloud-init configures static IP via DHCP reservation or netplan

**cpu**
- Number of vCPU cores
- Minimum: 1
- Recommended for Kubernetes master: 2
- Recommended for Kubernetes worker: 2-4
- Recommended for Ansible control: 1

**memory**
- RAM in MB
- Minimum: 512
- Recommended for Kubernetes master: 4096 (4GB)
- Recommended for Kubernetes worker: 4096-8192 (4-8GB)
- Recommended for Ansible control: 2048 (2GB)

**role**
- Identifies VM purpose (used by Ansible)
- Common roles:
  - `ansible` — Ansible control node
  - `master` — Kubernetes master/control-plane
  - `worker` — Kubernetes worker node
- Passed to Ansible inventory and playbook
- Determines which tasks run on which nodes

### VM Configuration Examples

**Minimal Cluster (3 VMs):**
```hcl
vms = [
  {
    name   = "k8s-master-01"
    ip     = "192.168.1.10"
    cpu    = 2
    memory = 4096
    role   = "master"
  },
  {
    name   = "k8s-worker-01"
    ip     = "192.168.1.11"
    cpu    = 2
    memory = 4096
    role   = "worker"
  },
  {
    name   = "k8s-worker-02"
    ip     = "192.168.1.12"
    cpu    = 2
    memory = 4096
    role   = "worker"
  },
]
```

**High-Resource Cluster (7 VMs):**
```hcl
vms = [
  {
    name   = "ansible-01"
    ip     = "192.168.1.10"
    cpu    = 4
    memory = 8192
    role   = "ansible"
  },
  {
    name   = "k8s-master-01"
    ip     = "192.168.1.11"
    cpu    = 4
    memory = 8192
    role   = "master"
  },
  {
    name   = "k8s-master-02"
    ip     = "192.168.1.12"
    cpu    = 4
    memory = 8192
    role   = "master"
  },
  {
    name   = "k8s-master-03"
    ip     = "192.168.1.13"
    cpu    = 4
    memory = 8192
    role   = "master"
  },
  {
    name   = "k8s-worker-01"
    ip     = "192.168.1.14"
    cpu    = 4
    memory = 8192
    role   = "worker"
  },
  {
    name   = "k8s-worker-02"
    ip     = "192.168.1.15"
    cpu    = 4
    memory = 8192
    role   = "worker"
  },
  {
    name   = "k8s-worker-03"
    ip     = "192.168.1.16"
    cpu    = 4
    memory = 8192
    role   = "worker"
  },
]
```

**Notes on VM Configuration:**
- Ensure IPs don't conflict with your network's DHCP range
- Reserve IPs for other infrastructure (gateway, DNS, etc.)
- Roles should match your infrastructure (master, worker, control)
- Names should be descriptive and follow naming conventions

---

## Output Control

### write_private_key_local

**Type:** `bool`  
**Sensitive:** No  
**Required:** No (has default)

**Description:**  
Control whether to write the generated SSH private key to the local filesystem

**Default:**
```hcl
true  # Write key locally
```

**Example (Override):**
```hcl
write_private_key_local = false  # Only store in state file
```

**Behavior:**

| Value | Behavior | Use Case |
|-------|----------|----------|
| `true` | Write key to `./secrets/ansible_cluster_id_ed25519` | Lab, local development |
| `false` | Only store in `terraform.tfstate` | CI/CD, secure environments |

**⚠️ Important:**

- **If `true`:** Key written to disk (must be gitignored, permissions 0600)
- **If `false`:** Key only in Terraform state (state file becomes critical)
- Either way, **never commit the key or state file to Git**

**Recommendation:**

- **Lab/Development:** Set to `true` for convenience
- **Production:** Set to `false` and use state encryption (Terraform Cloud, encrypted S3 backend)

**How to Retrieve Key (if `false`):**

If you set `write_private_key_local = false` but later need the key:

```bash
# Extract from state file
terraform state show tls_private_key.ansible

# Or use terraform console
terraform console
> tls_private_key.ansible.private_key_openssh
```

---

## Setting Variables

### Method 1: terraform.tfvars (Recommended for Lab)

Create `terraform.tfvars`:

```hcl
proxmox_endpoint = "https://192.168.1.100:8006/"
api_token        = "terraform@pam!terraform-token=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
target_node      = "pve-01"
domain           = "k8s.local"
network_bridge   = "vmbr0"
gateway_ipv4     = "192.168.1.1"

vms = [
  {
    name   = "ansible-01"
    ip     = "192.168.1.10"
    cpu    = 1
    memory = 2048
    role   = "ansible"
  },
  {
    name   = "k8s-master-01"
    ip     = "192.168.1.11"
    cpu    = 2
    memory = 4096
    role   = "master"
  },
  {
    name   = "k8s-worker-01"
    ip     = "192.168.1.12"
    cpu    = 2
    memory = 4096
    role   = "worker"
  },
  {
    name   = "k8s-worker-02"
    ip     = "192.168.1.13"
    cpu    = 2
    memory = 4096
    role   = "worker"
  },
  {
    name   = "k8s-worker-03"
    ip     = "192.168.1.14"
    cpu    = 2
    memory = 4096
    role   = "worker"
  }
]
```

**Secure it:**
```bash
chmod 0600 terraform.tfvars
# Verify in .gitignore
grep "terraform.tfvars" .gitignore
```

### Method 2: Command-line Flags

```bash
terraform apply \
  -var="proxmox_endpoint=https://192.168.1.100:8006/" \
  -var="api_token=terraform@pam!terraform-token=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" \
  -var="target_node=pve-01"
```

**Limitations:**
- Works for simple values
- Difficult for complex objects (vms list)
- Variables visible in shell history

### Method 3: Environment Variables

```bash
export TF_VAR_proxmox_endpoint="https://192.168.1.100:8006/"
export TF_VAR_api_token="terraform@pam!terraform-token=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
export TF_VAR_target_node="pve-01"

terraform apply
```

**Notes:**
- Prefix: `TF_VAR_` + variable name
- Works for all types
- Persists for session duration
- Good for CI/CD secrets

### Method 4: terraform.tfvars.example (Template)

Create `terraform.tfvars.example` (commit to Git):

```hcl
# NEVER commit terraform.tfvars — only this example file

proxmox_endpoint = "https://your-proxmox-ip:8006/"
api_token        = "user@realm!tokenid=token-secret"
target_node      = "your-proxmox-node-name"
domain           = "your-domain.local"
network_bridge   = "vmbr0"
gateway_ipv4     = "your-gateway-ip"

vms = [
  # ... VM definitions ...
]
```

**Usage:**
```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
```

---

## Variable Validation

### Type Checking

Terraform validates variable types before applying:

```hcl
# ✅ Correct
variable "cpu" {
  type = number
  default = 2
}
# Usage: cpu = 2

# ❌ Incorrect
cpu = "2"  # Error: string cannot be used as number
```

### Object Type Validation

For complex objects like `vms`:

```hcl
# ✅ Correct structure
vms = [
  {
    name   = "vm-name"
    ip     = "192.168.1.10"
    cpu    = 2
    memory = 4096
    role   = "master"
  }
]

# ❌ Missing required field
vms = [
  {
    name = "vm-name"
    # Missing: ip, cpu, memory, role
  }
]
# Error: missing required arguments: ip, cpu, memory, role
```

### Common Validation Errors

| Error | Cause | Solution |
|-------|-------|----------|
| `Error: Missing required argument` | Variable required but not provided | Set in terraform.tfvars or -var flag |
| `Error: Invalid type constraint` | Wrong variable type | Check variable definition and value type match |
| `Error: Invalid value for "cpu": number required` | Provided string instead of number | Use `cpu = 2` instead of `cpu = "2"` |
| `Error: Template validation failed` | Invalid CIDR or network config | Verify network_prefix and gateway_ipv4 match network |

---

## Examples

### Example 1: Basic Deployment

**terraform.tfvars:**
```hcl
proxmox_endpoint = "https://192.168.1.100:8006/"
api_token        = "terraform@pam!terraform-token=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
target_node      = "pve-01"
```

**Result:**
- Uses all other defaults
- Creates 5 VMs (ansible-01, master, 3 workers) on default network
- IPs: 192.168.1.10-14
- Domain: k8s.local

### Example 2: Custom Network

**terraform.tfvars:**
```hcl
proxmox_endpoint = "https://192.168.1.100:8006/"
api_token        = "terraform@pam!terraform-token=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
target_node      = "pve-01"

network_bridge   = "vmbr1"
gateway_ipv4     = "192.168.100.1"
network_prefix   = 25

vms = [
  {
    name   = "k8s-master"
    ip     = "192.168.100.10"
    cpu    = 4
    memory = 8192
    role   = "master"
  },
  {
    name   = "k8s-worker-01"
    ip     = "192.168.100.11"
    cpu    = 4
    memory = 8192
    role   = "worker"
  },
]
```

### Example 3: Minimal Setup (3 VMs)

**terraform.tfvars:**
```hcl
proxmox_endpoint = "https://192.168.1.100:8006/"
api_token        = "terraform@pam!terraform-token=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
target_node      = "pve-01"

vms = [
  {
    name   = "k8s-master"
    ip     = "192.168.1.10"
    cpu    = 2
    memory = 4096
    role   = "master"
  },
  {
    name   = "k8s-worker-01"
    ip     = "192.168.1.11"
    cpu    = 2
    memory = 4096
    role   = "worker"
  },
  {
    name   = "k8s-worker-02"
    ip     = "192.168.1.12"
    cpu    = 2
    memory = 4096
    role   = "worker"
  }
]
```

### Example 4: High-Availability Cluster

**terraform.tfvars:**
```hcl
proxmox_endpoint = "https://192.168.1.100:8006/"
api_token        = "terraform@pam!terraform-token=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
target_node      = "pve-01"

vms = [
  {
    name   = "ansible-01"
    ip     = "192.168.1.10"
    cpu    = 2
    memory = 4096
    role   = "ansible"
  },
  {
    name   = "k8s-master-01"
    ip     = "192.168.1.11"
    cpu    = 4
    memory = 8192
    role   = "master"
  },
  {
    name   = "k8s-master-02"
    ip     = "192.168.1.12"
    cpu    = 4
    memory = 8192
    role   = "master"
  },
  {
    name   = "k8s-master-03"
    ip     = "192.168.1.13"
    cpu    = 4
    memory = 8192
    role   = "master"
  },
  {
    name   = "k8s-worker-01"
    ip     = "192.168.1.14"
    cpu    = 4
    memory = 8192
    role   = "worker"
  },
  {
    name   = "k8s-worker-02"
    ip     = "192.168.1.15"
    cpu    = 4
    memory = 8192
    role   = "worker"
  },
  {
    name   = "k8s-worker-03"
    ip     = "192.168.1.16"
    cpu    = 4
    memory = 8192
    role   = "worker"
  },
]

system_disk = {
  storage = "local-lvm"
  size    = 100  # Larger disks for HA
}

write_private_key_local = false  # Use state encryption instead
```

---

## Related Documentation

- [terraform.md](terraform.md) — Terraform configuration and providers
- [modules.md](modules.md) — Module reference (proxmox_vm module)
- [cloud-init.md](cloud-init.md) — VM initialization and cloud-init templates
- [quickstart.md](quickstart.md) — Quick start guide

---

**Version:** 1.0
