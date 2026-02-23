# BCM Node Provisioning Module

Terraform child module for managing bare metal node provisioning via BCM (Base Command Manager) API. Nodes are imported from BCM and managed declaratively. Reprovisioning is triggered by changing the software image (requires provider changes — see `specs/001-bcm-node-provisioning/provider-gap-analysis.md`).

## Prerequisites

The following must be pre-configured on the BCM headnode before using this module:

| #   | Prerequisite                      | Verification Command                                                            |
| --- | --------------------------------- | ------------------------------------------------------------------------------- |
| 1   | BCM 10 installed on headnode      | `cmsh -c "main; status"`                                                        |
| 2   | Management network defined        | `cmsh -c "network; list"`                                                       |
| 3   | Software image prepared           | `cmsh -c "softwareimage; list"`                                                 |
| 4   | DHCP/TFTP/PXE active on headnode  | `systemctl status dhcpd tftpd`                                                  |
| 5   | Provisioning role on headnode     | `cmsh -c "device use headnode; roles; show provisioning"`                       |
| 6   | Provisioning slots ≥ node count   | `cmsh -c "device use headnode; roles; use provisioning; get provisioningslots"` |
| 7   | Target image in provisioning role | `cmsh -c "device use headnode; roles; use provisioning; get localimages"`       |
| 8   | `DeviceResolveAnyMAC=1`           | `grep DeviceResolveAnyMAC /cm/local/apps/cmd/etc/cmd.conf`                      |

## Usage

```hcl
module "node_provisioning" {
  source = "./bcm_node_provisioning"

  nodes = {
    "cpu-03" = {
      mac           = "B8:CE:F6:D2:C9:5A"
      category      = "default"
      management_ip = "10.184.162.102"
      roles         = []
    }
    "dgx-05" = {
      mac           = "10:70:FD:BD:73:4D"
      category      = "default"
      management_ip = "10.184.162.109"
      roles         = ["compute"]
    }
  }

  management_network_name = "dgxnet"
  software_image_name     = "ubuntu2204-4"
}
```

## Variables

| Name                      | Type          | Required | Default | Description                   |
| ------------------------- | ------------- | -------- | ------- | ----------------------------- |
| `nodes`                   | `map(object)` | Yes      | —       | Map of hostname → node config |
| `software_image_name`     | `string`      | Yes      | —       | BCM software image name       |
| `management_network_name` | `string`      | Yes      | —       | Management network name       |

## Outputs

| Name                    | Description                         |
| ----------------------- | ----------------------------------- |
| `device_ids`            | Map of hostname → BCM device UUID   |
| `device_details`        | Map of hostname → device details    |
| `software_image_uuid`   | UUID of provisioning image          |
| `management_network_id` | ID of management network            |
| `node_count`            | Total managed nodes                 |
| `node_status`           | Per-node provisioning status        |
| `provisioning_summary`  | Summary counts: total/success/failed |

## Architecture

- **All API calls go to the BCM head node only.** Terraform never contacts individual nodes or BMC/IPMI interfaces directly.
- **Nodes are auto-imported** from BCM on first apply — no duplicate device errors.
- **Static IPs on BOOTIF** are required for all management interfaces (`dhcp = false`).
- **Reprovisioning** (software image changes, power actions) is pending provider changes. See `specs/001-bcm-node-provisioning/provider-gap-analysis.md`.

## Troubleshooting

| Issue                      | Solution                                                                    |
| -------------------------- | --------------------------------------------------------------------------- |
| `Software image not found` | Verify image name: `cmsh -c "softwareimage; list"`                          |
| `Network not found`        | Verify network name: `cmsh -c "network; list"`                              |
| `Category not found`       | Verify category name: `cmsh -c "category; list"`                            |
| `Node stuck in INSTALLING` | Check provisioning status: `cmsh -c "softwareimage; provisioningstatus"`    |
| `PXE boot fails`           | Verify `DeviceResolveAnyMAC=1` and DHCP/TFTP services on headnode           |
