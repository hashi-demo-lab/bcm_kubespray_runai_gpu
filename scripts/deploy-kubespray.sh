#!/usr/bin/env bash
# =============================================================================
# Kubespray Deployment Script
# =============================================================================
# This script replicates the Terraform ansible.tf deployment outside of
# Terraform for testing and manual deployment scenarios.
#
# Usage:
#   ./scripts/deploy-kubespray.sh [options]
#
# Options:
#   -c, --config FILE    Configuration file (default: scripts/kubespray.conf)
#   -i, --inventory      Only generate inventory (skip deployment)
#   -v, --validate       Only validate SSH connectivity
#   -d, --dry-run        Show what would be done without executing
#   -h, --help           Show this help message
#
# =============================================================================

set -euo pipefail

# =============================================================================
# Default Configuration
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Kubespray settings
KUBESPRAY_VERSION="${KUBESPRAY_VERSION:-v2.27.1}"
KUBERNETES_VERSION="${KUBERNETES_VERSION:-v1.31.9}"
PYTHON_VERSION="${PYTHON_VERSION:-3.11}"
CNI_PLUGIN="${CNI_PLUGIN:-calico}"
CLUSTER_NAME="${CLUSTER_NAME:-k8s-cluster}"

# SSH settings
SSH_USER="${SSH_USER:-ubuntu}"
SSH_KEY_PATH="${SSH_KEY_PATH:-/tmp/kubespray_ssh_key}"
SSH_PRIVATE_KEY="${SSH_PRIVATE_KEY:-}"

# Node configuration (space-separated hostnames or IPs)
CONTROL_PLANE_NODES="${CONTROL_PLANE_NODES:-}"
WORKER_NODES="${WORKER_NODES:-}"
ETCD_NODES="${ETCD_NODES:-}"  # Defaults to control plane if empty

# Node IP mapping (hostname:ip pairs, space-separated)
# Example: "node1:192.168.1.10 node2:192.168.1.11"
NODE_IP_MAP="${NODE_IP_MAP:-}"

# Working directories
KUBESPRAY_DIR="${KUBESPRAY_DIR:-/tmp/kubespray}"
VENV_DIR="${VENV_DIR:-/tmp/kubespray-venv}"

# Execution flags
DRY_RUN=false
VALIDATE_ONLY=false
INVENTORY_ONLY=false
CONFIG_FILE="${SCRIPT_DIR}/kubespray.conf"

# =============================================================================
# Color Output
# =============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARNING]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# =============================================================================
# Usage
# =============================================================================
usage() {
    cat <<EOF
Kubespray Deployment Script

Usage: $(basename "$0") [options]

Options:
    -c, --config FILE    Configuration file (default: scripts/kubespray.conf)
    -i, --inventory      Only generate inventory (skip deployment)
    -v, --validate       Only validate SSH connectivity
    -d, --dry-run        Show what would be done without executing
    -h, --help           Show this help message

Environment Variables:
    KUBESPRAY_VERSION    Kubespray version (default: v2.27.1)
    KUBERNETES_VERSION   Kubernetes version (default: v1.31.9)
    PYTHON_VERSION       Python minor version (default: 3.11)
    CNI_PLUGIN           CNI plugin (default: calico)
    CLUSTER_NAME         Cluster name (default: k8s-cluster)
    SSH_USER             SSH user (default: ubuntu)
    SSH_KEY_PATH         Path to SSH private key
    SSH_PRIVATE_KEY      SSH private key content (alternative to path)
    CONTROL_PLANE_NODES  Space-separated list of control plane hostnames
    WORKER_NODES         Space-separated list of worker hostnames
    ETCD_NODES           Space-separated list of etcd hostnames (optional)
    NODE_IP_MAP          Space-separated hostname:ip pairs

Example:
    export CONTROL_PLANE_NODES="master1 master2 master3"
    export WORKER_NODES="worker1 worker2"
    export NODE_IP_MAP="master1:10.0.1.10 master2:10.0.1.11 master3:10.0.1.12 worker1:10.0.2.10 worker2:10.0.2.11"
    export SSH_KEY_PATH=~/.ssh/id_rsa
    ./scripts/deploy-kubespray.sh

EOF
    exit 0
}

# =============================================================================
# Parse Arguments
# =============================================================================
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            -i|--inventory)
                INVENTORY_ONLY=true
                shift
                ;;
            -v|--validate)
                VALIDATE_ONLY=true
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                usage
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                ;;
        esac
    done
}

