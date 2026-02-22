# BCM Node Provisioning Module - Input Variables
#
# This file defines all input variables for the module with validation rules
# and security controls per constitution requirements.

# ============================================================================
# FOUNDATIONAL VARIABLES - Required for all user stories
# ============================================================================

variable "software_image_name" {
  description = "Name of the BCM software image to use for node provisioning. Must match an existing image name exactly (case-sensitive). Example: 'ubuntu-22.04-nvidia-535'"
  type        = string

  validation {
    condition     = length(var.software_image_name) > 0
    error_message = "Software image name cannot be empty. Provide the exact name of a BCM software image (run: cmsh -c 'softwareimage; list')"
  }
}

variable "management_network_name" {
  description = "Name of the BCM management network for PXE boot and provisioning. Must match an existing network name exactly (case-sensitive). Example: 'dgxnet'"
  type        = string

  validation {
    condition     = length(var.management_network_name) > 0
    error_message = "Management network name cannot be empty. Provide the exact name of a BCM network (run: cmsh -c 'network; list')"
  }
}

variable "oob_network_name" {
  description = <<-EOT
    Name of the BCM-registered out-of-band network (e.g., "ipminet").

    ARCHITECTURE NOTE: This value is sent to the BCM head node API as part of
    device registration so BCM knows which network each node's IPMI interface
    is on. Terraform NEVER contacts IPMI/BMC addresses (10.229.10.x) directly.
    All communication flows exclusively through the BCM head node API endpoint.
  EOT
  type        = string
  default     = "ipminet"

  validation {
    condition     = length(var.oob_network_name) > 0
    error_message = "OOB network name cannot be empty."
  }
}

# NOTE: bmc_username / bmc_password are intentionally absent.
# Terraform does NOT authenticate directly to node IPMI/BMC interfaces.
# The BCM head node manages all IPMI power and provisioning operations
# internally. Only the single BCM head node API endpoint is needed.

# ============================================================================
# USER STORY 1: Initial Bare Metal Node Provisioning
# ============================================================================

variable "nodes" {
  description = <<-EOT
    Map of bare metal nodes to provision. Key = hostname, Value = node configuration object.
    
    Each node must include:
    - mac: Primary network interface MAC address (format: "00:11:22:33:44:55") for PXE boot
    - category: Provisioning category name (existing or custom)
    - management_ip: Static IP on the management network (REQUIRED — prevents DHCP fallback)
    - roles: List of role names to assign (e.g., ["compute", "gpu"], ["control_plane"])
    
    Optional per-node fields:
    - ipmi_ip: BMC/IPMI IP address (must be reachable from BCM headnode) — needed for IPMI power control
    - interfaces: Map of additional network interfaces
    
    Note: BMC MAC address is NOT required by the BCM API for BMC interfaces.
    The API only needs the IPMI IP and network reference. MAC is only required
    for physical interfaces (PXE boot NIC).
    
    Example (minimal — without IPMI):
    {
      "dgx-05" = {
        mac            = "10:70:FD:BD:73:4D"
        category       = "default"
        management_ip  = "10.184.162.109"
        roles          = ["compute"]
      }
    }
    
    Example (full — with IPMI):
    {
      "dgx-05" = {
        mac            = "10:70:FD:BD:73:4D"
        ipmi_ip        = "10.229.10.11"
        category       = "default"
        management_ip  = "10.184.162.109"
        roles          = ["compute"]
      }
    }
  EOT
  type = map(object({
    mac           = string
    ipmi_ip       = optional(string)
    category      = string
    management_ip = string
    interfaces = optional(map(object({
      type     = string
      mac      = optional(string)
      network  = string
      bootable = optional(bool, false)
      ip       = optional(string)
    })), {})
    roles = list(string)
  }))

  validation {
    condition     = length(var.nodes) > 0
    error_message = "At least one node must be defined."
  }

  validation {
    condition = alltrue([
      for hostname, config in var.nodes :
      can(regex("^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$", config.mac))
    ])
    error_message = "All node MAC addresses must be in format: 00:11:22:33:44:55"
  }

  validation {
    condition = alltrue([
      for hostname, config in var.nodes :
      config.ipmi_ip == null || can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}$", config.ipmi_ip))
    ])
    error_message = "IPMI IP addresses, when provided, must be valid IPv4 addresses."
  }

  validation {
    condition = alltrue([
      for hostname, config in var.nodes :
      can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}$", config.management_ip))
    ])
    error_message = "All nodes must have a valid management_ip in IPv4 format. This field is required to prevent DHCP fallback."
  }

  validation {
    condition     = length(distinct([for h, n in var.nodes : n.mac])) == length(var.nodes)
    error_message = "Duplicate primary MAC addresses detected. Each node must have a unique MAC address."
  }

}

variable "enable_power_action" {
  description = <<-EOT
    SAFETY GATE: Enable IPMI power actions (power on/off/cycle). 
    
    Default: false (prevents accidental power operations during routine applies)
    
    Set to true when:
    - Initial provisioning (power_on)
    - Re-provisioning existing nodes (power_cycle)
    - Controlled shutdowns (power_off)
    
    Power actions are opt-in to prevent unintended node reboots.
  EOT
  type        = bool
  default     = false
}

variable "power_action" {
  description = <<-EOT
    IPMI power action to perform when enable_power_action = true.
    
    Valid values:
    - "power_on": Power on node from off state (initial provisioning)
    - "power_off": Graceful shutdown
    - "power_cycle": Reboot node (re-provisioning)
    - "power_reset": Hard reset (for hung provisioning)
    
    Action is only executed when enable_power_action = true.
  EOT
  type        = string
  default     = "power_on"

  validation {
    condition     = contains(["power_on", "power_off", "power_cycle", "reboot"], var.power_action)
    error_message = "Power action must be one of: power_on, power_off, power_cycle, reboot"
  }
}

variable "power_action_timeout" {
  description = "Timeout for power action completion (Go duration format). Default: 5m."
  type        = string
  default     = "5m"
}
