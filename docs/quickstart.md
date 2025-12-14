# Quick Start Guide - Kubernetes on Proxmox with Terraform and Ansible

## Overview

This guide will get you up and running with a fully automated Kubernetes cluster on Proxmox in approximately 30-45 minutes.

**What you'll get:**
- 1× Ansible control node
- 1× Kubernetes master node
- 3× Kubernetes worker nodes
- Full Flannel CNI networking
- Automated deployment via Terraform + Ansible

---

## Prerequisites Checklist

Before starting, verify you have:

- [ ] **Proxmox VE** (7.x or 8.x) installed and accessible
- [ ] **Ubuntu 20.04 or 22.04 LTS** VM template in Proxmox (tagged with `template`)
- [ ] **Terraform** >= 1.0 installed locally
- [ ] **Ansible** >= 2.9 installed locally
- [ ] **SSH client** and **Git** installed
- [ ] **API token** for Proxmox (obtained from Web UI)
- [ ] **Network bridge** configured in Proxmox (e.g., `vmbr0`)
- [ ] **Available IP range** for 5 VMs (e.g., `192.168.1.10-14`)
- [ ] **50+ GB free storage** in Proxmox storage pool
- [ ] **SSH key pair** generated (ED25519 preferred)

For detailed setup, see [Prerequisites Documentation](prerequis.md).

---

## 5-Minute Setup

### 1. Clone the Project

```bash
git clone https://github.com/your-org/projet-terraform-k8s.git
cd projet-terraform-k8s
```

### 2. Create terraform.tfvars

```bash
cat > terraform.tfvars << 'EOF'
# Proxmox Access
proxmox_endpoint = "https://192.168.1.100:8006/"  # Replace with your Proxmox IP
api_token        = "user@realm!tokenid=tokensecret"  # Replace with your token

# Infrastructure Configuration (Optional - defaults provided)
# target_node     = "pve-node-01"          # Replace with your Proxmox node name
# network_bridge  = "vmbr0"                # Replace with your bridge name
# gateway_ipv4    = "192.168.1.1"         # Replace with your gateway
# domain          = "k8s.local"           # Your DNS domain

EOF

chmod 600 terraform.tfvars
```

**⚠️ IMPORTANT**: 
- Never commit `terraform.tfvars` to Git
- Keep your API token confidential
- Add `terraform.tfvars` to `.gitignore`

### 3. Initialize Terraform

```bash
terraform init
```

**What this does:**
- Downloads required providers (Proxmox, TLS, Local, Random)
- Creates local Terraform state file
- Sets up working directory

### 4. Verify Configuration

```bash
terraform validate
```

Expected output:
```
Success! The configuration is valid.
```

### 5. Plan the Deployment

```bash
terraform plan -out=tfplan
```

**Review the plan output:**
- Shows 5 VMs to be created
- Shows SSH key generation
- Shows cloud-init templates
- Shows Ansible provisioning resources

**Example output lines:**
```
Plan: 15 to add, 0 to change, 0 to destroy.
- module.vm["ansible-01"] (proxmox_virtual_environment_vm)
- module.vm["k8s-master-01"] (proxmox_virtual_environment_vm)
- module.vm["k8s-worker-01"] (proxmox_virtual_environment_vm)
- ...
```

---

## Deployment (15-30 minutes)

### Apply the Configuration

```bash
terraform apply tfplan
```

**This will:**

1. **Generate SSH keys** (ED25519)
   - Private key: `./secrets/ansible_cluster_id_ed25519`
   - Public key: Distributed to all VMs via cloud-init

2. **Create 5 VMs** on Proxmox
   - Clone from template
   - Inject cloud-init configuration
   - Configure network (static IP, gateway)
   - Boot and wait for SSH

3. **Install Ansible** on control node
   - Install Python packages
   - Setup virtual environment
   - Generate dynamic inventory

4. **Run Ansible Playbook**
   - Install containerd on all nodes
   - Install kubeadm, kubelet, kubectl
   - Initialize Kubernetes on master
   - Join workers to cluster
   - Deploy Flannel CNI

5. **Output cluster information**
   - Master IP address
   - Worker IP addresses
   - SSH key location
   - Cluster status

**Expected duration:** 15-30 minutes depending on:
- Network speed (package downloads)
- Proxmox performance
- VM specs

**Console output example:**
```
Apply complete! Resources have been added, removed, or changed.

Outputs:

ansible_control_ip = "192.168.1.10"
kubernetes_master = "192.168.1.11"
kubernetes_workers = [
  "192.168.1.12",
  "192.168.1.13",
  "192.168.1.14",
]
ssh_private_key = "./secrets/ansible_cluster_id_ed25519"
```

---

## Post-Deployment Verification

### 1. Check SSH Access

```bash
# Test SSH to master node
ssh -i ./secrets/ansible_cluster_id_ed25519 ubuntu@192.168.1.11

# You should see Ubuntu prompt
ubuntu@k8s-master-01:~$
```

### 2. Verify Kubernetes Cluster