# =============================================================================
# Load Configuration
# =============================================================================
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        log_info "Loading configuration from $CONFIG_FILE"
        # shellcheck disable=SC1090
        source "$CONFIG_FILE"
    else
        log_warn "Configuration file not found: $CONFIG_FILE"
        log_info "Using environment variables or defaults"
    fi
}

# =============================================================================
# Validate Prerequisites
# =============================================================================
validate_prerequisites() {
    log_info "Validating prerequisites..."

    local errors=0

    # Check Python
    local python_cmd="python${PYTHON_VERSION}"
    if ! command -v "$python_cmd" &>/dev/null; then
        log_error "Python ${PYTHON_VERSION} is required but not found"
        log_info "Install with: brew install python@${PYTHON_VERSION} (macOS) or apt install python${PYTHON_VERSION} (Ubuntu)"
        ((errors++))
    else
        log_success "Python ${PYTHON_VERSION} found: $($python_cmd --version)"
    fi

    # Check git
    if ! command -v git &>/dev/null; then
        log_error "Git is required but not found"
        ((errors++))
    else
        log_success "Git found: $(git --version)"
    fi

    # Check SSH key
    if [[ -z "$SSH_PRIVATE_KEY" && ! -f "$SSH_KEY_PATH" ]]; then
        log_error "SSH private key not found at $SSH_KEY_PATH"
        log_info "Set SSH_KEY_PATH or SSH_PRIVATE_KEY environment variable"
        ((errors++))
    else
        log_success "SSH key configured"
    fi

    # Check node configuration
    if [[ -z "$CONTROL_PLANE_NODES" ]]; then
        log_error "No control plane nodes specified"
        log_info "Set CONTROL_PLANE_NODES environment variable"
        ((errors++))
    else
        log_success "Control plane nodes: $CONTROL_PLANE_NODES"
    fi

    if [[ -z "$NODE_IP_MAP" ]]; then
        log_error "No node IP mapping specified"
        log_info "Set NODE_IP_MAP environment variable (e.g., 'node1:192.168.1.10 node2:192.168.1.11')"
        ((errors++))
    else
        log_success "Node IP mapping configured"
    fi

    if [[ $errors -gt 0 ]]; then
        log_error "Prerequisites check failed with $errors error(s)"
        exit 1
    fi

    log_success "All prerequisites validated"
}

# =============================================================================
# Get Node IP
# =============================================================================
get_node_ip() {
    local hostname="$1"
    local ip=""
    
    for mapping in $NODE_IP_MAP; do
        local h="${mapping%%:*}"
        local i="${mapping#*:}"
        if [[ "$h" == "$hostname" ]]; then
            ip="$i"
            break
        fi
    done
    
    echo "$ip"
}

# =============================================================================
# Validate SSH Connectivity
# =============================================================================
validate_ssh_connectivity() {
    log_info "Validating SSH connectivity to nodes..."

    # Prepare SSH key
    local ssh_key_file="$SSH_KEY_PATH"
    if [[ -n "$SSH_PRIVATE_KEY" ]]; then
        ssh_key_file="/tmp/kubespray_ssh_key_temp"
        echo "$SSH_PRIVATE_KEY" > "$ssh_key_file"
        chmod 600 "$ssh_key_file"
    fi

    local all_nodes="$CONTROL_PLANE_NODES $WORKER_NODES"
    local errors=0

    for node in $all_nodes; do
        local ip
        ip=$(get_node_ip "$node")
        
        if [[ -z "$ip" ]]; then
            log_error "No IP mapping found for node: $node"
            ((errors++))
            continue
        fi

        log_info "Testing SSH to $node ($ip)..."
        
        if $DRY_RUN; then
            log_info "[DRY-RUN] Would SSH to $SSH_USER@$ip"
        else
            if ssh -o StrictHostKeyChecking=no \
                   -o UserKnownHostsFile=/dev/null \
                   -o ConnectTimeout=10 \
                   -i "$ssh_key_file" \
                   "$SSH_USER@$ip" \
                   "echo 'Node $node is ready'" 2>/dev/null; then
                log_success "SSH to $node ($ip) successful"
            else
                log_error "SSH to $node ($ip) failed"
                ((errors++))
            fi
        fi
    done

    # Cleanup temp key if used
    if [[ -n "$SSH_PRIVATE_KEY" && -f "/tmp/kubespray_ssh_key_temp" ]]; then
        rm -f "/tmp/kubespray_ssh_key_temp"
    fi

    if [[ $errors -gt 0 ]]; then
        log_error "SSH connectivity check failed for $errors node(s)"
        exit 1
    fi

    log_success "All nodes are SSH accessible"
}

