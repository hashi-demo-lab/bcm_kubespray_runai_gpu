# Fetch all nodes from BCM
data "bcm_cmdevice_nodes" "all" {}

# Filter nodes to only include our target nodes
locals {
  # Filter nodes by hostname matching our target list
  target_nodes = {
    for node in data.bcm_cmdevice_nodes.all.nodes :
    node.hostname => node
    if contains(var.target_nodes, node.hostname)
  }

  # Extract primary IP from first interface with an IP address
  node_ips = {
    for hostname, node in local.target_nodes :
    hostname => try(
      [for iface in node.interfaces : iface.ip if iface.ip != null && iface.ip != ""][0],
      null
    )
  }

  # Build Ansible inventory structure
  ansible_inventory = {
    all = {
      hosts = {
        for hostname, node in local.target_nodes :
        hostname => {
          ansible_host = local.node_ips[hostname]
          ip           = local.node_ips[hostname]
          access_ip    = local.node_ips[hostname]
          bcm_uuid     = node.uuid
          bcm_mac      = node.mac
          bcm_type     = node.child_type
          bcm_roles = [
            for role in node.roles :
            role.name if role.name != null
          ]
        }
      }
      children = {
        compute_nodes = {
          hosts = {
            for hostname in keys(local.target_nodes) :
            hostname => {}
          }
        }
      }
      vars = {
        ansible_user                 = var.ansible_user
        ansible_ssh_private_key_file = var.ansible_ssh_private_key_file
        ansible_become               = true
        ansible_become_method        = "sudo"
      }
    }
  }
}

# Generate YAML inventory file
resource "local_file" "ansible_inventory" {
  content  = yamlencode(local.ansible_inventory)
  filename = "${path.module}/inventory.yml"

  file_permission = "0644"
}

# Generate INI-style inventory file (alternative format)
resource "local_file" "ansible_inventory_ini" {
  content = templatefile("${path.module}/templates/inventory.ini.tftpl", {
    nodes                        = local.target_nodes
    node_ips                     = local.node_ips
    ansible_user                 = var.ansible_user
    ansible_ssh_private_key_file = var.ansible_ssh_private_key_file
  })
  filename = "${path.module}/inventory.ini"

  file_permission = "0644"
}