```bash
# SSH into master
ssh -i ./secrets/ansible_cluster_id_ed25519 ubuntu@192.168.1.11

# Check node status
kubectl get nodes
```

**Expected output:**
```
NAME             STATUS   ROLES           AGE     VERSION
k8s-master-01    Ready    control-plane   5m      v1.29.0
k8s-worker-01    Ready    <none>          4m      v1.29.0
k8s-worker-02    Ready    <none>          4m      v1.29.0
k8s-worker-03    Ready    <none>          4m      v1.29.0
```

### 3. Verify Pods

```bash
# Check kube-system pods
kubectl get pods -n kube-system

# Expected pods:
# - coredns-* (DNS)
# - etcd-k8s-master-01 (State store)
# - kube-apiserver-* (API server)
# - kube-controller-manager-* (Controllers)
# - kube-proxy-* (Networking)
# - kube-scheduler-* (Scheduler)
# - flannel-* (CNI plugin)
```

### 4. Test Networking

```bash
# Check pod CIDR
kubectl get nodes -o wide

# Expected pod CIDR: 10.244.x.0/24

# Deploy a test pod
kubectl run test-pod --image=busybox -- sleep 3600
kubectl get pods -o wide
```

---

## Basic Operations

### Accessing the Cluster

```bash
# Copy kubeconfig to local machine (optional)
scp -i ./secrets/ansible_cluster_id_ed25519 \
  ubuntu@192.168.1.11:/home/ubuntu/.kube/config \
  ~/.kube/config-k8s

# Use with kubectl
export KUBECONFIG=~/.kube/config-k8s
kubectl get nodes
```

### SSH to Any Node

```bash
# Ansible node (control)
ssh -i ./secrets/ansible_cluster_id_ed25519 ubuntu@192.168.1.10

# Master
ssh -i ./secrets/ansible_cluster_id_ed25519 ubuntu@192.168.1.11

# Worker 1
ssh -i ./secrets/ansible_cluster_id_ed25519 ubuntu@192.168.1.12
```

### View Logs

```bash
# Terraform apply logs
terraform show

# Ansible logs (on ansible-01 node)
ssh -i ./secrets/ansible_cluster_id_ed25519 ubuntu@192.168.1.10
cat /var/log/ansible-playbook.log
```

### Cloud-init Logs (Troubleshooting)

```bash
# SSH to any node
ssh -i ./secrets/ansible_cluster_id_ed25519 ubuntu@192.168.1.11

# View cloud-init output
sudo cat /var/log/cloud-init-output.log

# View cloud-init status
cloud-init status
```

---

## Customization

### Modify VM Configuration

Edit `variables.tf` or `terraform.tfvars` to customize:

```hcl
# Change network settings
network_bridge = "vmbr1"  # Use different bridge
gateway_ipv4   = "10.0.0.1"  # Different gateway

# Change domain
domain = "mycompany.local"

# Modify VM specs
vms = [
  {
    name   = "ansible-01"
    ip     = "192.168.1.10"
    cpu    = 2    # Increase from 1
    memory = 4096 # Increase from 2048
    role   = "ansible"
  },
  # ... other VMs
]
```

### Apply Customizations

```bash
# Recreate VMs with new config
terraform apply

# Or target specific VMs
terraform apply -target=module.vm[\"k8s-master-01\"]
```

### Change Node Count

To add more workers, modify `variables.tf`:

```hcl
vms = [
  # ... existing VMs ...
  {
    name   = "k8s-worker-04"
    ip     = "192.168.1.15"
    cpu    = 2
    memory = 4096
    role   = "worker"
  },
]
```

Then:
```bash
terraform apply
```

The new worker will automatically join the cluster.

---

## Cleanup

### Destroy All Resources

```bash
# This will delete all VMs and local state
terraform destroy

# Confirm by typing: yes
```

**What this removes:**
- All 5 VMs from Proxmox
- Cloud-init snippets
- Local Terraform state (but NOT terraform.tfvars or SSH keys)

### Destroy Specific VMs

```bash
# Remove a single worker
terraform apply -destroy -target=module.vm[\"k8s-worker-03\"]
```

### Keep Keys for Redeployment

```bash
# Backup SSH keys
cp ./secrets/ansible_cluster_id_ed25519 ~/backup/

# Run destroy
terraform destroy

# Keys are kept - safe to redeploy
```

---

## Common Issues & Quick Fixes

### Issue: "No templates found"

```
Error: data.proxmox_virtual_environment_vms.template: Error: no templates found
```

**Fix:**
1. Verify template exists in Proxmox
2. Check template has required tags: `template` (and optionally `ubuntu`)
3. Update `template_tag` variable if using different tags

```bash
# List templates on Proxmox
pvesh get /nodes/pve-node-01/qemu --output=json | jq '.[] | select(.template == 1)'
```

### Issue: "API token invalid"

```
Error: invalid authentication data
```

