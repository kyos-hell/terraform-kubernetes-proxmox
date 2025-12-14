// Génère une paire ED25519 pour le cluster (private_key sera dans l'état)
resource "tls_private_key" "ansible" {
  algorithm = "ED25519"
}

// Génère un UUID unique par VM (pour instance-id)
resource "random_uuid" "vm_ids" {
  for_each = { for vm in var.vms : vm.name => vm }
}

// Crée un snippet user-data par VM (choisit template ansible ou generic selon role)
resource "proxmox_virtual_environment_file" "cloud_user_config" {
  for_each     = { for vm in var.vms : vm.name => vm }
  content_type = "snippets"
  datastore_id = "local"
  node_name    = var.target_node

  source_raw {
    data = templatefile(
      "${path.module}/cloud-init/${each.value.role == "ansible" ? "user_data_ansible.tpl" : "user_data.tpl"}",
      {
        hostname = each.value.name,
        domain   = var.domain,
        // Ensure no trailing newline in public key
        ssh_pub = chomp(tls_private_key.ansible.public_key_openssh),
        // If role == "ansible", provide the private key already indented for YAML block scalar
        // Use chomp + replace to ensure consistent indentation
        ssh_priv = each.value.role == "ansible" ? format("%s%s", "      ", replace(chomp(tls_private_key.ansible.private_key_openssh), "\n", "\n      ")) : ""
      }
    )

    file_name = "${each.value.name}.${var.domain}-ci-user.yml"
  }
}

// Crée un snippet meta-data par VM, utilise random_uuid pour instance-id (unique par VM)
resource "proxmox_virtual_environment_file" "cloud_meta_config" {
  for_each     = { for vm in var.vms : vm.name => vm }
  content_type = "snippets"
  datastore_id = "local"
  node_name    = var.target_node

  source_raw {
    data = templatefile(
      "${path.module}/cloud-init/meta_data.tpl",
      {
        // use the random uuid result we created per-vm
        instance_id = random_uuid.vm_ids[each.value.name].result
      }
    )

    file_name = "${each.value.name}.${var.domain}-ci-meta_data.yml"
  }
}
