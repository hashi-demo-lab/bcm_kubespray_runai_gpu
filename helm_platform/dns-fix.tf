# DNS Configuration Fix for Run:AI
# Feature: Run:AI Platform Deployment
# 
# NodeLocalDNS needs custom configuration to resolve the Run:AI domain
# (bcm-head-01.eth.cluster) to the correct control plane IP address.
# Without this fix, pods cannot reach the Run:AI backend services.

# =============================================================================
# CoreDNS Hosts Entry for Run:AI Domain
# Adds hosts plugin entry to resolve runai_domain to control_plane_ip
# =============================================================================

resource "null_resource" "coredns_runai_hosts" {
  count = var.enable_runai ? 1 : 0

  triggers = {
    runai_domain     = var.runai_domain
    control_plane_ip = local.control_plane_ip
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -e
      KUBECONFIG="${var.kubeconfig_path}"
      DOMAIN="${var.runai_domain}"
      IP="${local.control_plane_ip}"
      
      echo "Adding DNS hosts entry for $DOMAIN -> $IP"
      
      # Check if nodelocaldns exists (Kubespray default)
      if kubectl --kubeconfig "$KUBECONFIG" get configmap nodelocaldns -n kube-system &>/dev/null; then
        echo "Patching nodelocaldns configmap..."
        
        # Get current Corefile
        CURRENT_COREFILE=$(kubectl --kubeconfig "$KUBECONFIG" get configmap nodelocaldns -n kube-system -o jsonpath='{.data.Corefile}')
        
        # Check if domain zone already exists
        if echo "$CURRENT_COREFILE" | grep -q "$DOMAIN"; then
          echo "DNS zone for $DOMAIN already exists, skipping"
        else
          # Create new zone and prepend to Corefile
          NEW_ZONE="$DOMAIN:53 {
    errors
    cache 30
    forward . $IP
}
"
          NEW_COREFILE="$NEW_ZONE$CURRENT_COREFILE"
          
          # Apply patch using kubectl
          kubectl --kubeconfig "$KUBECONFIG" create configmap nodelocaldns-patch \
            --from-literal="Corefile=$NEW_COREFILE" \
            -n kube-system --dry-run=client -o yaml | \
          kubectl --kubeconfig "$KUBECONFIG" patch configmap nodelocaldns -n kube-system --patch-file=/dev/stdin
          
          # Restart nodelocaldns pods to pick up changes
          kubectl --kubeconfig "$KUBECONFIG" rollout restart daemonset/nodelocaldns -n kube-system 2>/dev/null || true
          echo "nodelocaldns patched successfully"
        fi
      else
        echo "nodelocaldns configmap not found, checking coredns..."
        
        # Fallback to coredns if nodelocaldns doesn't exist
        if kubectl --kubeconfig "$KUBECONFIG" get configmap coredns -n kube-system &>/dev/null; then
          echo "Patching coredns configmap..."
          kubectl --kubeconfig "$KUBECONFIG" patch configmap coredns -n kube-system --type=json \
            -p="[{\"op\": \"add\", \"path\": \"/data/NodeHosts\", \"value\": \"$IP $DOMAIN\"}]" 2>/dev/null || \
          echo "coredns patch may already exist"
        fi
      fi
      
      echo "DNS configuration complete"
    EOT
  }

  lifecycle {
    ignore_changes = all
  }
}

