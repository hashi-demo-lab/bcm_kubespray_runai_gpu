# BCM Data Source Outputs — All values exposed for inspection

# ==========================================================================
# SOFTWARE IMAGES
# ==========================================================================

output "software_images_all" {
  description = "All software images registered in BCM"
  value       = data.bcm_cmpart_softwareimages.all.images
}

# ==========================================================================
# CATEGORIES
# ==========================================================================

output "categories_all" {
  description = "All device categories registered in BCM"
  value       = data.bcm_cmdevice_categories.all.categories
}

# ==========================================================================
# NETWORKS
# ==========================================================================

output "networks_all" {
  description = "All networks configured in BCM"
  value       = data.bcm_cmnet_networks.all.networks
}

# ==========================================================================
# NODES
# ==========================================================================

output "nodes_all" {
  description = "All nodes registered in BCM"
  value       = data.bcm_cmdevice_nodes.all.nodes
}

# ==========================================================================
# ROLES
# ==========================================================================

output "roles_all" {
  description = "All roles available in BCM"
  value       = data.bcm_cmdevice_roles.all.roles
}
