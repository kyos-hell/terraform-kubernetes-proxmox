# Architecture - Kubernetes on Proxmox with Terraform and Ansible

## Table of Contents

1. [Overview](#overview)
2. [General Architecture](#general-architecture)
3. [Terraform Architecture](#terraform-architecture)
4. [Kubernetes Architecture](#kubernetes-architecture)
5. [Network Architecture](#network-architecture)
6. [Deployment Flow](#deployment-flow)
7. [Components and Roles](#components-and-roles)
8. [Dependencies and Orchestration](#dependencies-and-orchestration)

---

## Overview

This project automates the complete deployment of a Kubernetes HA (High Availability) cluster on Proxmox infrastructure via Infrastructure-as-Code (IaC).

**Key Components:**
- **Proxmox VE**: Hypervisor/Host Infrastructure
- **Terraform**: VM orchestration and provisioning
- **Ansible**: Kubernetes cluster configuration and initialization
- **Containerd**: Container runtime
- **Kubernetes 1.29**: Container orchestration
- **Calico**: CNI (Container Network Interface, VXLAN overlay supported)

---

## General Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                          PROXMOX VE (Physical)                      │
│                        pve-node-01 (Node, example)                │
└─────────────────────────────────────────────────────────────────────┘
                                    │
         ┌──────────────────────────┼──────────────────────────┐
         │                          │                          │
    ┌────▼────────┐          ┌─────▼──────┐          ┌────────▼──────┐
    │ ansible-01  │          │k8s-master-01│         │ k8s-worker-* │
    │ (Control)   │          │ (Master)     │         │ (Workers)    │
    │ 2048 MB RAM │          │ 4096 MB RAM  │         │ 4096 MB RAM  │
    │ 1 CPU       │          │ 2 CPUs       │         │ 2 CPUs each  │
    └─────────────┘          └──────────────┘         └──────────────┘
    192.168.1.10          192.168.1.11    192.168.1.12/13/14
         │                       │                      │
         └───────────────────────┼──────────────────────┘
                                 │
                        ┌────────▼────────┐
                        │  Calico CNI (VXLAN) │
                        │ Pod CIDR: 10.233.64.0/18 │
                        └──────────────────┘
```

---

## Terraform Architecture

### Project Structure

```
projet-terraform-k8s/
├── providers.tf              # Provider configuration (Proxmox, TLS, Local, Random)
├── variables.tf              # Input variables (VMs, network, credentials)
├── locals.tf                 # Derived local values (IP maps, etc.)
├── data.tf                   # Data sources (VM template filtering)
├── vms.tf                    # VM module - loop over var.vms
├── cloud-init/               # cloud-init templates (user_data, metadata)
├── modules/
│   └── proxmox_vm/          # Reusable module for VM creation
│       ├── main.tf          # VM provisioning definition
│       ├── variables.tf      # Module variables
│       ├── outputs.tf        # Module outputs
│       └── required_providers_fix.tf  # Provider fix
├── ansible_install.tf        # Ansible provisioning on ansible-01
├── wait_and_run_ansible.tf   # Ansible execution orchestration
├── write_private_key.tf      # SSH key management
└── reboot_local_exec_with_script.tf  # Post-deployment reboot
```

### Terraform Provisioning Flow

```
1. DATA RETRIEVAL
   data.proxmox_virtual_environment_vms → Fetch VM template

2. VM CREATION (VM Module - for_each loop)
   ├── Clone template via Proxmox
   ├── cloud-init configuration (IP, hostname, SSH keys)
   ├── CPU/Memory/Disk allocation
   └── SSH private key generation

3. POST-VM SETUP
   ├── Wait for SSH availability (wait_for_ssh.sh)
   ├── Distribute public key (authorized_keys)
   ├── Populate known_hosts

4. ANSIBLE PROVISIONING
   ├── Install Ansible on ansible-01
   ├── Copy playbook/inventory to ansible-01
   └── Execute playbook.yml (kubeadm + CNI)

5. OUTPUTS
   └── IPs, FQDN, SSH private key
```

### Providers Used

| Provider | Version | Role |
|----------|---------|------|
| `bpg/proxmox` | 0.42.0 | Proxmox API interaction |
| `hashicorp/tls` | ~> 4.0 | SSH key generation |
| `hashicorp/local` | ~> 2.0 | Local file writing |
| `hashicorp/random` | ~> 3.4 | Random identifier generation |

---

## Kubernetes Architecture

### Cluster Topology

**Type**: Kubernetes Standard (1 master + N workers)  
**Version**: 1.29  
**CRI**: containerd 1.x  
**CNI**: Calico v3.29.x (VXLAN overlay supported)

#### Nodes

| Role | Name | IP | CPU | RAM | Responsibilities |
|------|------|----|----|-----|-----------------|
| **Master** | k8s-master-01 | 192.168.1.11 | 2 | 4 GB | Control Plane, API Server, etcd, Scheduler |
| **Worker** | k8s-worker-01 | 192.168.1.12 | 2 | 4 GB | Kubelet, kube-proxy, Pod scheduling |
| **Worker** | k8s-worker-02 | 192.168.1.13 | 2 | 4 GB | Kubelet, kube-proxy, Pod scheduling |
| **Worker** | k8s-worker-03 | 192.168.1.14 | 2 | 4 GB | Kubelet, kube-proxy, Pod scheduling |
| **Ansible** | ansible-01 | 192.168.1.10 | 1 | 2 GB | Bastion/Control node (not K8s) |

### Installed Kubernetes Components

#### Control Plane (Master)
- **kube-apiserver**: Kubernetes REST API
- **kube-controller-manager**: Reconciliation loops
- **kube-scheduler**: Pod to node assignment
- **etcd**: Distributed key-value store (cluster state)

#### Node Components (Master + Workers)
- **kubelet**: Node agent, pod lifecycle management
- **kube-proxy**: Networking, services, iptables/netfilter
- **containerd**: Container runtime

#### Add-ons
- **Calico CNI**: Pod network overlay (VXLAN), IPPool CIDR = 10.233.64.0/18 (blockSize /26)

Additional cluster add-ons installed by the Ansible playbook:

- **local-path-provisioner** (Rancher): lightweight dynamic `StorageClass` for local volumes in lab environments. The playbook forces a known image version and ensures the `local-path` StorageClass has `reclaimPolicy: Retain`.

- **metrics-server**: exposes cluster resource metrics (CPU/memory) consumed by nodes/pods and enables `kubectl top` and HPA use-cases. The playbook applies the upstream `components.yaml` and patches args for kubelet TLS/address preferences.

- **ingress-nginx**: NGINX-based Ingress Controller deployed via Helm. Installed with `controller.service.type=LoadBalancer` so a MetalLB `LoadBalancer` IP can be assigned to the controller service in lab networks.

### Kubernetes Initialization Flow

```
1. PRE-INITIALIZATION (All nodes)
   ├── Disable swap
   ├── Load kernel modules (overlay, br_netfilter)
   ├── Configure sysctl (bridge, IP forwarding)
   ├── Install containerd (Docker repo)
   ├── Configure containerd (SystemdCgroup, CRI plugin)
   └── Install kubeadm/kubelet/kubectl

2. MASTER INITIALIZATION
   ├── kubeadm init --pod-network-cidr=10.233.64.0/18
   ├── Generate admin.conf (kubeconfig)
   ├── Extract kubeadm token + join command
   └── Deploy Calico CNI (calico.yaml) and create IPPool

3. WORKER JOIN
   └── kubeadm join --token ... (for each worker)

4. VERIFICATION
   └── kubectl get nodes → all READY
```

### Kubernetes Networking

```
┌────────────────────────────────────────────┐
│      Host Network (192.168.1.0/24)       │
│   (Proxmox vmbr0 bridge, example)            │
└────────────────────────────────────────────┘
         │           │          │       │
    ┌────▼───┐  ┌───▼─────┐  ┌─▼─────┐ └─...
   │Master  │  │ Worker1 │  │Worker2│
   │(Calico IPs)│  │(Calico IPs) │  │(Calico IPs)│
    └────┬───┘  └────┬────┘  └─┬─────┘
         │           │         │
    ┌────▼───────────▼─────────▼─────┐
   │  Pod Network Overlay (Calico VXLAN)   │
   │       CIDR: 10.233.64.0/18 (IPPool)  │
    └────────────────────────────────┘
```

-- **Host Network**: 192.168.1.0/24 (example, Proxmox VLAN)
-- **Pod Network**: 10.233.64.0/18 (Calico VXLAN IPPool)
   - Calico allocates per-node blocks (e.g., /26) from the IPPool
   - Master and worker pod ranges are assigned by Calico

---

## Network Architecture

### Physical Network (Proxmox)

```
Proxmox Node (pve-node-01, example)
    │
    └─→ vmbr0 (Bridge Network, example)
        │
        ├─→ 192.168.1.10 (ansible-01, example)
        ├─→ 192.168.1.11 (k8s-master-01, example)
        ├─→ 192.168.1.12 (k8s-worker-01, example)
        ├─→ 192.168.1.13 (k8s-worker-02, example)
        └─→ 192.168.1.14 (k8s-worker-03, example)

Gateway: 192.168.1.1 (example)
Prefix: /24 (255.255.255.0)
```

### Terraform Network Configuration

```hcl
variable "network_bridge"      = "vmbr0"          # Proxmox bridge (example)
variable "network_prefix"      = 24               # CIDR /24
variable "gateway_ipv4"        = "192.168.1.1"   # Gateway (example)
variable "domain"              = "k8s.local"     # Local domain (example)
```

### Cloud-init Network Setup

The cloud-init configuration (cloud-init/user_data.tpl) configures:
- Static IP via DHCP override (via Proxmox initialization)
- FQDN hostname (e.g., k8s-master-01.k8s.local, example)
- SSH keys distribution

---

## Deployment Flow

### Phase 1: Terraform Preparation (Local)

1. **Read variables**
   ```bash
   terraform apply -var-file="terraform.tfvars"
   ```
   - Proxmox API connection
   - Provider validation

2. **Search template**
   ```hcl
   data "proxmox_virtual_environment_vms" "template"
   ```
   - Filter: tags = ["template", var.template_tag]
   - Fetch VM ID from template

### Phase 2: VM Creation (Proxmox)

```
for_each var.vms :
  ├── Clone template VM (via proxmox_virtual_environment_vm)
  ├── Inject cloud-init user-data + meta-data
  │   ├── Hostname
  │   ├── Static IP + gateway
  │   └── SSH authorized_keys
  ├── Resource allocation (CPU, RAM, disk)
  └── Boot VM
```

**Resolved dependencies**:
```
module.vm["ansible-01"]
module.vm["k8s-master-01"]
module.vm["k8s-worker-*"]
```

### Phase 3: Connectivity Wait (Scripts)

```bash
wait_for_ssh.sh <timeout> <user> <key> <IPs>
```
- SSH polling on each VM (timeout = 600s)
- Wait for cloud-init completion
- Distribute public key SSH

### Phase 4: Ansible Installation (ansible-01)

```bash
install-ansible.sh
```
- Install apt packages (ansible, python3-venv)
- Setup virtual environment
- Install Ansible dependencies

### Phase 5: Playbook + Inventory Distribution

```bash
generate_and_copy_ansible.sh
```
- Generate dynamic inventory.ini (from var.vms)
- Copy playbook.yml to ansible-01
- Prepare known_hosts

### Phase 6: Ansible Playbook Execution

```bash
ansible-playbook -i inventory.ini playbook.yml -v
```

**Playbook steps**:
1. **Setup All Nodes** (pre-K8s)
   - Disable swap
   - Load kernel modules
   - Install containerd
   - Install kubeadm/kubelet/kubectl

2. **Init Master**
   - `kubeadm init` → generate tokens
   - Deploy Calico CNI (calico.yaml) and create IPPool

3. **Join Workers**
   - `kubeadm join` → join cluster

### Phase 7: Reboot + Verification

```bash
reboot_and_wait.sh
```
- Safe VM reboot
- Wait for cluster READY
- Verify nodes

---

## Components and Roles

### VM Roles

#### ansible-01 (Bastion/Control Node)
- **Role**: Control machine (not part of K8s cluster)
- **Responsibilities**:
  - Ansible host for orchestrating deployments
  - Storage for playbooks/inventories
  - Centralized SSH access point
- **Services**: SSH, Ansible, Python venv
- **Resources**: 1 CPU, 2 GB RAM

#### k8s-master-01 (Control Plane)
- **Role**: Kubernetes Master
- **Responsibilities**:
  - API Server (Kubernetes REST API)
  - etcd (state store)
  - Scheduler (pod placement)
  - Controller Manager (reconciliation loops)
- **Services**: kubelet, kube-proxy, containerd, API server
- **Resources**: 2 CPU, 4 GB RAM

#### k8s-worker-01/02/03 (Compute Nodes)
- **Role**: Worker nodes (pod execution)
- **Responsibilities**:
  - Workload execution (pods)
  - Local network management (kube-proxy)
  - CRI communication (containerd)
- **Services**: kubelet, kube-proxy, containerd
- **Resources**: 2 CPU, 4 GB RAM each

### Technology Stack

| Component | Role | Version |
|-----------|------|---------|
| **Proxmox VE** | Hypervisor | Latest |
| **Terraform** | IaC Orchestration | >= 1.0 |
| **Ansible** | Configuration Management | 2.x |
| **Ubuntu** | OS template | 20.04 LTS / 22.04 LTS |
| **containerd** | CRI Runtime | 1.x |
| **Kubernetes** | Orchestration | 1.29 |
| **kubeadm** | Cluster bootstrapping | 1.29.0-* |
| **Calico** | CNI | v3.29.x |
| **local-path-provisioner** | StorageClass (dynamic local PVs) | v0.0.32 (pin) |
| **metrics-server** | Metrics for `kubectl top` / HPA | upstream release |
| **ingress-nginx** | Ingress controller (NGINX) | helm chart (stable) |
| **cloud-init** | VM bootstrap | Standard |

---

## Dependencies and Orchestration

### Logical Execution Order

```
┌─────────────────────────────────────────────────────────┐
│ 1. DATA SOURCES (Search Proxmox template)              │
│    data.proxmox_virtual_environment_vms.template       │
└──────────────┬──────────────────────────────────────────┘
               │
┌──────────────▼──────────────────────────────────────────┐
│ 2. VM CREATION (for_each on var.vms)                   │
│    module.vm[*] → Clone + cloud-init                   │
└──────────────┬──────────────────────────────────────────┘
               │
┌──────────────▼──────────────────────────────────────────┐
│ 3. CONNECTIVITY SETUP                                  │
│    ├── wait_for_ssh.sh (SSH polling)                   │
│    ├── distribute_pubkey (authorized_keys)             │
│    └── populate_known_hosts                            │
└──────────────┬──────────────────────────────────────────┘
               │
┌──────────────▼──────────────────────────────────────────┐
│ 4. ANSIBLE CONTROL NODE                                │
│    ├── install_ansible (apt install)                   │
│    └── wait_and_reboot                                 │
└──────────────┬──────────────────────────────────────────┘
               │
┌──────────────▼──────────────────────────────────────────┐
│ 5. PLAYBOOK EXECUTION                                  │
│    ├── copy_ansible (files distribution)               │
│    └── run_playbook (kubeadm init/join)               │
└──────────────┬──────────────────────────────────────────┘
               │
┌──────────────▼──────────────────────────────────────────┐
│ 6. CLUSTER VALIDATION                                  │
│    └── kubectl get nodes → READY                       │
└─────────────────────────────────────────────────────────┘
```

### Terraform Dependencies (depends_on)

```hcl
module.vm[*]
    ↓
null_resource.reboot_ansible
    ↓
null_resource.install_ansible
    ↓
null_resource.wait_for_vms
    ├─→ null_resource.populate_known_hosts
    ├─→ null_resource.distribute_pubkey
    │
    ↓
null_resource.copy_ansible
    ↓
null_resource.run_playbook (ansible-playbook)
    ↓
CLUSTER READY
```

### Critical Checkpoint

| Step | Timeout | Condition |
|------|---------|-----------|
| wait_for_ssh.sh | 600s | SSH available |
| cloud-init | Automatic | Completed by cloud-init |
| kubeadm init | Variable | Control plane ready |
| kubeadm join | Variable | Workers ready (minutes) |
| Calico CNI | Variable | Pods running (calico-node DaemonSet)
| Cluster ready | Variable | All nodes READY |

---

## Key Variables

### VMs Configuration

```hcl
variable "vms" {
  type = list(object({
    name   = string  # e.g., "k8s-master-01"
    ip     = string  # e.g., "192.168.1.11" (example)
    cpu    = number  # e.g., 2
    memory = number  # e.g., 4096 (MB)
    role   = string  # "master", "worker", "ansible"
  }))
}
```

### Credentials and Access

```hcl
variable "proxmox_endpoint"    # Proxmox API URL
variable "api_token"           # Proxmox token (sensitive)
variable "ssh_key_path"        # Private SSH key path
variable "ssh_user"            # SSH user (ubuntu by default)
```

### Network

```hcl
variable "network_bridge"      # vmbr0 (Proxmox bridge)
variable "gateway_ipv4"        # 192.168.1.1
variable "network_prefix"      # 24 (CIDR)
variable "domain"              # k8s.local
```

### Storage

```hcl
variable "system_disk" = {
  storage = "local"
  size    = 50  # GB
}

variable "additionnal_disks" = []  # List of additional disks
```

---

## Outputs

```hcl
# Outputs available after terraform apply
├── vm_details         # IP, FQDN, resources
├── ansible_control_ip # 192.168.1.10
├── kubernetes_master  # 192.168.1.11
├── kubernetes_workers # [192.168.1.12, 13, 14]
├── ssh_private_key    # Local private key path
└── cluster_status     # Provisioning state
```

---

## Important Points

### Security

- ✅ ED25519 SSH keys generated locally
- ✅ Proxmox credentials in sensitive variables
- ✅ Secret files in .gitignore
- ⚠️ Insecure=true Proxmox (lab only)

### High Availability

- ❌ Single master (not HA currently)
- ⚠️ For production: add load balancer + 3 masters + external etcd

### Scalability

- ✅ Reusable VM module
- ✅ Workers addable via var.vms variable
- ✅ Resources configurable per VM

### Maintenance

- 🔧 Terraform state: stored locally (terraform.tfstate)
- 🔧 Cloud-init logs: /var/log/cloud-init-output.log
- 🔧 Kubernetes logs: journalctl -u kubelet
- 🔧 Ansible logs: ~/.ansible.log

---

## Next Steps / Improvements

1. **HA Master**: Add 2nd/3rd master + Load Balancer
2. **Persistent Storage**: Integrate Ceph/NFS CSI
3. **Monitoring**: Prometheus + Grafana
4. **Logging**: ELK/Loki stack
5. **Backup**: etcd snapshots + VM backups
6. **GitOps**: Flux/ArgoCD for deployments
7. **Advanced Networking**: Cilium CNI + network policies
8. **RBAC**: Policies + Pod Security Standards

---

## References

- [Proxmox Terraform Provider](https://registry.terraform.io/providers/bpg/proxmox/latest)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Kubeadm Setup](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/)
- [Calico CNI](https://github.com/projectcalico/calico)
- [Ansible Documentation](https://docs.ansible.com/)
- [cloud-init](https://cloud-init.io/)