# =============================================================================
# Setup Python Virtual Environment
# =============================================================================
setup_venv() {
    local python_cmd="python${PYTHON_VERSION}"
    log_info "Setting up Python ${PYTHON_VERSION} virtual environment..."

    if $DRY_RUN; then
        log_info "[DRY-RUN] Would create virtualenv at $VENV_DIR"
        return
    fi

    # Remove old virtualenv
    log_info "Removing old virtualenv if exists..."
    rm -rf "$VENV_DIR"

    # Create fresh venv using built-in venv module
    log_info "Creating new virtualenv (this may take a moment)..."
    "$python_cmd" -m venv "$VENV_DIR"

    # Activate and upgrade pip
    log_info "Activating virtualenv..."
    # shellcheck disable=SC1091
    source "$VENV_DIR/bin/activate"
    
    log_info "Upgrading pip..."
    pip install --upgrade pip --quiet --timeout 60

    log_success "Virtual environment created at $VENV_DIR"
}

# =============================================================================
# Clone Kubespray
# =============================================================================
clone_kubespray() {
    log_info "Cloning Kubespray $KUBESPRAY_VERSION..."

    if $DRY_RUN; then
        log_info "[DRY-RUN] Would clone Kubespray $KUBESPRAY_VERSION to $KUBESPRAY_DIR"
        return
    fi

    rm -rf "$KUBESPRAY_DIR"
    git clone --depth 1 --branch "$KUBESPRAY_VERSION" \
        https://github.com/kubernetes-sigs/kubespray.git "$KUBESPRAY_DIR"

    log_success "Kubespray cloned to $KUBESPRAY_DIR"
}

# =============================================================================
# Install Kubespray Requirements
# =============================================================================
install_requirements() {
    log_info "Installing Kubespray requirements..."

    if $DRY_RUN; then
        log_info "[DRY-RUN] Would install requirements from $KUBESPRAY_DIR/requirements.txt"
        return
    fi

    # Ensure virtualenv is activated
    # shellcheck disable=SC1091
    source "$VENV_DIR/bin/activate"

    pip install -r "$KUBESPRAY_DIR/requirements.txt" --quiet

    log_success "Kubespray requirements installed"
    log_info "Ansible version: $("$VENV_DIR/bin/ansible" --version | head -1)"
}

# =============================================================================
# Generate Inventory
# =============================================================================
generate_inventory() {
    log_info "Generating Kubespray inventory..."

    local inventory_dir="$KUBESPRAY_DIR/inventory/mycluster"
    local inventory_file="$inventory_dir/hosts.yml"

    if $DRY_RUN; then
        log_info "[DRY-RUN] Would generate inventory at $inventory_file"
        echo "--- Preview of inventory ---"
        generate_inventory_yaml
        return
    fi

    # Create inventory directory
    mkdir -p "$inventory_dir"
    
    # Copy sample group_vars
    cp -rfp "$KUBESPRAY_DIR/inventory/sample/group_vars" "$inventory_dir/"

    # Generate hosts.yml
    generate_inventory_yaml > "$inventory_file"

    log_success "Inventory generated at $inventory_file"
    log_info "Inventory contents:"
    cat "$inventory_file"
}

