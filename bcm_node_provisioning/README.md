# BCM Node Provisioning Module

Terraform child module for automating bare metal node provisioning and re-provisioning via BCM (Base Command Manager) API using IPMI/PXE boot.

## Prerequisites

The following must be pre-configured on the BCM headnode before using this module:

| # | Prerequisite | Verification Command |
|---|---|---|
| 1 | BCM 10 installed on headnode | `cmsh -c "main; status"` |
| 2 | Management network defined | `cmsh -c "network; list"` |
| 3 | Software image prepared | `cmsh -c "softwareimage; list"` |
| 4 | DHCP/TFTP/PXE active on headnode | `systemctl status dhcpd tftpd` |
| 5 | Provisioning role on headnode | `cmsh -c "device use headnode; roles; show provisioning"` |
| 6 | Provisioning slots ≥ node count | `cmsh -c "device use headnode; roles; use provisioning; get provisioningslots"` |
| 7 | Target image in provisioning role | `cmsh -c "device use headnode; roles; use provisioning; get localimages"` |
| 8 | `DeviceResolveAnyMAC=1` | `grep DeviceResolveAnyMAC /cm/local/apps/cmd/etc/cmd.conf` |
| 9 | BMC/IPMI network connectivity | `ipmitool -H <bmc_ip> -U <user> -P <pass> power status` |

## Usage

### New Node Provisioning

```hcl
module "node_provisioning" {
  source = "./bcm_node_provisioning"

  nodes = {
    "dgx-05" = {
      mac           = "94:6D:AE:AA:13:C9"
      bmc_mac       = "94:6D:AE:AA:13:CA"
      ipmi_ip       = "10.229.10.109"
      category      = "dgx-h100"
      management_ip = "10.184.162.109"
      roles         = ["compute"]
    }
    "dgx-06" = {
      mac           = "A0:88:C2:A3:44:E5"
      bmc_mac       = "A0:88:C2:A3:44:E6"
      ipmi_ip       = "10.229.10.110"
      category      = "dgx-h100"
      management_ip = "10.184.162.110"
      roles         = ["compute"]
    }
  }

  management_network_name = "managementnet"
  oob_network_name        = "oobmanagementnet"
  software_image_name     = "dgx-os-6.3-h100-image"
  bmc_username            = var.bmc_username
  bmc_password            = var.bmc_password

  # Safety gate: set true to trigger IPMI power actions
  enable_power_action = true
  power_action        = "power_on"
}
```

### Re-provisioning Existing Nodes

```hcl
module "node_reprovisioning" {
  source = "./bcm_node_provisioning"

  # Same node definitions...
  nodes = { ... }

  management_network_name = "managementnet"
  oob_network_name        = "oobmanagementnet"
  software_image_name     = "dgx-os-6.4-h100-image"  # Updated image
  bmc_username            = var.bmc_username
  bmc_password            = var.bmc_password

  enable_power_action = true
  power_action        = "power_cycle"  # Reboot to PXE
}
```

## Variables

| Name | Type | Required | Default | Description |
|---|---|---|---|---|
| `nodes` | `map(object)` | Yes | — | Map of hostname → node config |
| `software_image_name` | `string` | Yes | — | BCM software image name |
| `management_network_name` | `string` | Yes | — | Management network name |
| `oob_network_name` | `string` | No | `"oob-mgmt"` | OOB/IPMI network name |
| `bmc_username` | `string` | Yes | — | BMC username (sensitive) |
| `bmc_password` | `string` | Yes | — | BMC password (sensitive) |
| `enable_power_action` | `bool` | No | `false` | Safety gate for power ops |
| `power_action` | `string` | No | `"power_on"` | IPMI action type |
| `power_action_timeout` | `string` | No | `"5m"` | Power action timeout |

## Outputs

| Name | Description |
|---|---|
| `device_ids` | Map of hostname → BCM device UUID |
| `device_details` | Map of hostname → device details |
| `software_image_uuid` | UUID of provisioning image |
| `management_network_id` | ID of management network |
| `power_action_enabled` | Whether power actions were executed |
| `node_count` | Total managed nodes |

## Provisioning Flow

```
1. terraform plan   → Validates: image exists, networks exist, categories exist
2. terraform apply  → Creates device identities in BCM (hostname, MAC, interfaces)
3. (if enabled)     → IPMI power action triggers PXE boot
4. BCM auto-provisions → Headnode serves OS image to node via PXE/TFTP
5. Node reports UP  → Monitor via: cmsh -c "softwareimage; provisioningstatus"
```

## Security

- BMC credentials are marked `sensitive` — never appear in plan output
- Power actions require explicit opt-in (`enable_power_action = true`)
- IPMI traffic is isolated to OOB management network
- No credentials are hardcoded in module code

## Troubleshooting

| Issue | Solution |
|---|---|
| `Software image not found` | Verify image name: `cmsh -c "softwareimage; list"` |
| `Network not found` | Verify network name: `cmsh -c "network; list"` |
| `Category not found` | Verify category name: `cmsh -c "category; list"` |
| `Power action failed` | Check BMC connectivity: `ipmitool -H <ip> -U <user> -P <pass> power status` |
| `Node stuck in INSTALLING` | Check provisioning status: `cmsh -c "softwareimage; provisioningstatus"` |
| `PXE boot fails` | Verify `DeviceResolveAnyMAC=1` and DHCP/TFTP services on headnode |
