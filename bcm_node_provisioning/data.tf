# BCM Node Provisioning Module - Data Sources
#
# Lookups for pre-existing BCM infrastructure: images, networks, categories.

# Software images — filter by exact name
data "bcm_cmpart_softwareimages" "target" {
  name = var.software_image_name
}

# Networks — all (client-side filter in locals.tf)
data "bcm_cmnet_networks" "all" {}

# Categories — one lookup per unique category name referenced by nodes
data "bcm_cmdevice_categories" "lookup" {
  for_each = local.unique_category_names
  name     = each.value
}

# Available roles — for validation reference
data "bcm_cmdevice_roles" "all" {}

# Post-provision node status query
data "bcm_cmdevice_nodes" "status" {
  depends_on = [
    bcm_cmdevice_device.nodes,
  ]
}
