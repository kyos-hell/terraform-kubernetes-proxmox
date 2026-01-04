# Security Policy

## 🔐 Reporting Security Vulnerabilities

If you discover a security vulnerability in this project, please **DO NOT** open a public GitHub issue. Instead:

1. **Email us privately** with details of the vulnerability
2. Include steps to reproduce (if applicable)
3. Allow 30 days for us to respond and patch before public disclosure

> Contact: Open a private security advisory on GitHub (Settings → Security advisories)

---

## 🛡️ Security Best Practices for Users

### ⚠️ Never Commit Secrets

This project is configured with comprehensive `.gitignore` rules to prevent accidental secret commits. **However**, it's YOUR responsibility to ensure:

- ✅ **Never hardcode** API tokens, passwords, or private keys
- ✅ **Use environment variables** for sensitive data
- ✅ **Keep `.gitignore` updated** if you add new secret files
- ✅ **Review staged changes** before committing (`git diff --cached`)

### 🔑 Credential Management

#### Proxmox API Token
```bash
# ❌ DON'T: Hardcode in variables.tf
variable "api_token" {
  default = "user@pam!token=abc123..."  # ❌ NEVER
}

# ✅ DO: Use environment variables
export PROXMOX_VE_API_TOKEN="user@pam!token=abc123..."
export TF_VAR_api_token="${PROXMOX_VE_API_TOKEN}"
```

#### SSH Keys
```bash
# ✅ Keys are automatically generated in ./secrets/ (Git-ignored)
# ✅ Keep ./secrets/ directory safe and backed up
# ✅ Never share private keys

# To verify key permissions:
ls -la ./secrets/
# Should show: -rw------- (0600)
```

#### ArgoCD Admin Password
```bash
# ✅ Password is auto-generated at runtime
# ✅ Retrieve it post-deployment:
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# ✅ IMMEDIATELY change password after first login
```

---

## 📋 What's Already Protected

This project includes security controls:

| Component | Protection |
|-----------|-----------|
| Private Keys | Excluded via `.gitignore`, dynamically generated |
| API Tokens | Marked `sensitive = true`, environment-based |
| Terraform State | `*.tfstate*` excluded from Git |
| Cloud-init Data | Templated, no hardcoded secrets |
| Ansible Vault | `.ansible_vault_pass` excluded |
| Passwords | Retrieved at runtime, not stored |

---

## ✅ Pre-Deployment Checklist

Before using this project:

- [ ] Review [SECURITY_AUDIT.md](SECURITY_AUDIT.md) for complete audit
- [ ] Ensure `.gitignore` is intact and not modified
- [ ] Set up environment variables (don't hardcode credentials)
- [ ] Test in a non-production environment first
- [ ] Review the Terraform plan before applying: `terraform plan`
- [ ] Keep Kubernetes versions up to date

---

## 🔄 Keeping Dependencies Updated

This project uses multiple open-source components. Keep them secure by:

### Kubernetes & Container Runtime
```bash
# Monitor for security updates
# Update kubernetes_version in ansible/playbook.yml
kubernetes_version: "1.29"  # Check kubernetes.io for latest
```

### ArgoCD
```bash
# Check latest stable version:
# https://github.com/argoproj/argo-cd/releases
```

### Calico CNI
```bash
# Current version: v3.29.1
# Check for updates: https://github.com/projectcalico/calico/releases
```

### MetalLB
```bash
# Keep Helm chart updated
helm repo update
helm search repo metallb
```

---

## 🚨 Common Security Mistakes to Avoid

### ❌ Don't:
- Hardcode passwords or API tokens in code
- Commit `.tfstate` files to Git
- Share private keys via email or chat
- Leave default credentials unchanged
- Expose kubeconfig files publicly
- Use plain HTTP for sensitive endpoints
- Commit environment files (`.env`, `.env.local`)
- Store encrypted vault passwords in Git

### ✅ Do:
- Use `sensitive = true` in Terraform variables
- Provide secrets via environment variables
- Back up SSH keys securely (offline or encrypted vault)
- Change default credentials immediately after deployment
- Protect kubeconfig file permissions (0600)
- Use HTTPS for all connections
- Document where to find credentials (but not the values themselves)
- Store vault passwords in secure password managers

---

## 🔍 Audit Trail

### What Was Audited
- ✅ All 15 Terraform files
- ✅ 3 cloud-init templates
- ✅ 1065-line Ansible playbook
- ✅ 11 documentation files
- ✅ `.gitignore` configuration
- ✅ Variable definitions
- ✅ Output values

### Audit Results
**Status:** ✅ **SECURE FOR PUBLIC RELEASE**

See [SECURITY_AUDIT.md](SECURITY_AUDIT.md) for complete details.

---

## 📚 Additional Resources

- [OWASP Top 10 - Secrets Management](https://owasp.org/www-project-top-ten/)
- [NIST Cybersecurity Framework](https://www.nist.gov/cyberframework)
- [Terraform Security Best Practices](https://www.terraform.io/docs/cloud/security)
- [Kubernetes Security Best Practices](https://kubernetes.io/docs/concepts/security/)
- [ArgoCD Security](https://argo-cd.readthedocs.io/en/stable/security/)

---

## 📞 Questions?

If you have security-related questions:

1. Check [docs/troubleshooting.md](troubleshooting.md)
2. Review [SECURITY_AUDIT.md](SECURITY_AUDIT.md)
3. Open a non-sensitive GitHub discussion

---

**Last Updated:** January 4, 2026  
**Status:** Ready for Public Release ✅

