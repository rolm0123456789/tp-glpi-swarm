[managers]
manager ansible_host=${nodes[0]} ansible_user=vagrant ansible_ssh_private_key_file=${ssh_private_key} ansible_become_pass=vagrant

[workers]
worker1 ansible_host=${nodes[1]} ansible_user=vagrant ansible_ssh_private_key_file=${ssh_private_key} ansible_become_pass=vagrant
worker2 ansible_host=${nodes[2]} ansible_user=vagrant ansible_ssh_private_key_file=${ssh_private_key} ansible_become_pass=vagrant

[swarm:children]
managers
workers