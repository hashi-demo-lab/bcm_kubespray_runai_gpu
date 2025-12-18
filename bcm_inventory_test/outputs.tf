output "discovered_nodes" {
  description = "All nodes discovered from BCM"
  value = [
    for node in data.bcm_cmdevice_nodes.all.nodes :
    {
      hostname = node.hostname
      uuid     = node.uuid
      type     = node.child_type
    }
  ]
}

output "target_nodes" {
  description = "Filtered target nodes with their details"
  value = {
    for hostname, node in local.target_nodes :
    hostname => {
      uuid       = node.uuid
      type       = node.child_type
      mac        = node.mac
      ip         = local.node_ips[hostname]
      interfaces = length(node.interfaces)
      roles = [
        for role in node.roles :
        role.name if role.name != null
      ]
    }
  }
}

output "ansible_inventory" {
  description = "Generated Ansible inventory structure"
  value       = local.ansible_inventory
}

output "inventory_yaml_path" {
  description = "Path to generated YAML inventory file"
  value       = local_file.ansible_inventory.filename
}

output "inventory_ini_path" {
  description = "Path to generated INI inventory file"
  value       = local_file.ansible_inventory_ini.filename
}
