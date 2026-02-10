resource "virtualbox_vm" "node" {
  count     = var.node_count
  name      = format("glpi-node-%02d", count.index + 1)
  image     = "https://app.vagrantup.com/ubuntu/boxes/bionic64/versions/20180903.0.0/providers/virtualbox.box"
  cpus      = 2
  memory    = "2048 MiB"
  
  network_adapter {
    type           = "hostonly"
    host_interface = "vboxnet1" # Assure-toi d'avoir créé ce réseau dans VirtualBox
  }
}

resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/templates/inventory.tpl", {
    nodes = virtualbox_vm.node.*.network_adapter.0.ipv4_address
  })
  filename = "../config/inventory.ini"
}