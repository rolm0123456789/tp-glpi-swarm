resource "virtualbox_vm" "node" {
  count     = 3
  name      = format("glpi-node-%02d", count.index + 1)
  image     = "https://app.vagrantup.com/bento/boxes/ubuntu-20.04/versions/202212.11.0/providers/virtualbox.box"
  cpus      = 2
  memory    = "2048 MiB"
  
  network_adapter {
    type           = "nat"
  }

  network_adapter {
    type           = "hostonly"
    host_interface = "vboxnet0"
  }
}

resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/templates/inventory.tpl", {
    nodes = virtualbox_vm.node.*.network_adapter.1.ipv4_address
  })
  filename = "../config/inventory.ini"
}