**Fix:**
1. Verify token format: `user@realm!tokenid=secret`
2. Check token hasn't expired (Proxmox Web UI → Datacenter → API Tokens)
3. Verify token has required permissions

### Issue: "Network bridge not found"

```
Error: bridge vmbr0 not found
```

**Fix:**
1. List available bridges on Proxmox:
   ```bash
   ip link show | grep vmbr
   ```
2. Update `network_bridge` variable to correct bridge name

### Issue: "SSH timeout"

```
Error: timeout waiting for SSH
```

**Fix:**
1. Verify VMs are running in Proxmox
2. Check cloud-init status: `cloud-init status`
3. Verify network bridge configuration
4. Increase timeout in `wait_for_ssh.sh` if needed

### Issue: "Kubernetes nodes not ready"

```bash
kubectl get nodes
# Shows: NotReady status
```

**Fix:**
1. Wait 2-3 minutes for cluster initialization
2. Check node logs:
   ```bash
   ssh -i ./secrets/ansible_cluster_id_ed25519 ubuntu@192.168.1.12
   sudo systemctl status kubelet
   sudo journalctl -u kubelet -n 50
   ```
3. Check Flannel pods:
   ```bash
   kubectl get pods -n kube-system -l app=flannel
   ```

---

## Next Steps

### 1. Deploy Applications

```bash
# Deploy a test application
kubectl create deployment nginx --image=nginx:latest
kubectl expose deployment nginx --type=NodePort --port=80

# Access it
kubectl get service nginx
```

### 2. Setup Monitoring

See [Architecture Documentation](architecture.md) for monitoring recommendations.

### 3. Configure Persistent Storage

Add storage class for persistent volumes:

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-storage
provisioner: kubernetes.io/no-provisioner
```

### 4. Setup Ingress

Deploy Nginx Ingress Controller:

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm install ingress-nginx ingress-nginx/ingress-nginx \
  -n ingress-nginx --create-namespace
```

### 5. Read Full Documentation

- [Prerequisites](prerequis.md) - Detailed setup requirements
- [Architecture](architecture.md) - System design and components
- [Cloud-init](cloud-init.md) - VM initialization details
- [Modules](modules.md) - Terraform module documentation

---

## Getting Help

### Useful Commands

```bash
# Check Terraform state
terraform state list
terraform state show module.vm[\"k8s-master-01\"]

# View provider logs
export TF_LOG=DEBUG
terraform apply

# Check Ansible inventory
cat ansible/inventory.ini

# View Ansible playbook results
ssh -i ./secrets/ansible_cluster_id_ed25519 ubuntu@192.168.1.10
cat /var/log/ansible-playbook.log
```

### Debugging Steps

1. **Terraform apply fails:**
   ```bash
   terraform apply -parallelism=1 -no-color 2>&1 | tee apply.log
   ```

2. **Ansible playbook fails:**
   ```bash
   ssh -i ./secrets/ansible_cluster_id_ed25519 ubuntu@192.168.1.10
   ansible-playbook -i inventory.ini playbook.yml -vvv
   ```

3. **Kubernetes issues:**
   ```bash
   kubectl describe nodes
   kubectl describe pod <pod-name> -n <namespace>
   kubectl logs <pod-name> -n <namespace>
   ```

### Resources

- [Terraform Documentation](https://www.terraform.io/docs)
- [Kubernetes Official Docs](https://kubernetes.io/docs/)
- [Proxmox Terraform Provider](https://registry.terraform.io/providers/bpg/proxmox/latest)
- [Flannel CNI](https://github.com/flannel-io/flannel)
- [Ansible Documentation](https://docs.ansible.com/)

---

## Security Notes

⚠️ **Important Security Considerations:**

1. **API Token**
   - Never commit to Git
   - Use environment variables in CI/CD
   - Rotate tokens regularly

2. **SSH Keys**
   - Keep `./secrets/` directory secure
   - Restrict permissions: `chmod 600 ./secrets/*`
   - Backup keys in secure location
   - Never share keys

3. **Kubernetes Access**
   - Restrict kubectl access to authorized users
   - Use RBAC for pod security
   - Consider network policies for pod-to-pod communication
   - Implement admission controllers

4. **Production Hardening**
   - Use external etcd cluster
   - Enable audit logging
   - Setup pod security policies
   - Consider network segmentation
   - Use TLS for all communication

---

## Troubleshooting Workflow

```
Problem occurs
    ↓
Check terraform.tfvars and variables
    ↓
Run: terraform plan
    ↓
Check SSH access to VMs
    ↓
Check cloud-init logs: cloud-init status
    ↓
Check Ansible logs on ansible-01 node
    ↓
SSH to master: kubectl get nodes
    ↓
If still issues: Run terraform destroy and start over
```

---

## Support

For issues not covered here, see:
- [Prerequisites Documentation](prerequis.md) for setup issues
- [Architecture Documentation](architecture.md) for design questions
- [Cloud-init Documentation](cloud-init.md) for VM initialization issues
- [Modules Documentation](modules.md) for Terraform code details

---


