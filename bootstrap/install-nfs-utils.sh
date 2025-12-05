#!/bin/bash
set -e

echo "Installing NFS client utilities on all nodes..."

# Create a DaemonSet that installs nfs-common on each node
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: install-nfs-utils
  namespace: kube-system
spec:
  selector:
    matchLabels:
      name: install-nfs-utils
  template:
    metadata:
      labels:
        name: install-nfs-utils
    spec:
      hostPID: true
      hostNetwork: true
      initContainers:
      - name: install-nfs-utils
        image: ubuntu:22.04
        command:
        - /bin/bash
        - -c
        - |
          set -e
          echo "Installing NFS client utilities..."
          # Try to detect the host's package manager
          if nsenter --target 1 --mount --uts --ipc --net --pid -- which apt-get > /dev/null 2>&1; then
            echo "Detected apt-get, installing nfs-common..."
            nsenter --target 1 --mount --uts --ipc --net --pid -- apt-get update
            nsenter --target 1 --mount --uts --ipc --net --pid -- apt-get install -y nfs-common
          elif nsenter --target 1 --mount --uts --ipc --net --pid -- which yum > /dev/null 2>&1; then
            echo "Detected yum, installing nfs-utils..."
            nsenter --target 1 --mount --uts --ipc --net --pid -- yum install -y nfs-utils
          elif nsenter --target 1 --mount --uts --ipc --net --pid -- which dnf > /dev/null 2>&1; then
            echo "Detected dnf, installing nfs-utils..."
            nsenter --target 1 --mount --uts --ipc --net --pid -- dnf install -y nfs-utils
          else
            echo "ERROR: Could not detect package manager!"
            exit 1
          fi
          echo "NFS utilities installed successfully on \$(hostname)"
          # Keep the container running briefly to show success
          sleep 5
        securityContext:
          privileged: true
      containers:
      - name: pause
        image: gcr.io/google_containers/pause:3.2
EOF

echo ""
echo "DaemonSet created. Monitoring installation progress..."
echo "Waiting for all pods to complete initialization..."

# Wait for all pods to be ready
kubectl rollout status daemonset/install-nfs-utils -n kube-system --timeout=5m

echo ""
echo "Installation complete! Checking logs from one pod..."
POD=$(kubectl get pods -n kube-system -l name=install-nfs-utils -o jsonpath='{.items[0].metadata.name}')
kubectl logs -n kube-system "$POD" -c install-nfs-utils

echo ""
echo "NFS utilities have been installed on all nodes."
echo "You can now delete the DaemonSet with:"
echo "  kubectl delete daemonset install-nfs-utils -n kube-system"
