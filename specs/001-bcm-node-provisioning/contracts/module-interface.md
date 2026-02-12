# Module Interface Contract

**Feature**: BCM Node Provisioning Module  
**Branch**: `001-bcm-node-provisioning`  
**Module Path**: `bcm_node_provisioning/`

---

## Module Invocation

```hcl
module "bcm_node_provisioning" {
  source = "./bcm_node_provisioning"
  
  # Required: Node configurations
  nodes = {
    "dgx-05" = {
      mac       = "00:1A:2B:3C:4D:5E"
      bmc_mac   = "00:1A:2B:3C:4D:5F"
      ipmi_ip   = "10.229.10.50"
      category  = "gpu-worker"
      roles     = ["compute", "gpu"]
    }
  }
  
  software_image_name = "ubuntu-22.04-nvidia-535"
  management_network  = "dgxnet"
  bmc_username        = var.bmc_username
  bmc_password        = var.bmc_password
}
```

See full specification in file for complete details.
