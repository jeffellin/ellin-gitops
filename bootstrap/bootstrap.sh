#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CREDENTIALS_FILE="$SCRIPT_DIR/aws-credentials"

if [ ! -f "$CREDENTIALS_FILE" ]; then
  echo "Error: aws-credentials file not found!"
  echo "Please create $CREDENTIALS_FILE with your AWS credentials"
  echo "You can use aws-credentials.example as a template"
  exit 1
fi

# Source the credentials file
source "$CREDENTIALS_FILE"

# Create namespaces if they don't exist
echo "Ensuring namespaces exist..."
kubectl create namespace flux-system --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace secrets --dry-run=client -o yaml | kubectl apply -f -

echo "Creating AWS credentials secret for cert-manager..."
kubectl create secret generic aws-credentials \
  --from-literal=access-key-id="$AWS_ACCESS_KEY_ID" \
  --from-literal=secret-access-key="$AWS_SECRET_ACCESS_KEY" \
  --from-literal=region="$AWS_REGION" \
  --namespace=secrets \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Creating cluster-config configmap..."
kubectl create configmap cluster-config \
  --from-literal=zone-id="$R53_ZONE" \
  --from-literal=external-dns-txt-id="$CLUSTER_NAME" \
  --from-literal=metal-lb-address-pool="$METALLB_ADDRESS_POOL" \
  --from-literal=cert-email="$CERT_EMAIL" \
  --namespace=flux-system \
  --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "AWS credentials secrets and configmap created successfully!"
