# Terraform + Kubernetes on Proxmox — Learning Project

![Terraform](https://img.shields.io/badge/Terraform-1.0+-623CE4?logo=terraform&logoColor=white)
![Kubernetes](https://img.shields.io/badge/Kubernetes-1.29-326CE5?logo=kubernetes&logoColor=white)
![Proxmox](https://img.shields.io/badge/Proxmox-7.0+-E57000?logo=proxmox&logoColor=white)
![Ansible](https://img.shields.io/badge/Ansible-2.9+-EE0000?logo=ansible&logoColor=white)
![Linux](https://img.shields.io/badge/Linux-Debian/Ubuntu-A81D33?logo=linux&logoColor=white)
![Bash](https://img.shields.io/badge/Bash-5.0+-4EAA25?logo=gnubash&logoColor=white)

Welcome! 👋 This project demonstrates infrastructure-as-code principles by automating the provisioning of a complete Kubernetes cluster on Proxmox VE using Terraform, cloud-init, and Ansible.

---

## 🎯 Project Objective

This project is designed as a **learning platform** for DevOps technologies, cloud infrastructure, and modern deployment practices. The goal is to:

- **Learn Infrastructure-as-Code (IaC)**: Terraform patterns, state management, modular design
- **Understand Cloud-init**: VM automation, automated configuration, user data scripting
- **Master Kubernetes**: Cluster initialization with kubeadm, networking with Flannel, node bootstrapping
- **Practice Ansible**: Configuration management, playbook design, idempotence
- **Implement SSH & Security**: Key management, secure credential handling, best practices
- **Explore DevOps Workflows**: From infrastructure provisioning to application deployment
- **Debug & Troubleshoot**: Real-world issues and pragmatic solutions

**This is NOT a production-ready system**, but rather an educational foundation that can evolve into one.

---

## 📚 Documentation Structure

All documentation lives in the `docs/` directory. Below is a complete roadmap:

### Getting Started

| Document | Purpose | Audience |
|----------|---------|----------|
| [**quickstart.md**](docs/quickstart.md) | 5-minute setup & first deployment | Everyone (start here!) |
| [**prerequis.md**](docs/prerequis.md) | System requirements & pre-flight checks | First-time setup |
| [**architecture.md**](docs/architecture.md) | Infrastructure design & topology | Understanding the system |

### Configuration & Customization

| Document | Purpose | Audience |
|----------|---------|----------|
| [**variables.md**](docs/variables.md) | Complete variable reference & examples | Customizing your deployment |
| [**terraform.md**](docs/terraform.md) | Terraform configuration & providers | Understanding IaC |
| [**modules.md**](docs/modules.md) | Terraform module reference | Advanced customization |

### Deployment & Operations

| Document | Purpose | Audience |
|----------|---------|----------|
| [**cloud-init.md**](docs/cloud-init.md) | VM initialization & templates | VM setup details |
| [**scripts.md**](docs/scripts.md) | Helper scripts documentation | Automation & orchestration |
| [**ansible.md**](docs/ansible.md) | Ansible playbooks & inventory | Kubernetes configuration |

### Security & Maintenance

| Document | Purpose | Audience |
|----------|---------|----------|
| [**secrets.md**](docs/secrets.md) | Credential & SSH key management | Security & compliance |
| [**troubleshooting.md**](docs/troubleshooting.md) | Common issues & solutions | Problem-solving |

---

## 🚀 Quick Start

### 1. Prerequisites

- **Proxmox VE** (7.0+) with at least 64GB RAM and 500GB storage
- **Terraform** (1.0+) installed locally
- **SSH key** capability (Linux/macOS/WSL2 recommended)
- **Ubuntu cloud image** template prepared in Proxmox

For detailed setup, see [prerequis.md](docs/prerequis.md).

### 2. Clone & Initialize

```bash
# Clone the repository
git clone <repository-url>
cd projet-terraform-k8s

# Initialize Terraform
terraform init

# Create your configuration
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your Proxmox details
```

### 3. Deploy

```bash
# Plan the deployment
terraform plan

# Apply the configuration
terraform apply

# Wait 5-15 minutes for VMs to boot and cloud-init to run
```

### 4. Access Your Cluster

```bash
# SSH to the master node
ssh -i ./secrets/ansible_cluster_id_ed25519 ubuntu@192.168.1.11

# Check cluster status
kubectl get nodes
kubectl get pods -A

# Access kubeconfig
cat ~/.kube/config
```

For step-by-step instructions, see [quickstart.md](docs/quickstart.md).

---

## 📂 Project Structure

```
.
├── README.md                          # This file
├── .gitignore                         # Exclude secrets, state files
├── terraform.tfvars.example          # Configuration template
│
├── terraform/
│   ├── providers.tf                  # Provider configuration
│   ├── variables.tf                  # Input variables
│   ├── locals.tf                     # Local values
│   ├── outputs.tf                    # Output values
│   ├── vms.tf                        # VM module instantiation
│   ├── data.tf                       # Data sources (template lookup)
│   ├── write_private_key.tf         # SSH key local storage
│   ├── ansible_install.tf           # Ansible installation
│   ├── wait_and_run_ansible.tf      # Ansible orchestration
│   └── reboot_local_exec_with_script.tf  # VM reboot helper
│
├── modules/
│   └── proxmox_vm/
│       ├── main.tf                  # VM resource definition
│       ├── variables.tf             # Module variables
│       ├── outputs.tf               # Module outputs
│       └── required_providers_fix.tf  # Provider constraints
│
├── cloud-init/
│   ├── user_data.tpl                # VM bootstrap template
│   ├── user_data_ansible.tpl        # Ansible node variant
│   └── meta_data.tpl                # Metadata template
│
├── ansible/
│   ├── playbook.yml                 # Main Kubernetes configuration
│   └── inventory.ini                # Generated dynamically
│
├── scripts/
│   ├── wait_for_ssh.sh              # SSH polling utility
│   ├── install-ansible.sh           # Ansible setup script
│   ├── generate_and_copy_ansible.sh # Inventory generation & SCP
│   └── reboot_and_wait.sh           # Safe VM reboot utility
│
├── secrets/
│   ├── ansible_cluster_id_ed25519   # Generated SSH private key
│   └── ansible_cluster_id_ed25519.pub  # Generated SSH public key
│   └── .gitignore                   # Ensure secrets are not committed
│
└── docs/
    ├── README.md                    # This documentation index
    ├── quickstart.md                # Quick start guide
    ├── prerequis.md                 # Prerequisites & setup
    ├── architecture.md              # Infrastructure design
    ├── variables.md                 # Variable reference
    ├── terraform.md                 # Terraform configuration
    ├── modules.md                   # Module reference
    ├── cloud-init.md                # Cloud-init documentation
    ├── scripts.md                   # Scripts reference
    ├── ansible.md                   # Ansible documentation
    ├── secrets.md                   # Secrets management
    └── troubleshooting.md           # Troubleshooting guide
```

---

## 🛠️ Technology Stack

| Component | Version | Purpose |
|-----------|---------|---------|
| **Terraform** | 1.0+ | Infrastructure-as-Code provisioning |
| **Proxmox VE** | 7.0+ | Virtualization platform |
| **Ubuntu** | 20.04 / 22.04 | VM operating system |
| **Kubernetes** | 1.29 | Container orchestration |
| **Ansible** | 2.9+ | Configuration management |
| **containerd** | 1.x | Container runtime |
| **Flannel** | latest | CNI (Pod networking) |
| **kubeadm** | 1.29 | Kubernetes bootstrap utility |

---

## 🎓 Learning Outcomes

By working through this project, you'll understand:

### Infrastructure & Cloud
- ✅ How to provision VMs programmatically (Terraform)
- ✅ Proxmox VE fundamentals and API usage
- ✅ Cloud-init for automated VM initialization
- ✅ Network configuration (static IPs, gateways, CIDR notation)

### Kubernetes
- ✅ Kubernetes architecture (master, workers, control plane)
- ✅ kubeadm cluster initialization from scratch
- ✅ Container runtimes (containerd vs Docker)
- ✅ CNI (Container Network Interface) and Pod networking
- ✅ Node bootstrap and cluster joining

### DevOps & Automation
- ✅ Infrastructure-as-Code patterns and state management
- ✅ SSH key management and secure distribution
- ✅ Configuration management with Ansible
- ✅ Idempotence and reproducible deployments
- ✅ Debugging and troubleshooting infrastructure

### Security
- ✅ API token management and rotation
- ✅ SSH key generation and distribution
- ✅ Secure credential storage (secrets, .gitignore)
- ✅ Access control and permissions

---

## 🔄 Workflow Overview

```
1. terraform init
   ↓
2. terraform plan
   ↓
3. terraform apply
   ├─ Generate SSH keys (tls_private_key)
   ├─ Upload cloud-init templates to Proxmox
   ├─ Create 5 VMs from template
   ├─ Cloud-init initializes VMs (networking, packages, SSH)
   ├─ Reboot VMs and wait for cloud-init completion
   ├─ Populate SSH known_hosts on control node
   └─ Run Ansible playbook to configure Kubernetes
   ↓
4. Access cluster
   kubectl get nodes
   kubectl get pods -A
```

---

## 🐛 Current State & Known Limitations

### What Works ✅

- Automated VM provisioning via Terraform
- Cloud-init-based VM initialization
- SSH key generation and distribution
- Kubernetes cluster setup with kubeadm
- Flannel CNI for pod networking
- Ansible-based configuration management
- Idempotent deployments (safe to re-run)

### Known Issues & Workarounds ⚠️

| Issue | Workaround |
|-------|-----------|
| Cloud-init race condition (SSH key ownership) | Systemd oneshot service + reboot+wait script |
| Terraform line ending issues (CRLF) | Run `dos2unix` on scripts before deploying |
| SSH host key verification failures | Pre-populate known_hosts on control node |
| Terraform reboot timeout | Use custom reboot_and_wait.sh instead of Proxmox reboot |

See [troubleshooting.md](docs/troubleshooting.md) for detailed solutions.

---

## 📈 Areas for Improvement

This project is a learning platform and welcomes improvements! Here are key areas to enhance:

### Short-term Improvements

- [ ] **Multi-node Proxmox support**: Extend module to deploy VMs across multiple Proxmox nodes for HA
- [ ] **HA Kubernetes setup**: Configure multiple masters with load balancing (kube-vip, HAProxy)
- [ ] **Persistent storage**: Implement local storage, NFS, or Ceph integration
- [ ] **Monitoring stack**: Add Prometheus, Grafana, and Kubernetes monitoring
- [ ] **Ingress controller**: Deploy NGINX or Traefik for external access
- [ ] **CI/CD pipeline**: Add GitHub Actions or GitLab CI for automated deployments

### Medium-term Enhancements

- [ ] **Terraform modules marketplace**: Extract reusable modules for Proxmox VM, Kubernetes, etc.
- [ ] **Remote state backend**: Implement S3 or Terraform Cloud for state management
- [ ] **Secrets management**: Integrate HashiCorp Vault or sealed-secrets for production
- [ ] **Configuration templates**: Add Helm charts for common Kubernetes workloads
- [ ] **Cost analysis**: Implement cost tracking and optimization recommendations
- [ ] **Disaster recovery**: Automated backup and restore procedures

### Long-term Vision

- [ ] **Multi-cloud support**: Extend to AWS, Azure, GCP (not just Proxmox)
- [ ] **GitOps workflow**: Implement with ArgoCD or Flux for declarative deployments
- [ ] **Security hardening**: RBAC, network policies, pod security policies
- [ ] **Service mesh**: Integrate Istio or Linkerd for advanced networking
- [ ] **Machine learning ops**: Add MLflow, Kubeflow for ML workloads
- [ ] **Production-grade setup**: Full HA, backup, monitoring, compliance

---

## 📝 Contribution Guidelines

This is a **learning project**, and contributions are very welcome! Whether you're a beginner or experienced:

### Types of Contributions

- 🐛 **Bug fixes**: Found an issue? Submit a fix or report it
- 📚 **Documentation**: Clarify, expand, or improve any documentation
- 💡 **Features**: Add new features or improvements
- 🎓 **Educational content**: Add examples, tutorials, or explanations
- 🔒 **Security**: Identify and fix security issues
- ♻️ **Code quality**: Refactor, optimize, clean up code

### How to Contribute

1. **Fork** the repository
2. **Create** a feature branch: `git checkout -b feature/your-feature`
3. **Make** your changes
4. **Test** your changes (verify Terraform syntax, test scripts)
5. **Commit** with clear messages: `git commit -m "Add feature: description"`
6. **Push** to your fork: `git push origin feature/your-feature`
7. **Open a Pull Request** with a clear description

### Guidelines

- Keep commits small and focused
- Write clear commit messages
- Update documentation when adding features
- Test before submitting
- Be respectful and constructive

---

## ❓ Questions & Support

**This is a learning project!** If you have questions, improvements, or suggestions:

- 📖 **Check the docs first**: Most answers are in [docs/](docs/)
- 🤔 **Ask questions**: Open an issue to ask for clarification
- 💬 **Share feedback**: Suggest improvements or point out confusion
- 🐛 **Report bugs**: Help improve the project by reporting issues
- 📚 **Share knowledge**: If you learn something cool, document it!

**Remember**: Everyone is learning here. There are no stupid questions—if something is unclear, it's likely unclear to others too!

---

## 🎯 Next Steps

1. **Start here**: Read [quickstart.md](docs/quickstart.md) for a 5-minute setup
2. **Understand the system**: Review [architecture.md](docs/architecture.md)
3. **Customize your setup**: Modify [variables.md](docs/variables.md) for your environment
4. **Deploy**: Run `terraform apply` and watch your cluster come to life
5. **Explore**: SSH into nodes, inspect Kubernetes, experiment with deployments
6. **Learn**: Read through the other documentation to understand how everything works
7. **Improve**: Suggest improvements or contribute enhancements

---

## 📚 External Resources

### Terraform
- [Terraform Official Documentation](https://www.terraform.io/docs)
- [Terraform Best Practices](https://www.terraform.io/language)
- [bpg/proxmox Provider](https://github.com/bpg/terraform-provider-proxmox)

### Kubernetes
- [Kubernetes Official Docs](https://kubernetes.io/docs/)
- [kubeadm Installation Guide](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/)
- [Flannel CNI](https://github.com/flannel-io/flannel)
- [containerd Documentation](https://containerd.io/)

### Proxmox VE
- [Proxmox VE Documentation](https://pve.proxmox.com/wiki/)
- [Proxmox API](https://pve.proxmox.com/pve-docs/api-viewer/)
- [Cloud-init Support](https://pve.proxmox.com/wiki/Cloud-Init_Support)

### Ansible
- [Ansible Documentation](https://docs.ansible.com/)
- [Ansible Best Practices](https://docs.ansible.com/ansible/latest/user_guide/playbooks_best_practices.html)

### DevOps Learning
- [DevOps Handbook](https://itrevolution.com/the-devops-handbook/) — Industry best practices
- [Kubernetes in Action](https://www.manning.com/books/kubernetes-in-action) — Deep dive
- [Terraform Up & Running](https://www.oreilly.com/library/view/terraform-up-and/9781492046899/) — IaC patterns

---

## 📄 License

This project is provided as-is for educational purposes. Feel free to use, modify, and learn from it!

---

## 🙏 Acknowledgments

- **Proxmox Team**: For excellent virtualization platform
- **HashiCorp**: For Terraform and infrastructure-as-code tools
- **Kubernetes Community**: For container orchestration excellence
- **Cloud-init Team**: For VM automation capabilities
- **You**: For learning and improving this project!

---

## 📞 Contact & Support

- **Questions?** Open an issue
- **Suggestions?** Create a discussion
- **Found a bug?** Submit a bug report
- **Want to contribute?** Send a pull request
- **Want to collaborate?** Reach out!

---

## ⭐ Show Your Support

If this project helps you learn, consider:

- ⭐ **Starring** the repository
- 📤 **Sharing** with others learning DevOps
- 📝 **Contributing** improvements
- 💬 **Providing feedback**
- 🙋 **Helping others** in discussions

---

## 🚀 Ready to Start?

👉 **Go to [quickstart.md](docs/quickstart.md) to begin your Kubernetes journey!**

**Happy learning! 🎉**

---

 
**Status:** Active Learning Project  
**Version:** 1.0

---

*This is a community learning project. Made with ❤️ for aspiring DevOps engineers.*
