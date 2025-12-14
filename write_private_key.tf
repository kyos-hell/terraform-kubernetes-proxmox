# (Optionnel) écrit la clé privée en local sur le contrôleur pour usages locaux.
# NE PAS committer ./secrets dans Git. Assure-toi que ./secrets est dans .gitignore.
resource "local_file" "ansible_private_key" {
  count           = var.write_private_key_local ? 1 : 0
  content         = tls_private_key.ansible.private_key_openssh
  filename        = "${path.module}/secrets/ansible_cluster_id_ed25519"
  file_permission = "0600"
}
