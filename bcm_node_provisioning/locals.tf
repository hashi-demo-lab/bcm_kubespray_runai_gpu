# BCM Node Provisioning Module - Local Values
#
# Computed values: data source filtering, UUID lookups, node maps.

locals {
  # ==========================================================================
  # SOFTWARE IMAGE UUID
  # ==========================================================================

  software_image_uuid = (
    length(data.bcm_cmpart_softwareimages.target.images) > 0
    ? data.bcm_cmpart_softwareimages.target.images[0].uuid
    : null
  )

  # ==========================================================================
  # NETWORK LOOKUPS (client-side filtering by name)
  # ==========================================================================

  management_network_matches = [
    for net in data.bcm_cmnet_networks.all.networks :
    net if net.name == var.management_network_name
  ]
  management_network_id = (
    length(local.management_network_matches) > 0
    ? local.management_network_matches[0].id
    : null
  )

  oob_network_matches = [
    for net in data.bcm_cmnet_networks.all.networks :
    net if net.name == var.oob_network_name
  ]
  oob_network_id = (
    length(local.oob_network_matches) > 0
    ? local.oob_network_matches[0].id
    : null
  )

  # ==========================================================================
  # CATEGORY UUID LOOKUPS
  # ==========================================================================

  # Collect unique category names from all nodes
  unique_category_names = toset([for node in var.nodes : node.category])

  # Map category name → UUID from data source lookups
  category_uuid_map = {
    for name, ds in data.bcm_cmdevice_categories.lookup :
    name => length(ds.categories) > 0 ? ds.categories[0].uuid : null
  }

  # ==========================================================================
  # NODE PROCESSING
  # ==========================================================================

  # Ordered list of node hostnames (for sequential provisioning)
  ordered_node_keys = sort(keys(var.nodes))

  # Nodes eligible for power actions
  power_action_nodes = var.enable_power_action ? var.nodes : {}

  # ==========================================================================
  # NODE STATUS (post-provision query)
  # ==========================================================================

  # Map queried node data by hostname for easy lookup
  queried_nodes_by_hostname = {
    for node in try(data.bcm_cmdevice_nodes.status.nodes, []) :
    node.hostname => node
  }

  # Per-node provisioning status
  node_status = {
    for hostname, config in var.nodes :
    hostname => {
      found   = contains(keys(local.queried_nodes_by_hostname), hostname)
      state   = try(local.queried_nodes_by_hostname[hostname].state, "not_found")
      ip      = try(local.queried_nodes_by_hostname[hostname].ip, null)
      success = try(local.queried_nodes_by_hostname[hostname].state, "") == "UP"
    }
  }
}
