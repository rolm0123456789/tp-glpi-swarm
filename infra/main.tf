# =============================================
#  Infrastructure GLPI Swarm - VMs VirtualBox
#  Pilotage via Vagrant (plus fiable que terra-farm/virtualbox)
# =============================================

locals {
  # IPs statiques attribuées aux VMs (192.168.56.101, .102, .103)
  node_ips = [for i in range(var.node_count) : "192.168.56.${101 + i}"]
}

# --- Création des VMs via Vagrant ---
resource "null_resource" "vagrant_up" {
  triggers = {
    node_count = var.node_count
  }

  provisioner "local-exec" {
    command     = "vagrant up --parallel 2>&1"
    working_dir = path.module
    environment = {
      TF_VAR_node_count = var.node_count
    }
  }

  provisioner "local-exec" {
    when        = destroy
    command     = "vagrant destroy -f 2>/dev/null || true"
    working_dir = path.module
  }
}

# --- Génération de l'inventaire Ansible ---
resource "local_file" "ansible_inventory" {
  depends_on = [null_resource.vagrant_up]

  content = templatefile("${path.module}/templates/inventory.tpl", {
    nodes = local.node_ips
  })
  filename        = "${path.module}/../config/inventory.ini"
  file_permission = "0644"
}

# --- Outputs ---
output "manager_ip" {
  description = "IP du noeud Manager"
  value       = local.node_ips[0]
}

output "worker_ips" {
  description = "IPs des noeuds Workers"
  value       = slice(local.node_ips, 1, var.node_count)
}

output "all_ips" {
  description = "Toutes les IPs des noeuds"
  value       = local.node_ips
}
