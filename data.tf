# Sélection du template via les tags (par ex. "template" + var.template_tag)
data "proxmox_virtual_environment_vms" "template" {
  node_name = var.target_node
  tags      = ["template", var.template_tag]
}
