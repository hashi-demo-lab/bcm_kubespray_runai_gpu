# CLAUDE.md

## Project Summary

This project automates deployment of a production Kubernetes cluster on NVIDIA DGX bare metal infrastructure (via BCM - Base Command Manager) with Run:AI v2.21 self-hosted for GPU workload scheduling. The stack is: Terraform + Ansible/Kubespray + Helm.

## Architecture (3 Stages)

1. **Node Discovery** -- BCM API queries physical nodes (cpu-03/05/06 as control plane, dgx-05/06 as GPU workers)
2. **Kubernetes Deployment** -- Kubespray v2.27.1 deploys K8s v1.31.9 via Ansible with auto-generated SSH keys
3. **Platform Services** -- Helm charts deploy GPU Operator, Prometheus, Knative, LeaderWorkerSet, Run:AI backend + cluster

## Key Files

| Path | Purpose |
|------|---------|
| `main.tf`, `ansible.tf`, `inventory.tf` | Root module: BCM node discovery, Kubespray orchestration |
| `helm_platform/` | Child module: all Helm-based platform components |
| `scripts/` | Shell scripts for node setup, GPU prereqs, containerd relocation |
| `bcm_cmkube_cluster/` | Reference module for BCM native K8s (not used in main flow) |
| `docs/GPU_OPERATOR_PREREQUISITES.md` | GPU node requirements and troubleshooting |

## Providers

- `bcm` v0.1 (hashi-demo-lab/bcm) -- bare metal node discovery
- `ansible` v1.3 -- playbook execution for Kubespray
- `kubernetes`, `helm` -- platform service deployment
- `tls`, `local`, `external` -- supporting utilities

## Conventions

- **Speckit workflow**: spec -> clarify -> plan -> review -> tasks -> analyze -> implement -> deploy -> report
- **Private registry first**: always search HCP Terraform private registry before public
- **Terraform CLI for runs**: never use MCP `create_run` (causes config version errors)
- **Use subagents liberally**: parallel tool calls and Task agents for research and isolation
- Use `AskUserQuestion` tool when clarification is needed (especially during speckit.clarify)

## Network Layout

- **Production network**: 10.184.162.0/24 (node IPs for deployment)
- **Management network**: 10.229.10.0/24 (BCM out-of-band -- do NOT use for deployment)
- **Pod CIDR**: 172.29.0.0/16
- **Service CIDR**: 10.150.0.0/16

## Current Node Assignments

| Hostname | Role | Production IP |
|----------|------|--------------|
| cpu-03 | Control plane + etcd | 10.184.162.102 |
| cpu-05 | Control plane + etcd | 10.184.162.104 |
| cpu-06 | Control plane + etcd | 10.184.162.121 |
| dgx-05 | GPU worker | 10.184.162.109 |
| dgx-06 | GPU worker | 10.184.162.110 |

## Component-Specific Guidance

Check for `AGENTS.md` files in subdirectories for targeted implementation details:
- `AGENTS.md` (root) -- speckit workflow rules, MCP tool priorities, sandbox testing
- `helm_platform/AGENTS.md` -- component versions, dependency order, known issues
- `scripts/AGENTS.md` -- script inventory, execution context, failure modes
- `bcm_cmkube_cluster/AGENTS.md` -- BCM native cluster reference notes

## Updating AGENTS.md Files

When you discover new information during development:
- **Update existing AGENTS.md files** with implementation details, debugging insights, or architectural patterns
- **Create new AGENTS.md files** in relevant directories when working with undocumented areas
- **Add valuable insights** such as common pitfalls, dependency relationships, or workarounds
