#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

CLUSTER_NAME="${1:-}"
if [ -z "$CLUSTER_NAME" ]; then
  echo "Usage: $0 <cluster-name>"
  echo "Example: $0 homelab-1"
  echo ""
  echo "Available clusters:"
  ls "$REPO_ROOT/clusters/"
  exit 1
fi

CLUSTER_VARS="$REPO_ROOT/clusters/$CLUSTER_NAME/cluster-vars.env"
if [ ! -f "$CLUSTER_VARS" ]; then
  echo "Error: cluster vars not found at $CLUSTER_VARS"
  exit 1
fi

CREDENTIALS_FILE="$SCRIPT_DIR/aws-credentials"
if [ ! -f "$CREDENTIALS_FILE" ]; then
  echo "Error: aws-credentials file not found at $CREDENTIALS_FILE"
  echo "Copy bootstrap/aws-credentials.example to bootstrap/aws-credentials and fill in secrets"
  exit 1
fi

source "$CLUSTER_VARS"
source "$CREDENTIALS_FILE"

CURRENT_CONTEXT=$(kubectl config current-context 2>/dev/null || echo "")
if [ "$CURRENT_CONTEXT" != "$KUBE_CONTEXT" ]; then
  echo "Error: current kubectl context '$CURRENT_CONTEXT' does not match expected '$KUBE_CONTEXT'"
  echo "Switch contexts with: kubectl config use-context $KUBE_CONTEXT"
  exit 1
fi

echo "Bootstrapping cluster: $CLUSTER_NAME"
echo "  MetalLB pool: $METALLB_ADDRESS_POOL"
echo "  Cert email:   $CERT_EMAIL"
echo ""

echo "Ensuring namespaces exist..."
kubectl create namespace flux-system --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace secrets --dry-run=client -o yaml | kubectl apply -f -

echo "Creating AWS credentials secret..."
kubectl create secret generic aws-credentials \
  --from-literal=access-key-id="$AWS_ACCESS_KEY_ID" \
  --from-literal=secret-access-key="$AWS_SECRET_ACCESS_KEY" \
  --from-literal=region="$AWS_REGION" \
  --namespace=secrets \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Creating cluster-config configmap..."
kubectl create configmap cluster-config \
  --from-literal=zone_id="$R53_ZONE" \
  --from-literal=external_dns_txt_id="$CLUSTER_NAME" \
  --from-literal=metal_lb_address_pool="$METALLB_ADDRESS_POOL" \
  --from-literal=cert_email="$CERT_EMAIL" \
  --namespace=flux-system \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Applying Flux GitRepository..."
kubectl apply -f "$SCRIPT_DIR/git-repo.yaml"

echo "Applying Flux Kustomizations for $CLUSTER_NAME..."
kubectl apply -f "$REPO_ROOT/clusters/$CLUSTER_NAME/flux-kustomizations.yaml"

echo ""
echo "Bootstrap complete for $CLUSTER_NAME!"
echo "Flux will now sync the cluster. Monitor with:"
echo "  flux get kustomizations --watch"
