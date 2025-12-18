# VM Resource Declarations
# Feature: vSphere VM Provisioning with Kubernetes Deployment via Kubespray
# Spec: /workspace/specs/001-vsphere-k8s-kubespray/spec.md



# Query all cluster nodes
data "bcm_cmdevice_nodes" "all" {}

# Output all node information
output "all_nodes" {
  value = data.bcm_cmdevice_nodes.all.nodes
}



# Create inventory map
output "node_inventory" {
  value = {
    for node in data.bcm_cmdevice_nodes.all.nodes :
    node.hostname => {
      uuid       = node.uuid
      type       = node.child_type
      mac        = node.mac
      interfaces = length(node.interfaces)
      roles = [
        for role in node.roles :
        role.name if role.name != null
      ]
    }
  }
}