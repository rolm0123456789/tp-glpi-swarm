#cloud-config
hostname: ${hostname}
fqdn: ${hostname}.glpi.local
manage_etc_hosts: true

users:
  - name: vagrant
    plain_text_passwd: vagrant
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    lock_passwd: false
    groups: [sudo, adm]
    ssh_authorized_keys:
      - ${ssh_public_key}

ssh_pwauth: true

chpasswd:
  expire: false

package_update: false
package_upgrade: false

runcmd:
  - sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
  - sed -i 's/^#\?KbdInteractiveAuthentication.*/KbdInteractiveAuthentication yes/' /etc/ssh/sshd_config
  - systemctl restart ssh
