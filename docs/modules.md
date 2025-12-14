# Terraform Modules Documentation

## Table of Contents

1. [Overview](#overview)
2. [Module Structure](#module-structure)
3. [proxmox_vm Module](#proxmox_vm-module)
4. [Module Usage](#module-usage)
5. [Input Variables](#input-variables)
6. [Outputs](#outputs)
7. [Module Design Patterns](#module-design-patterns)
8. [Advanced Usage](#advanced-usage)
9. [Troubleshooting](#troubleshooting)
10. [Best Practices](#best-practices)

---

## Overview

This project uses Terraform modules to encapsulate reusable infrastructure components. The primary module is **`proxmox_vm`**, which provides a standardized interface for creating Proxmox virtual machines with consistent configuration across the Kubernetes cluster.

**Key Benefits of Modularization:**

- ✅ **Code Reusability** — Single module definition, multiple VM instantiations
- ✅ **Consistency** — All VMs created with identical configuration logic
- ✅ **Maintainability** — Updates to VM configuration in one place affect all VMs
- ✅ **Testability** — Module can be tested independently
- ✅ **Scalability** — Easy to add/remove VMs by adjusting input variable list

---

## Module Structure

### Directory Layout

```
modules/
└── proxmox_vm/
    ├── main.tf                      # VM resource definition
    ├── variables.tf                 # Input variable declarations
    ├── outputs.tf                   # Output value declarations
    ├── required_providers_fix.tf    # Provider version constraints
    └── README.md                    # (Optional) module documentation
```

### Module Location

Modules are stored in the `modules/` directory at the repository root. The root module (`/`) references the `proxmox_vm` module via:

```hcl
module "vm" {
  source   = "./modules/proxmox_vm"
  for_each = local.vms_map
  ...
}
```

---

## proxmox_vm Module

### Purpose

The `proxmox_vm` module abstracts the complexity of provisioning a Proxmox virtual machine. It handles:

- VM cloning from a template
- Network configuration (IP, gateway, CIDR)
- CPU and memory allocation
- Disk management (system + additional disks)
- Cloud-init initialization (user-data, metadata)
- VM tagging and metadata

### Resource Hierarchy

```
proxmox_virtual_environment_vm "this"
  ├── cpu { cores, type, sockets }
  ├── memory { dedicated }
  ├── network_device { bridge, model }
  ├── disk (system) { interface, storage, size }
  ├── dynamic disk (additional) { interface, storage, size }
  ├── clone { vm_id from template }
  ├── initialization { cloud-init data, IP config }
  └── lifecycle { ignore_changes policy }
```

### Module File Details

#### `main.tf`

Defines the main Proxmox VM resource with the following configuration:

```hcl
resource "proxmox_virtual_environment_vm" "this" {
  name      = var.fqdn                    # VM name (FQDN)
  node_name = var.node_name               # Proxmox node
  on_boot   = true                        # Auto-start on node reboot

  agent { enabled = true }                # Proxmox guest agent
  tags = var.tags                         # Organizational tags

  cpu {
    type    = "x86-64-v2-AES"            # CPU model (host-compatible)
    cores   = var.cpu                     # Number of cores
    sockets = 1                           # Number of sockets
  }

  memory {
    dedicated = var.memory                # RAM in MB
  }

  network_device {
    bridge = var.network_bridge           # Proxmox bridge (e.g., vmbr0)
    model  = "virtio"                     # Virtio for performance
  }

  disk {
    interface    = "scsi0"                # System disk (SCSI)
    iothread     = true                   # Enable IO threading
    datastore_id = var.system_disk.storage
    discard      = "ignore"               # Discard policy
    size         = var.system_disk.size
  }

  dynamic "disk" {
    for_each = var.additionnal_disks      # Additional data disks
    content {
      interface    = "scsi${1 + disk.key}"
      iothread     = true
      datastore_id = disk.value.storage
      discard      = "ignore"
      file_format  = "raw"
      size         = disk.value.size
    }
  }

  clone {
    vm_id = var.template_vm               # Clone from template
  }

  initialization {
    datastore_id      = "local"
    interface         = "ide2"            # Cloud-init device
    user_data_file_id = var.cloud_user_file_id
    meta_data_file_id = var.cloud_meta_file_id
    ip_config {
      ipv4 {
        address = "${var.ip}/${var.network_prefix}"
        gateway = var.gateway_ipv4
      }
    }
  }

  lifecycle {
    ignore_changes = [
      network_device,                     # Ignore post-boot changes
      started,
      disk[0].iothread,
      disk[0].discard,
    ]
  }

  boot_order    = ["scsi0"]               # Boot from system disk
  scsi_hardware = "virtio-scsi-single"    # SCSI controller type
}
```

**Key Design Decisions:**

| Decision | Rationale |
|----------|-----------|
| CPU model `x86-64-v2-AES` | Host-compatible, modern CPU features |
| `iothread = true` | Better disk I/O performance |
| `discard = "ignore"` | Avoid thin-provisioning issues in lab |
| `clone` block | Template-based deployment (fast) |
| `initialization` via cloud-init | Automated first-boot configuration |
| `lifecycle.ignore_changes` | Prevent drift when network changes post-deployment |

#### `variables.tf`

Declares 15 input variables used by the module:

| Variable | Type | Required | Description |
|----------|------|----------|-------------|
| `name` | string | ✅ | VM short name (for reference) |
| `fqdn` | string | ✅ | Fully qualified domain name (actual VM name in Proxmox) |
| `ip` | string | ✅ | IPv4 address (e.g., 192.168.1.11) |
| `cpu` | number | ✅ | Number of CPU cores (e.g., 2) |
| `memory` | number | ✅ | Dedicated RAM in MB (e.g., 4096) |
| `role` | string | ✅ | VM role (e.g., "master", "worker", "ansible") |
| `template_vm` | number | ✅ | Proxmox VM ID of template to clone |
| `node_name` | string | ✅ | Proxmox node name (e.g., "pve-node-01") |
| `network_bridge` | string | ✅ | Proxmox bridge (e.g., "vmbr0") |
| `system_disk` | object | ✅ | System disk config: { storage, size } |
| `cloud_user_file_id` | string | ✅ | Cloud-init user-data snippet file ID |
| `cloud_meta_file_id` | string | ✅ | Cloud-init metadata snippet file ID |
| `network_prefix` | number | ✅ | CIDR prefix length (e.g., 24 for /24) |
| `gateway_ipv4` | string | ✅ | IPv4 gateway (e.g., 192.168.1.1) |
| `additionnal_disks` | list(object) | ❌ | Additional data disks (default: []) |
| `tags` | list(string) | ❌ | Proxmox tags (default: ["ubuntu"]) |

#### `outputs.tf`

Exports three outputs from the VM resource:

| Output | Type | Description |
|--------|------|-------------|
| `vm_id` | number | Proxmox VM ID (internal identifier) |
| `fqdn` | string | Fully qualified domain name |
| `ip` | list(string) | List of IPv4 addresses assigned to VM |

**Example Output Usage:**

```hcl
# Access from root module
module.vm["k8s-master-01"].vm_id      # Returns Proxmox VM ID
module.vm["k8s-master-01"].fqdn       # Returns "k8s-master-01.k8s.local"
module.vm["k8s-master-01"].ip         # Returns ["192.168.1.11"]
```

#### `required_providers_fix.tf`

Specifies Terraform provider constraints for the module:

```hcl
terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.42.0"
    }
  }
}
```

**Purpose:** Ensures the module uses compatible provider versions. This constraint is validated when the module is instantiated.

---

## Module Usage

### Basic Usage (from root module)

In `vms.tf` at the repository root:

```hcl
locals {
  vms_map = { for vm in var.vms : vm.name => vm }
}

module "vm" {
  source   = "./modules/proxmox_vm"
  for_each = local.vms_map

  name               = each.value.name
  fqdn               = "${each.value.name}.${var.domain}"
  ip                 = each.value.ip
  cpu                = each.value.cpu
  memory             = each.value.memory
  role               = each.value.role
  template_vm        = data.proxmox_virtual_environment_vms.template.vms[0].vm_id
  node_name          = var.target_node
  network_bridge     = var.network_bridge
  system_disk        = var.system_disk
  cloud_user_file_id = proxmox_virtual_environment_file.cloud_user_config[each.key].id
  cloud_meta_file_id = proxmox_virtual_environment_file.cloud_meta_config[each.key].id

  network_prefix = var.network_prefix
  gateway_ipv4   = var.gateway_ipv4
  tags           = var.vm_tags
}
```

### for_each Loop

The module uses `for_each` to create multiple VM instances from a single source definition:

```hcl
for_each = local.vms_map  # Map: { "ansible-01" => {...}, "k8s-master-01" => {...}, ... }
```

**Benefits:**
- ✅ Each VM gets a unique key in state: `module.vm["ansible-01"]`
- ✅ VMs can be added/removed by modifying `var.vms`
- ✅ Easy to target individual VMs: `terraform apply -target=module.vm["k8s-master-01"]`

### Input Variable Flow

```
var.vms (list of VM definitions)
    ↓
locals.vms_map (converted to map for for_each)
    ↓
module.vm[each.key] (one module instance per VM)
    ↓
proxmox_virtual_environment_vm.this (actual VM created in Proxmox)
```

---

## Input Variables

### Variable Definitions

All variables are defined in `modules/proxmox_vm/variables.tf`:

```hcl
variable "name" {
  type = string
}

variable "fqdn" {
  type = string
}

variable "ip" {
  type = string
}

variable "cpu" {
  type = number
}

variable "memory" {
  type = number
}

variable "role" {
  type = string
}

variable "template_vm" {
  type = number
}

variable "node_name" {
  type = string
}

variable "network_bridge" {
  type = string
}

variable "system_disk" {
  type = object({
    storage = string
    size    = number
  })
}

variable "cloud_user_file_id" {}

variable "cloud_meta_file_id" {}

variable "network_prefix" {
  type = number
}

variable "gateway_ipv4" {
  type = string
}

variable "additionnal_disks" {
  type    = list(object({ storage = string, size = number }))
  default = []
}

variable "tags" {
  type    = list(string)
  default = ["ubuntu"]
}
```

### Variable Descriptions (for Documentation)

Consider adding descriptions to improve clarity:

```hcl
variable "fqdn" {
  type        = string
  description = "Fully qualified domain name for the VM (used as Proxmox VM name)"
}

variable "system_disk" {
  type = object({
    storage = string
    size    = number
  })
  description = "System disk configuration (storage datastore and size in GB)"
}
```

---

## Outputs

### Available Outputs

The module exports three outputs that can be consumed by the root module:

```hcl
output "vm_id" {
  value       = proxmox_virtual_environment_vm.this.vm_id
  description = "Proxmox VM ID (numeric identifier)"
}

output "fqdn" {
  value       = proxmox_virtual_environment_vm.this.name
  description = "Fully qualified domain name of the VM"
}

output "ip" {
  value       = proxmox_virtual_environment_vm.this.ipv4_addresses
  description = "List of IPv4 addresses assigned to the VM"
}
```

### Output Usage from Root Module

In `outputs.tf` at the repository root:

```hcl
output "vms" {
  value = { for k, m in module.vm : k => {
    fqdn = m.fqdn
    ip   = m.ip
    id   = m.vm_id
  } }
  description = "Map of VM name => { fqdn, ip, id }"
}
```

This aggregates all module outputs into a single root module output available via `terraform output vms`.

---

## Module Design Patterns

### 1. for_each Pattern

**Pattern:** Using `for_each` to create multiple instances from a single module definition.

**Advantage:** 
- Declarative: what you see in code is what gets created
- Keyed by VM name, making it easy to target specific VMs

**Example:**
```hcl
module "vm" {
  for_each = local.vms_map
  source   = "./modules/proxmox_vm"
  ...
}

# Reference specific VM
module.vm["k8s-master-01"].vm_id

# Or iterate over all
[for name, vm in module.vm : vm.ip]
```

### 2. Object Variables for Complex Configuration

**Pattern:** Using `object()` type for grouping related configuration.

**Example:**
```hcl
variable "system_disk" {
  type = object({
    storage = string  # Proxmox datastore
    size    = number  # Size in GB
  })
}

# Usage
disk {
  datastore_id = var.system_disk.storage
  size         = var.system_disk.size
}
```

**Benefit:** Cleaner than separate variables; groups related config together.

### 3. Dynamic Blocks for Optional Lists

**Pattern:** Using `dynamic` block to iterate over optional list variables.

**Example:**
```hcl
dynamic "disk" {
  for_each = var.additionnal_disks  # Empty list by default
  content {
    interface    = "scsi${1 + disk.key}"
    datastore_id = disk.value.storage
    size         = disk.value.size
  }
}
```

**Benefit:** Supports 0, 1, or many additional disks without code duplication.

### 4. Lifecycle Policies to Manage Drift

**Pattern:** Using `lifecycle.ignore_changes` to prevent Terraform from fighting with external changes.

**Example:**
```hcl
lifecycle {
  ignore_changes = [
    network_device,    # Changed post-deployment by Proxmox
    started,           # VM state changes outside Terraform
    disk[0].iothread,  # Not managed after VM creation
    disk[0].discard,
  ]
}
```

**Benefit:** Prevents unnecessary updates when Proxmox or cloud-init modify these attributes.

---

## Advanced Usage

### Creating a VM with Additional Disks

If `var.additionnal_disks` is populated, the module automatically creates additional SCSI disks:

**Root module configuration:**
```hcl
module "vm" {
  for_each = local.vms_map
  source   = "./modules/proxmox_vm"

  # ... other variables ...

  additionnal_disks = [
    { storage = "local", size = 100 },  # 100 GB data disk
    { storage = "local", size = 200 },  # 200 GB data disk
  ]
}
```

**Result:**
- System disk: `scsi0` (size from `system_disk`)
- Data disk 1: `scsi1` (100 GB)
- Data disk 2: `scsi2` (200 GB)

### Module Customization

To customize module behavior, edit `modules/proxmox_vm/main.tf`:

**Example: Change CPU Model**
```hcl
cpu {
  type    = "host"      # Use host CPU directly
  cores   = var.cpu
  sockets = 1
}
```

**Example: Add Memory Ballooning**
```hcl
memory {
  dedicated = var.memory
  floating  = true      # Enable memory ballooning
}
```

**Example: Add vNIC Parameters**
```hcl
network_device {
  bridge = var.network_bridge
  model  = "virtio"
  mtu    = 9000         # Jumbo frames
}
```

### Module Testing

To test the module in isolation:

```bash
# Navigate to module directory
cd modules/proxmox_vm

# Initialize Terraform with module
terraform init

# Validate module
terraform validate

# Format module files
terraform fmt -recursive
```

---

## Troubleshooting

### Module State Issues

**Problem:** Module resource not found in state.

**Solution:**
```bash
# Verify module instance exists
terraform state list | grep "module.vm"

# Inspect specific module resource
terraform state show module.vm[\"k8s-master-01\"]
```

### Variable Type Mismatch

**Problem:** Error: `attribute must be a string, got map`

**Cause:** Incorrect variable type or missing conversion.

**Solution:**
```hcl
# Check variable type
variable "system_disk" {
  type = object({        # ✅ Correct
    storage = string
    size    = number
  })
}

# NOT:
# system_disk = "local"  # ❌ String instead of object
```

### Dynamic Block Not Expanding

**Problem:** Additional disks not created.

**Solution:**
```hcl
# Verify additionnal_disks is provided
module "vm" {
  ...
  additionnal_disks = [
    { storage = "local", size = 100 }
  ]  # ✅ Not empty list
}

# Check Terraform plan
terraform plan | grep "dynamic"
```

### Module Source Path Issues

**Problem:** Error: `Could not find a module with source`

**Solution:**
```hcl
# Verify relative path is correct
source = "./modules/proxmox_vm"  # ✅ Relative to root module

# NOT:
# source = "modules/proxmox_vm"  # ❌ Missing ./
```

### VM Clone Failures

**Problem:** Template VM not found when cloning.

**Solution:**
```bash
# Verify template VM exists
terraform plan | grep "template_vm"

# Check data source
terraform state show data.proxmox_virtual_environment_vms.template
```

---

## Best Practices

### 1. Keep Modules Focused

- ✅ **Good:** Module creates one type of resource (VMs)
- ❌ **Bad:** Module creates VMs, networks, and storage simultaneously

The `proxmox_vm` module follows this principle—it only creates VMs.

### 2. Use Descriptive Variable Names

```hcl
# ✅ Good
variable "system_disk" { ... }
variable "additionnal_disks" { ... }

# ❌ Bad
variable "disk1" { ... }
variable "disk2" { ... }
```

### 3. Provide Sensible Defaults

```hcl
variable "additionnal_disks" {
  type    = list(object({ storage = string, size = number }))
  default = []  # ✅ Optional, empty by default
}

variable "tags" {
  type    = list(string)
  default = ["ubuntu"]  # ✅ Sensible default
}
```

### 4. Document Module Interface

In each module, add a `README.md`:

```markdown
# proxmox_vm Module

Creates a Proxmox virtual machine.

## Usage

\`\`\`hcl
module "vm" {
  source = "./modules/proxmox_vm"
  fqdn   = "my-vm.example.com"
  ...
}
\`\`\`

## Inputs

| Name | Type | Required |
| ---- | ---- | -------- |
| fqdn | string | yes |
...

## Outputs

| Name | Type | Description |
| ---- | ---- | ----------- |
| vm_id | number | Proxmox VM ID |
...
```

### 5. Use for_each Over count

```hcl
# ✅ Good: for_each with map
module "vm" {
  for_each = { for v in var.vms : v.name => v }
  ...
}

# ❌ Avoid: count with index manipulation
# module "vm" {
#   count = length(var.vms)
#   fqdn  = var.vms[count.index].name
# }
```

**Why:** for_each produces stable resource addresses; count is index-based (fragile).

### 6. Manage Provider Requirements

Ensure module declares required providers:

```hcl
terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.42.0"
    }
  }
}
```

### 7. Version Modules

As your project grows, consider versioning modules:

```
modules/
├── proxmox_vm/
│   └── v1.0/       # Initial version
│   └── v2.0/       # New features
└── ...
```

Then reference specific versions in root module:

```hcl
module "vm" {
  source = "./modules/proxmox_vm/v2.0"
  ...
}
```

### 8. Test Module Changes Incrementally

```bash
# Apply only one VM to test module changes
terraform apply -target=module.vm[\"ansible-01\"]

# Verify VM created correctly
# Then apply rest
terraform apply
```

---

## Integration with Root Module

### Module Data Flow

```
root/variables.tf (var.vms, var.domain, etc.)
    ↓
root/vms.tf (module "vm" instantiation)
    ↓
modules/proxmox_vm/main.tf (VM creation)
    ↓
proxmox_virtual_environment_vm.this (actual VM)
```

### State Management

Module resources are stored in `terraform.tfstate` under a path:

```
resource "module.vm[\"k8s-master-01\"].proxmox_virtual_environment_vm.this" {
  vm_id = 1234
  ...
}
```

Access via root module outputs:

```hcl
# Access from root module
output "vms" {
  value = { for k, m in module.vm : k => { ... } }
}
```

Then retrieve outputs:

```bash
terraform output vms

# Output:
# {
#   "ansible-01" = {
#     "fqdn" = "ansible-01.k8s.local"
#     "id"   = 1234
#     "ip"   = ["192.168.1.10"]
#   }
#   ...
# }
```

---

## Extending the Module

### Adding New Functionality

To extend the module with new features:

1. **Add input variable** in `variables.tf`
2. **Update resource** in `main.tf` to use new variable
3. **Add output** in `outputs.tf` if needed
4. **Update root module** to pass new variable values
5. **Test** with `terraform plan` before applying

**Example: Add GPU Support**

```hcl
# variables.tf
variable "gpu" {
  type    = bool
  default = false
}

# main.tf
dynamic "device" {
  for_each = var.gpu ? [1] : []
  content {
    host = "0:1d.0"  # GPU PCI address
  }
}

# outputs.tf
output "has_gpu" {
  value = var.gpu
}
```

---

## References

- [Terraform Module Documentation](https://www.terraform.io/language/modules)
- [Terraform for_each Meta-Argument](https://www.terraform.io/language/meta-arguments/for_each)
- [Terraform dynamic Blocks](https://www.terraform.io/language/expressions/dynamic)
- [Terraform lifecycle Meta-Argument](https://www.terraform.io/language/meta-arguments/lifecycle)
- [Terraform Object Type Constraints](https://www.terraform.io/language/types/object)
- [Proxmox Provider Documentation](https://registry.terraform.io/providers/bpg/proxmox/latest)
- [Proxmox VE VM Configuration](https://pve.proxmox.com/wiki/Qemu/KVM_Virtual_Machines)
