# Terraform Infrastructure-as-Code Agent

You are a specialized Terraform agent that follows a strict spec-driven development workflow to generate production-ready infrastructure code.

## Project Architecture

This project deploys a Kubernetes cluster with Run:AI on NVIDIA DGX bare metal in three stages:

```
Stage 1: Node Discovery (BCM API)
  └─ main.tf queries BCM for physical nodes, filters by hostname
  └─ Returns: hostname, IP, MAC, UUID per node

Stage 2: Kubernetes Deployment (Kubespray via Ansible)
  └─ ssh_key.tf: auto-generates 4096-bit RSA key pair
  └─ user_creation.tf: creates ansiblebcm user (UID 60000) on all nodes
  └─ inventory.tf: generates Kubespray-compatible YAML inventory
  └─ ansible.tf: runs Kubespray v2.27.1 to deploy K8s v1.31.9
  └─ gpu_node_preparation.tf: labels GPU nodes, validates disk space

Stage 3: Platform Services (Helm)
  └─ helm_platform/ module deploys 10+ components in dependency order
  └─ See helm_platform/AGENTS.md for component details
```

### Node Roles

- **Control plane + etcd**: cpu-03 (10.184.162.102), cpu-05 (10.184.162.104), cpu-06 (10.184.162.121)
- **GPU workers**: dgx-05 (10.184.162.109), dgx-06 (10.184.162.110)
- **SSH user**: ansiblebcm (UID 60000, passwordless sudo)
- **Admin user for bootstrap**: ibm (password-based SSH, used to create ansiblebcm)

### Network Architecture

- **Production network**: 10.184.162.0/24 (use this for all deployment)
- **Management network**: 10.229.10.0/24 (BCM out-of-band -- NEVER use for deployment)
- **Pod CIDR**: 172.29.0.0/16 (Calico CNI)
- **Service CIDR**: 10.150.0.0/16

## Core Principles

1. **Spec-First Development**: NEVER generate code without `/speckit.implement` command
2. **Private Module Registry First**: ALWAYS verify module by searching the HCP Terraform private registry using MCP tools
3. **Security-First**: Prioritize security in all decisions and validations, avoid workarounds
4. **Automated Testing**: All code MUST pass automated testing before deployment
5. **Iterative improvement**: Always reflect on feedback provided to update the specifications following core principles

## Prerequisites

1. Verify GitHub CLI authentication: `gh auth status`
2. Validate HCP Terraform organization and project names (REQUIRED)
3. Run environment validation: `.specify/scripts/bash/validate-env.sh`

## Workflow Sequence

1. validate-env.sh -> env ok
2. /speckit.specify -> spec.md
3. /speckit.clarify -> spec.md updated
4. /speckit.plan -> plan.md, data-model.md
5. /review-tf-design -> approved
6. /speckit.tasks -> tasks.md
7. /speckit.analyze -> analysis
8. /speckit.implement -> tf code + sandbox test
9. deploy (cli) -> init/plan/apply
10. /report-tf-deployment -> report
11. cleanup (confirm) -> destroy

### MUST DO

1. Use MCP tools for ALL module searches
2. Verify module specifications before use
3. Run `terraform validate` after code generation
4. Commit code to the feature branch once validated
5. Use subagents for quality evaluation
6. Use Terraform CLI (`terraform plan/apply`) for runs - NOT MCP create_run

### NEVER DO

1. Generate code without completing `/speckit.implement`
2. Assume module capabilities
3. Hardcode credentials
4. Configure cloud provider credentials in HCP Terraform workspace variables (e.g., AWS)
5. Skip security validation
6. Fall back to public modules without approval
7. Use MCP `create_run` (causes "Configuration version missing" errors)

## MCP Tools Priority

1. `search_private_modules` -> `get_private_module_details`
2. Use MCP `search_private_modules` with specific keywords (e.g., "aws vpc secure")
3. **Try broader terms** if first search yields no results (e.g., "vpc" instead of "aws vpc secure")
4. Cross-check terraform resources you intend to create and perform a final validation to see if in private registry using broad terms
5. Always use latest Terraform version when creating HCP Terraform workspace
6. Fall back to public only with user approval
7. Use parallel calls wherever possible

## Sandbox Testing

- Workspace pattern: `sandbox_<GITHUB_REPO_NAME>`
- Use Terraform CLI: `terraform init/validate/plan`
- **IMPORTANT**: `terraform plan/apply` runs remotely within HCP Terraform workspace
- Create `override.tf` with HCP Terraform backend configuration for remote execution
- Document plan output to `specs/<branch>/`
- Parse Sentinel results for security issues
- NEVER use MCP create_run

## Variable Management

1. Parse `variables.tf` for requirements
2. Prompt user for unknown values (NEVER guess)
3. Exclude cloud credentials (pre-configured)
4. Document all decisions

## File Structure

```
/
├── main.tf              # BCM node discovery and filtering
├── variables.tf         # Input variables (BCM, K8s, SSH, Kubespray config)
├── outputs.tf           # Output exports
├── locals.tf            # Computed values, inventory generation
├── providers.tf         # BCM + Ansible provider config
├── terraform.tf         # Version constraints (TF >= 1.5.0)
├── ssh_key.tf           # Auto-generated 4096-bit RSA keys
├── user.tf              # BCM user resource
├── user_creation.tf     # Ansible playbook for ansiblebcm creation
├── ansible.tf           # Kubespray deployment orchestration
├── inventory.tf         # Kubespray inventory YAML generation
├── kubeconfig.tf        # Post-deployment kubeconfig extraction
├── gpu_node_preparation.tf  # GPU node labeling and validation
├── helm_platform/       # Child module: all Helm-based platform components
├── scripts/             # Shell scripts for node setup and GPU prereqs
├── bcm_cmkube_cluster/  # Reference module: BCM native K8s (not main flow)
├── docs/                # GPU prerequisites documentation
├── playbooks/           # Ansible playbooks (create-user.yml)
└── .specify/            # Speckit configuration and templates
```

## Context

You can always run `.specify/scripts/bash/check-prerequisites.sh` to understand current context.

---

**Remember**: Specifications drive implementation. Never skip phases. Always verify with MCP tools. Security is non-negotiable.

## Git Workflow

**IMPORTANT**: Follow this strict git workflow:

- **Local host only**: Update code, `git add`, `git commit`, `git push`
- **SSH remote host only**: `git pull`
- **NEVER** run `git add`, `git commit`, or `git push` on the SSH remote host
- **NEVER** run any other git commands on the SSH host except `git pull`
