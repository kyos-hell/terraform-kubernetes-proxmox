resource "null_resource" "install_ansible" {
  # ensure VM exists and reboot/wait has completed
  depends_on = [
    module.vm["ansible-01"],
    null_resource.reboot_ansible
  ]

  triggers = {
    ansible_ip = local.ansible_ip
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]

    # Send the local script to the remote host (strip CR if present), decode and run it under sudo.
    # - sed 's/\r$//' removes CRLF locally if present (prevents the CRLF -> bash errors).
    # - base64 -w0 builds a single-line payload for robust transport.
    # - remote side decodes and pipes into `sudo bash -s`.
    #
    # Notes:
    #  - ${path.root} ensures the script is read from repo root.
    #  - ${var.ssh_key_path}, ${var.ssh_user}, ${local.ansible_ip} come from your shared vars/locals.
    command = "sed 's/\\r$//' \"${path.root}/scripts/install-ansible.sh\" | base64 -w0 | ssh -oBatchMode=yes -oStrictHostKeyChecking=no -i '${var.ssh_key_path}' '${var.ssh_user}@${local.ansible_ip}' \"base64 -d | sudo bash -s\""
  }
}
