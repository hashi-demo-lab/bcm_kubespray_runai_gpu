# Local Computed Values
# Feature: vSphere VM Provisioning with Kubernetes Deployment via Kubespray
# Spec: /workspace/specs/001-vsphere-k8s-kubespray/spec.md
# Data Model: /workspace/specs/001-vsphere-k8s-kubespray/data-model.md
#
# Using private module: tfo-apj-demos/single-virtual-machine/vsphere v1.4.2

locals {
  # SSH authorized keys for cloud-init injection
  # This injects the generated SSH public key into VMs via custom_text userdata
  # Using proper cloud-config format for Ubuntu cloud-init
  ssh_authorized_keys_userdata = <<-EOT
#cloud-config
users:
  - name: ubuntu
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
      - ${tls_private_key.ssh_key.public_key_openssh}
EOT

  # Aggregated list of all VM IP addresses for SSH validation and Ansible inventory (FR-013)
  vm_ip_addresses = [
    module.k8s_control_plane_01.ip_address,
    module.k8s_worker_01.ip_address,
    module.k8s_worker_02.ip_address
  ]

  # Kubespray inventory structure for Ansible deployment (FR-016)
  kubespray_inventory = {
    all = {
      hosts = {
        "k8s-master-01" = {
          ansible_host = module.k8s_control_plane_01.ip_address
          ip           = module.k8s_control_plane_01.ip_address
          access_ip    = module.k8s_control_plane_01.ip_address
        }
        "k8s-worker-01" = {
          ansible_host = module.k8s_worker_01.ip_address
          ip           = module.k8s_worker_01.ip_address
          access_ip    = module.k8s_worker_01.ip_address
        }
        "k8s-worker-02" = {
          ansible_host = module.k8s_worker_02.ip_address
          ip           = module.k8s_worker_02.ip_address
          access_ip    = module.k8s_worker_02.ip_address
        }
      }
      children = {
        kube_control_plane = {
          hosts = {
            "k8s-master-01" = {}
          }
        }
        kube_node = {
          hosts = {
            "k8s-worker-01" = {}
            "k8s-worker-02" = {}
          }
        }
        etcd = {
          hosts = {
            "k8s-master-01" = {}
          }
        }
        k8s_cluster = {
          children = {
            kube_control_plane = {}
            kube_node          = {}
          }
        }
        calico_rr = {
          hosts = {}
        }
      }
      vars = {
        ansible_user                 = var.ssh_user
        ansible_ssh_private_key_file = var.ssh_private_key_path
        ansible_become               = true
        ansible_become_method        = "sudo"
      }
    }
  }
}
