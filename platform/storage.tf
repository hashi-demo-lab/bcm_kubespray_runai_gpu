# Storage Configuration
# Feature: Run:AI Platform Deployment
# Spec: /workspace/specs/002-runai-deployment/plan.md
# Dependency: None (first to deploy)

# =============================================================================
# Local Path Provisioner - Default StorageClass
# Requirement: Run:AI requires a default StorageClass for persistent volumes
# =============================================================================

resource "helm_release" "local_path_provisioner" {
  count = var.enable_local_storage ? 1 : 0

  name             = "local-path-provisioner"
  repository       = "https://charts.containeroo.ch"
  chart            = "local-path-provisioner"
  version          = var.local_storage_version
  namespace        = "local-path-storage"
  create_namespace = true

  # Mark as default storage class
  set {
    name  = "storageClass.defaultClass"
    value = "true"
  }

  set {
    name  = "storageClass.name"
    value = "local-path"
  }

  # Configure storage path on nodes
  set {
    name  = "nodePathMap[0].node"
    value = "DEFAULT_PATH_FOR_NON_LISTED_NODES"
  }

  set {
    name  = "nodePathMap[0].paths[0]"
    value = "/opt/local-path-provisioner"
  }

  # Reclaim policy
  set {
    name  = "storageClass.reclaimPolicy"
    value = "Delete"
  }
}
