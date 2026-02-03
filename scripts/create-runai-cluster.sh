#!/bin/bash
# Run:AI Phase 2 - Create cluster and retrieve credentials via API
# This script creates a cluster in Run:AI and outputs the credentials
# needed for the runai-cluster Helm chart deployment.
#
# Usage: ./create-runai-cluster.sh [cluster-name]
# Output: JSON with cluster_uid and client_secret for Terraform

set -e

# Configuration
RUNAI_URL="${RUNAI_URL:-https://bcm-head-01.eth.cluster:30443}"
RUNAI_USER="${RUNAI_USER:-}"
RUNAI_PASS="${RUNAI_PASS:-}"
CLUSTER_NAME="${1:-bcm-gpu-cluster}"
KUBECONFIG="${KUBECONFIG:-/home/ibm/bcm_kubespray_runai_gpu/kubeconfig}"

# Colors for output (only if terminal)
if [ -t 1 ]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  NC='\033[0m'
else
  RED=''
  GREEN=''
  YELLOW=''
  NC=''
fi

log() { echo -e "${GREEN}[INFO]${NC} $1" >&2; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1" >&2; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; exit 1; }

# Check required environment variables
if [ -z "$RUNAI_USER" ]; then
  error "RUNAI_USER environment variable is required"
fi

if [ -z "$RUNAI_PASS" ]; then
  error "RUNAI_PASS environment variable is required"
fi

# Check if jq is available
if ! command -v jq &> /dev/null; then
  error "jq is required but not installed"
fi

# Step 1: Authenticate with Keycloak
log "Authenticating with Run:AI control plane..."
AUTH_RESPONSE=$(curl -sk "${RUNAI_URL}/auth/realms/runai/protocol/openid-connect/token" \
  -d "grant_type=password" \
  -d "client_id=runai-cli" \
  -d "username=${RUNAI_USER}" \
  -d "password=${RUNAI_PASS}" 2>/dev/null)

TOKEN=$(echo "$AUTH_RESPONSE" | jq -r '.access_token // empty')

if [ -z "$TOKEN" ]; then
  error "Failed to authenticate. Response: $AUTH_RESPONSE"
fi

log "Authentication successful"

# Step 2: Check if cluster already exists
log "Checking for existing clusters..."
CLUSTERS_RESPONSE=$(curl -sk "${RUNAI_URL}/v1/k8s/clusters" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" 2>/dev/null)

EXISTING_CLUSTER=$(echo "$CLUSTERS_RESPONSE" | jq -r ".[] | select(.name == \"${CLUSTER_NAME}\") | .uuid // empty")

if [ -n "$EXISTING_CLUSTER" ]; then
  log "Cluster '${CLUSTER_NAME}' already exists with UID: ${EXISTING_CLUSTER}"
  CLUSTER_UID="$EXISTING_CLUSTER"
else
  # Step 3: Create the cluster
  log "Creating cluster '${CLUSTER_NAME}'..."
  CREATE_RESPONSE=$(curl -sk -X POST "${RUNAI_URL}/v1/k8s/clusters" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{
      \"name\": \"${CLUSTER_NAME}\"
    }" 2>/dev/null)

  CLUSTER_UID=$(echo "$CREATE_RESPONSE" | jq -r '.uuid // empty')

  if [ -z "$CLUSTER_UID" ]; then
    error "Failed to create cluster. Response: $CREATE_RESPONSE"
  fi

  log "Cluster created with UID: ${CLUSTER_UID}"
fi

# Step 4: Get cluster install values (contains client_secret)
log "Retrieving cluster credentials..."
INSTALL_VALUES=$(curl -sk "${RUNAI_URL}/v1/k8s/clusters/${CLUSTER_UID}/installfile?cloud=op" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" 2>/dev/null)

# Try to extract client secret from install values
# The format varies by Run:AI version, try multiple paths
CLIENT_SECRET=$(echo "$INSTALL_VALUES" | jq -r '.controlPlane.clientSecret // .spec.controlPlane.clientSecret // empty' 2>/dev/null)

# If not found in install values, try the cluster details endpoint
if [ -z "$CLIENT_SECRET" ]; then
  log "Trying alternative endpoint for credentials..."
  CLUSTER_DETAILS=$(curl -sk "${RUNAI_URL}/v1/k8s/clusters/${CLUSTER_UID}" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" 2>/dev/null)
  
  CLIENT_SECRET=$(echo "$CLUSTER_DETAILS" | jq -r '.clientSecret // .spec.clientSecret // empty' 2>/dev/null)
fi

# Try yet another endpoint - get token
if [ -z "$CLIENT_SECRET" ]; then
  log "Trying token endpoint..."
  TOKEN_RESPONSE=$(curl -sk "${RUNAI_URL}/v1/k8s/clusters/${CLUSTER_UID}/token" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" 2>/dev/null)
  
  CLIENT_SECRET=$(echo "$TOKEN_RESPONSE" | jq -r '.token // .clientSecret // empty' 2>/dev/null)
fi

if [ -z "$CLIENT_SECRET" ]; then
  warn "Could not retrieve client_secret automatically"
  warn "Install values response: $INSTALL_VALUES"
  # Output partial result
  echo "{\"cluster_uid\": \"${CLUSTER_UID}\", \"client_secret\": \"\", \"status\": \"partial\", \"message\": \"Cluster created but client_secret needs manual retrieval\"}"
  exit 0
fi

log "Credentials retrieved successfully"

# Output JSON for Terraform external data source
echo "{\"cluster_uid\": \"${CLUSTER_UID}\", \"client_secret\": \"${CLIENT_SECRET}\", \"status\": \"success\"}"
