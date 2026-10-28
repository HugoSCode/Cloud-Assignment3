#!/usr/bin/env bash
#
# Deploy the application and its monitoring, on the VM, in the right order.
# Run this AFTER both Terraform stages have been applied.
#
#   ./scripts/deploy.sh <label>.<region>.cloudapp.azure.com [image-tag]
#
# Idempotent: safe to re-run.
set -euo pipefail

cd "$(dirname "$0")/.."

HOST="${1:-}"
TAG="${2:-v1}"
NS=shop

if [ -z "$HOST" ]; then
  echo "usage: $0 <host> [image-tag]" >&2
  echo "   eg: $0 myshop.australiaeast.cloudapp.azure.com v1" >&2
  echo >&2
  echo "Get your host with:" >&2
  echo "  terraform -chdir=terraform/infra-<cloud> output -raw shop_host" >&2
  exit 1
fi

step () { echo; echo "=== $* ==="; }

# ---------------------------------------------------------------------------
step "Preflight"
# ---------------------------------------------------------------------------
command -v kubectl >/dev/null || { echo "kubectl not found" >&2; exit 1; }
command -v docker  >/dev/null || { echo "docker not found" >&2; exit 1; }

kubectl get nodes >/dev/null || { echo "cannot reach the cluster" >&2; exit 1; }

if ! kubectl get ns monitoring >/dev/null 2>&1; then
  echo "ERROR: the monitoring namespace does not exist." >&2
  echo "Apply terraform/platform first -- see RUNBOOK.md step 6." >&2
  exit 1
fi

if ! kubectl get crd servicemonitors.monitoring.coreos.com >/dev/null 2>&1; then
  echo "ERROR: the ServiceMonitor CRD is missing." >&2
  echo "kube-prometheus-stack has not finished installing." >&2
  exit 1
fi

echo "  cluster reachable, platform present"

# ---------------------------------------------------------------------------
step "Render the hostname into the Ingress and Certificate"
# ---------------------------------------------------------------------------
if grep -q '__SHOP_HOST__' manifests/07-ingress.yaml; then
  ./scripts/render.sh "$HOST"
else
  CURRENT=$(grep -m1 -oE '[a-z0-9.-]+\.(cloudapp\.azure\.com|sslip\.io)' manifests/07-ingress.yaml || true)
  if [ "$CURRENT" != "$HOST" ]; then
    echo "  manifest is rendered for '$CURRENT' but you asked for '$HOST'"
    sed -i "s/${CURRENT}/${HOST}/g" manifests/07-ingress.yaml
    echo "  re-pointed to $HOST"
  else
    echo "  already rendered for $HOST"
  fi
fi

# ---------------------------------------------------------------------------
step "Build and push the three images"
# ---------------------------------------------------------------------------
./scripts/build-images.sh "$TAG"

# The manifests pin :v1. If a different tag was asked for, point them at it.
if [ "$TAG" != "v1" ]; then
  echo "  updating manifests to :$TAG"
  sed -i "s|\(localhost:32000/[a-z-]*\):v[0-9]*|\1:${TAG}|g" manifests/*.yaml
fi

# ---------------------------------------------------------------------------
step "Apply the application manifests"
# ---------------------------------------------------------------------------
# Numbered, so the namespace and config exist before anything references them.
kubectl apply -f manifests/

# ---------------------------------------------------------------------------
step "Wait for the PKI chain"
# ---------------------------------------------------------------------------
# A leaf certificate cannot be issued until the CA that signs it exists, so
# wait on every Certificate in the cluster rather than on one by name. If your
# chain is right, they all become Ready; if it is not, this is where you find
# out, and `describe` on the one that is stuck tells you why.
echo "  waiting for every Certificate to become Ready..."
kubectl wait --for=condition=Ready certificate --all --all-namespaces --timeout=180s || {
  echo >&2
  echo "  Not every certificate is Ready. Look at the one that is stuck:" >&2
  kubectl get certificate --all-namespaces >&2 || true
  echo >&2
  echo "    kubectl -n <ns> describe certificate <name>" >&2
  echo "    kubectl -n cert-manager logs -l app.kubernetes.io/name=cert-manager --tail=50" >&2
  echo >&2
  echo "  See docs/TROUBLESHOOTING.md. A CA ClusterIssuer does not look for" >&2
  echo "  its signing key in your application namespace." >&2
}

# ---------------------------------------------------------------------------
step "Wait for the workloads"
# ---------------------------------------------------------------------------
for d in redis catalog orders frontend; do
  kubectl -n $NS rollout status deployment/$d --timeout=180s
done

# ---------------------------------------------------------------------------
step "Apply the monitoring objects"
# ---------------------------------------------------------------------------
kubectl apply -f monitoring/servicemonitors.yaml
kubectl apply -f monitoring/alerts.yaml

# ---------------------------------------------------------------------------
step "Result"
# ---------------------------------------------------------------------------
kubectl -n $NS get pods,svc,ingress,pvc
echo
echo "Application:  https://${HOST}/"
echo
echo "The browser will warn about the certificate. That is expected: it is"
echo "signed by your own in-cluster CA, which is not in any trust store."
echo
echo "Do not stop at the warning -- prove the chain. Export your CA"
echo "certificate from the Secret cert-manager wrote it to, then:"
echo
echo "  curl --cacert ca.crt https://${HOST}/ -o /dev/null -w '%{http_code}\\n'"
echo
echo "A 200 WITHOUT -k is the evidence Task 5 asks for. Put it in your report."
echo
echo "Next:  ./scripts/verify.sh ${HOST}"