# =============================================================================
# Generate Inventory YAML
# =============================================================================
generate_inventory_yaml() {
    # Determine etcd nodes (default to control plane)
    local etcd="${ETCD_NODES:-$CONTROL_PLANE_NODES}"

    cat <<EOF
all:
  hosts:
EOF

    # Generate host entries for control plane nodes
    for node in $CONTROL_PLANE_NODES; do
        local ip
        ip=$(get_node_ip "$node")
        cat <<EOF
    $node:
      ansible_host: $ip
      ip: $ip
      access_ip: $ip
EOF
    done

    # Generate host entries for worker nodes
    for node in $WORKER_NODES; do
        local ip
        ip=$(get_node_ip "$node")
        cat <<EOF
    $node:
      ansible_host: $ip
      ip: $ip
      access_ip: $ip
EOF
    done

    cat <<EOF
  children:
    kube_control_plane:
      hosts:
EOF
    for node in $CONTROL_PLANE_NODES; do
        echo "        $node: {}"
    done

    cat <<EOF
    kube_node:
      hosts:
EOF
    for node in $WORKER_NODES; do
        echo "        $node: {}"
    done

    cat <<EOF
    etcd:
      hosts:
EOF
    for node in $etcd; do
        echo "        $node: {}"
    done

    cat <<EOF
    k8s_cluster:
      children:
        kube_control_plane: {}
        kube_node: {}
    calico_rr:
      hosts: {}
  vars:
    ansible_user: $SSH_USER
    ansible_ssh_private_key_file: $SSH_KEY_PATH
    ansible_become: true
    ansible_become_method: sudo
EOF
}

# =============================================================================
# Write SSH Key
# =============================================================================
write_ssh_key() {
    log_info "Preparing SSH key..."

    if $DRY_RUN; then
        log_info "[DRY-RUN] Would write SSH key to $SSH_KEY_PATH"
        return
    fi

    if [[ -n "$SSH_PRIVATE_KEY" ]]; then
        echo "$SSH_PRIVATE_KEY" > "$SSH_KEY_PATH"
        chmod 600 "$SSH_KEY_PATH"
        log_success "SSH key written to $SSH_KEY_PATH"
    elif [[ -f "$SSH_KEY_PATH" ]]; then
        log_info "Using existing SSH key at $SSH_KEY_PATH"
    else
        log_error "No SSH key available"
        exit 1
    fi
}

# =============================================================================
# Run Kubespray
# =============================================================================
run_kubespray() {
    log_info "Starting Kubespray deployment..."

    if $DRY_RUN; then
        log_info "[DRY-RUN] Would run Kubespray with:"
        log_info "  - Kubernetes version: $KUBERNETES_VERSION"
        log_info "  - CNI plugin: $CNI_PLUGIN"
        log_info "  - Cluster name: $CLUSTER_NAME"
        return
    fi

    # Activate virtualenv
    # shellcheck disable=SC1091
    source "$VENV_DIR/bin/activate"

    # Set Ansible environment
    export ANSIBLE_HOST_KEY_CHECKING=False
    export ANSIBLE_SSH_ARGS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

    cd "$KUBESPRAY_DIR"

    log_info "Running ansible-playbook..."
    
    "$VENV_DIR/bin/ansible-playbook" \
        -i inventory/mycluster/hosts.yml \
        cluster.yml \
        -b -v \
        --private-key="$SSH_KEY_PATH" \
        -e "kube_version=$KUBERNETES_VERSION" \
        -e "kube_network_plugin=$CNI_PLUGIN" \
        -e "cluster_name=$CLUSTER_NAME" \
        -e "ansible_user=$SSH_USER" \
        -e "ansible_ssh_private_key_file=$SSH_KEY_PATH"

    log_success "Kubespray deployment completed!"
}

# =============================================================================
# Cleanup
# =============================================================================
cleanup() {
    log_info "Cleaning up sensitive files..."

    if [[ -n "$SSH_PRIVATE_KEY" && -f "$SSH_KEY_PATH" ]]; then
        rm -f "$SSH_KEY_PATH"
        log_info "Removed temporary SSH key"
    fi
}

# =============================================================================
# Main
# =============================================================================
main() {
    parse_args "$@"
    load_config
    validate_prerequisites

    if $VALIDATE_ONLY; then
        validate_ssh_connectivity
        exit 0
    fi

    validate_ssh_connectivity
    
    if ! $DRY_RUN; then
        setup_venv
        clone_kubespray
        install_requirements
    fi

    generate_inventory

    if $INVENTORY_ONLY; then
        log_success "Inventory generation complete"
        exit 0
    fi

    write_ssh_key
    run_kubespray
    cleanup

    log_success "Deployment complete!"
    log_info ""
    log_info "Next steps:"
    log_info "  1. SSH to a control plane node and verify: kubectl get nodes"
    log_info "  2. Copy kubeconfig from control plane: /etc/kubernetes/admin.conf"
    log_info "  3. Deploy the helm platform for GPU support"
}

# Trap for cleanup on error
trap cleanup EXIT

main "$@"
