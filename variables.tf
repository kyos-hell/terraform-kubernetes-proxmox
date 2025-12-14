variable "proxmox_endpoint" {
  description = "Proxmox VE API endpoint (ex: https://10.0.0.1:8006/). Can also be provided via PROXMOX_VE_ENDPOINT env var."
  type        = string
  default     = "https://your-proxmox:8006/"
}

variable "api_token" {
  description = "Token to connect Proxmox API"
  type        = string
  sensitive   = true
}

variable "ssh_key_path" {
  description = "Path to the private key used to SSH to VMs (kept in ./secrets/ by default)."
  type        = string
  default     = "./secrets/ansible_cluster_id_ed25519"
}

variable "ssh_user" {
  description = "SSH user for connecting to VMs."
  type        = string
  default     = "ubuntu"
}

variable "target_node" {
  description = "Proxmox node name"
  type        = string
  default     = "lab-training-day"
}

variable "onboot" {
  description = "Auto start VM when node is start"
  type        = bool
  default     = true
}

variable "target_node_domain" {
  description = "Proxmox node domain (optionnel)"
  type        = string
  default     = ""
}

variable "domain" {
  description = "VM domain"
  type        = string
  default     = "training.local"
}

variable "vm_tags" {
  description = "VM tags"
  type        = list(string)
  default     = ["ubuntu"]
}

variable "template_tag" {
  description = "Template tag utilisé pour filtrer le template"
  type        = string
  default     = "test"
}

variable "vm_user" {
  description = "User created/configuré via cloud-init (si utilisé dans user_data)"
  type        = string
  sensitive   = true
  default     = "sysadmin"
}

variable "system_disk" {
  description = "System disk (must match template size)"
  type = object({
    storage = string
    size    = number
  })
  default = {
    storage = "local"
    size    = 50
  }
}

variable "additionnal_disks" {
  description = "Additionnal data disks"
  type = list(object({
    storage = string
    size    = number
  }))
  default = []
}

variable "network_bridge" {
  description = "Proxmox bridge used for the main network interface"
  type        = string
  default     = "vmbr2"
}

variable "network_prefix" {
  description = "CIDR prefix length for VM IPv4 addresses"
  type        = number
  default     = 24
}

variable "gateway_ipv4" {
  description = "Default IPv4 gateway for VMs"
  type        = string
  default     = "192.168.1.254"
}

variable "vms" {
  description = "Liste des VMs du cluster k8s"

  type = list(object({
    name   = string
    ip     = string
    cpu    = number
    memory = number
    role   = string
  }))

  default = [
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
    },
  ]
}

variable "write_private_key_local" {
  description = "If true, write the generated private key to local 'secrets/' dir (lab convenience)."
  type        = bool
  default     = true
}
