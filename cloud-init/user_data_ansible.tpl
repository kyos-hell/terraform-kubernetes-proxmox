#cloud-config
hostname: ${hostname}
fqdn: ${hostname}.${domain}
manage_etc_hosts: true
package_upgrade: true

users:
  - default
  - name: ubuntu
    sudo: ALL=(ALL) NOPASSWD:ALL
    ssh_authorized_keys:
      - "${ssh_pub}"

ssh_pwauth: false

write_files:
  - path: /home/ubuntu/.ssh/id_ansible
    owner: root:root
    permissions: '0600'
    content: |
${ssh_priv}
  - path: /home/ubuntu/.ssh/config
    owner: root:root
    permissions: '0600'
    content: |
      Host *
        IdentityFile /home/ubuntu/.ssh/id_ansible
        IdentitiesOnly yes
        StrictHostKeyChecking ask

  - path: /usr/local/bin/fix-ssh-owner.sh
    owner: root:root
    permissions: '0755'
    content: |
      #!/bin/sh
      # Wait for ubuntu user to exist, then fix .ssh ownership and permissions.
      for i in $(seq 1 120); do
        id ubuntu >/dev/null 2>&1 && break || sleep 1
      done
      mkdir -p /home/ubuntu/.ssh || true
      chown -R ubuntu:ubuntu /home/ubuntu/.ssh || true
      chmod 700 /home/ubuntu/.ssh || true
      if [ -f /home/ubuntu/.ssh/id_ansible ]; then
        chmod 600 /home/ubuntu/.ssh/id_ansible || true
        chown ubuntu:ubuntu /home/ubuntu/.ssh/id_ansible || true
      fi
      # populate known_hosts defensively
      ssh-keyscan -H 192.168.1.11 >> /home/ubuntu/.ssh/known_hosts 2>/dev/null || true
      chown ubuntu:ubuntu /home/ubuntu/.ssh/known_hosts || true

  - path: /etc/systemd/system/fix-ssh-owner.service
    owner: root:root
    permissions: '0644'
    content: |
      [Unit]
      Description=Fix /home/ubuntu/.ssh ownership and permissions
      After=cloud-final.target network.target local-fs.target
      Wants=network-online.target

      [Service]
      Type=oneshot
      ExecStart=/usr/local/bin/fix-ssh-owner.sh
      RemainAfterExit=yes

      [Install]
      WantedBy=cloud-final.target

runcmd:
  - [ sh, -c, 'systemctl daemon-reload || true' ]
  - [ sh, -c, 'systemctl enable --now fix-ssh-owner.service || systemctl start fix-ssh-owner.service || true' ]
  - [ sh, -c, 'mkdir -p /home/ubuntu/.ssh || true' ]
  # minimal fallback (no chown here to avoid races)
  - [ sh, -c, 'chmod 700 /home/ubuntu/.ssh || true' ]
  - [ sh, -c, 'if [ -f /home/ubuntu/.ssh/id_ansible ]; then chmod 600 /home/ubuntu/.ssh/id_ansible || true; fi' ]

