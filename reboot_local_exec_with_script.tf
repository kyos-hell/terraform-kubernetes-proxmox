resource "null_resource" "reboot_ansible" {
  depends_on = [module.vm["ansible-01"]] # adapte si l'address du module est différent

  triggers = {
    ansible_ip = local.ansible_ip
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    # Wrap call in timeout (15 minutes = 900s) to avoid hanging indefinitely.
    command = "timeout 900 ${path.module}/scripts/reboot_and_wait.sh \"${local.ansible_ip}\" \"${var.ssh_key_path}\" \"${var.ssh_user}\" 22 600"
  }
}
