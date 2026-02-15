# =============================================
#  Infrastructure GLPI Swarm - KVM/libvirt
#  Provider Terraform natif dmacvicar/libvirt
# =============================================

locals {
  node_ips   = [for i in range(var.node_count) : "192.168.56.${101 + i}"]
  node_names = [for i in range(var.node_count) : "glpi-node-${format("%02d", i + 1)}"]
}

# -----------------------------------------------
#  1. Réseau NAT dédié au cluster
# -----------------------------------------------
resource "libvirt_network" "glpi_swarm" {
  name      = "glpi-swarm"
  mode      = "nat"
  domain    = "glpi.local"
  addresses = ["192.168.56.0/24"]
  autostart = true

  dhcp {
    enabled = true
  }

  dns {
    enabled = true
  }
}

# -----------------------------------------------
#  2. Volume de base Ubuntu 22.04 (cloud image)
# -----------------------------------------------
resource "libvirt_volume" "ubuntu_base" {
  name   = "ubuntu-22.04-cloudimg.qcow2"
  pool   = "default"
  source = var.base_image_url
  format = "qcow2"
}

# -----------------------------------------------
#  3. Disques des VMs (clonés depuis la base)
# -----------------------------------------------
resource "libvirt_volume" "vm_disk" {
  count          = var.node_count
  name           = "${local.node_names[count.index]}.qcow2"
  pool           = "default"
  base_volume_id = libvirt_volume.ubuntu_base.id
  size           = var.disk_size
  format         = "qcow2"
}

# -----------------------------------------------
#  4. Cloud-init (configuration initiale des VMs)
# -----------------------------------------------
resource "libvirt_cloudinit_disk" "vm_init" {
  count = var.node_count
  name  = "${local.node_names[count.index]}-init.iso"
  pool  = "default"
  user_data = templatefile("${path.module}/templates/cloud_init.tpl", {
    hostname       = local.node_names[count.index]
    ssh_public_key = var.ssh_public_key
  })
}

# -----------------------------------------------
#  5. Machines virtuelles (KVM)
# -----------------------------------------------
resource "libvirt_domain" "vm" {
  count   = var.node_count
  name    = local.node_names[count.index]
  memory  = var.vm_memory
  vcpu    = var.vm_cpus
  running = true

  cloudinit = libvirt_cloudinit_disk.vm_init[count.index].id

  cpu {
    mode = "host-passthrough"
  }

  network_interface {
    network_id     = libvirt_network.glpi_swarm.id
    addresses      = [local.node_ips[count.index]]
    wait_for_lease = true
  }

  disk {
    volume_id = libvirt_volume.vm_disk[count.index].id
  }

  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }

  graphics {
    type        = "vnc"
    listen_type = "address"
    autoport    = true
  }
}

# -----------------------------------------------
#  6. Inventaire Ansible (généré automatiquement)
# -----------------------------------------------
resource "local_file" "ansible_inventory" {
  depends_on = [libvirt_domain.vm]

  content = templatefile("${path.module}/templates/inventory.tpl", {
    nodes           = local.node_ips
    ssh_private_key = var.ssh_private_key_path
  })
  filename        = "${path.module}/../config/inventory.ini"
  file_permission = "0644"
}

# -----------------------------------------------
#  Outputs
# -----------------------------------------------
output "manager_ip" {
  description = "IP du nœud Manager"
  value       = local.node_ips[0]
}

output "worker_ips" {
  description = "IPs des nœuds Workers"
  value       = slice(local.node_ips, 1, var.node_count)
}

output "all_ips" {
  description = "Toutes les IPs des nœuds"
  value       = local.node_ips
}
