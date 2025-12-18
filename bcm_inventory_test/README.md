# BCM Ansible Inventory Generator

This Terraform configuration uses the BCM (Base Command Manager) provider to fetch node information and generate Ansible inventory files.

## Prerequisites

1. BCM API access with valid credentials
2. Terraform >= 1.5.0

## Configuration

Set BCM credentials via environment variables:

```bash
export BCM_ENDPOINT="https://bcm.example.com:8081"
export BCM_USERNAME="your-username"
export BCM_PASSWORD="your-password"
```

Or create a `terraform.tfvars` file:

```hcl
bcm_endpoint = "https://bcm.example.com:8081"
bcm_username = "your-username"
bcm_password = "your-password"
```

## Target Nodes

By default, this configuration targets the following nodes:
- cpu-03
- cpu-05
- cpu-06

To customize, set the `target_nodes` variable:

```hcl
target_nodes = ["cpu-01", "cpu-02", "cpu-03"]
```

## Usage

```bash
terraform init
terraform plan
terraform apply
```

## Outputs

After applying, two inventory files are generated:

1. `inventory.yml` - YAML format inventory
2. `inventory.ini` - INI format inventory

## Generated Inventory Structure

The YAML inventory follows this structure:

```yaml
all:
  hosts:
    cpu-03:
      ansible_host: <ip>
      ip: <ip>
      access_ip: <ip>
      bcm_uuid: <uuid>
      bcm_mac: <mac>
      bcm_type: <type>
      bcm_roles: [...]
    # ... more hosts
  children:
    compute_nodes:
      hosts:
        cpu-03: {}
        cpu-05: {}
        cpu-06: {}
  vars:
    ansible_user: ansible
    ansible_ssh_private_key_file: ~/.ssh/id_rsa
    ansible_become: true
    ansible_become_method: sudo
```
