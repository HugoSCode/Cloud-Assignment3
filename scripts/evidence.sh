#!/usr/bin/env bash
#
# Capture the terminal evidence the brief asks for, into evidence/.
# Screenshots you still have to take yourself.
#
#   ./scripts/evidence.sh <host>
set -uo pipefail

HOST="${1:-}"
OUT="evidence"
NS=shop
[ -z "$HOST" ] && { echo "usage: $0 <host>" >&2; exit 1; }

mkdir -p "$OUT"
run () { local f="$1"; shift; echo "  -> $OUT/$f"; { echo "\$ $*"; echo; "$@"; } > "$OUT/$f" 2>&1 || true; }

echo "Capturing evidence for https://${HOST}/"

echo "[1] infrastructure"
TFDIR="${TFDIR:-$(ls -d terraform/infra-* 2>/dev/null | head -1)}"
run 01-terraform-infra-show.txt  terraform -chdir="$TFDIR" show
run 02-terraform-infra-output.txt terraform -chdir="$TFDIR" output
run 03-terraform-infra-plan.txt  terraform -chdir="$TFDIR" plan -detailed-exitcode

echo "[2] platform"
run 04-helm-list.txt             helm list -A
run 05-platform-pods.txt         kubectl get pods -A

echo "[3] images"
run 06-registry-catalogue.txt    curl -s http://localhost:32000/v2/_catalog
run 07-deployment-images.txt     kubectl -n $NS get deploy -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.template.spec.containers[0].image}{"\n"}{end}'

echo "[4] workloads, config, storage"
run 08-get-all.txt               kubectl -n $NS get all,pvc,configmap,secret
run 09-describe-pvc.txt          kubectl -n $NS describe pvc redis-data
run 10-configmap.txt             kubectl -n $NS get configmap shop-config -o yaml
run 11-secret-reaches-pod.txt    kubectl -n $NS exec deploy/orders -- printenv DB_PASSWORD
run 12-probes.txt                kubectl -n $NS get deploy frontend -o jsonpath='{.spec.template.spec.containers[0].readinessProbe}{"\n"}{.spec.template.spec.containers[0].livenessProbe}'

echo "[5] TLS"
run 13-certificate.txt           kubectl -n $NS describe certificate shop-tls
run 14-clusterissuers.txt        kubectl get clusterissuer
echo "  -> $OUT/15-served-certificate.txt"
{ echo "\$ openssl s_client -connect ${HOST}:443 -servername ${HOST}"; echo;
  echo | openssl s_client -connect "${HOST}:443" -servername "${HOST}" 2>/dev/null \
    | openssl x509 -noout -subject -issuer -dates -ext subjectAltName; } \
  > "$OUT/15-served-certificate.txt" 2>&1 || true
echo "  -> $OUT/16-http-redirect.txt"
{ echo "\$ curl -s -o /dev/null -w '%{http_code} -> %{redirect_url}' http://${HOST}/"; echo;
  curl -s -o /dev/null -w '%{http_code} -> %{redirect_url}\n' "http://${HOST}/"; } \
  > "$OUT/16-http-redirect.txt" 2>&1 || true

echo "[6] monitoring"
run 17-servicemonitors.txt       kubectl -n $NS get servicemonitor -o yaml
run 18-prometheusrules.txt       kubectl -n $NS get prometheusrule -o yaml

PROM_POD=$(kubectl -n monitoring get pod -l app.kubernetes.io/name=prometheus \
             -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [ -n "$PROM_POD" ]; then
  promq () {
    kubectl -n monitoring exec "$PROM_POD" -c prometheus -- \
      wget -qO- "http://127.0.0.1:9090/api/v1/query?query=$1" 2>/dev/null
  }
  echo "  -> $OUT/19-promql-five-layers.txt"
  {
    echo "Layer 1 -- host (node-exporter)";        promq 'node_memory_MemAvailable_bytes'; echo
    echo "Layer 2 -- cluster (kube-state-metrics)"; promq 'kube_deployment_status_replicas_ready%7Bnamespace%3D%22shop%22%7D'; echo
    echo "Layer 3 -- containers (cAdvisor)";        promq 'container_memory_working_set_bytes%7Bnamespace%3D%22shop%22%7D'; echo
    echo "Layer 4 -- ingress edge";                 promq 'nginx_ingress_controller_requests'; echo
    echo "Layer 5 -- application";                  promq 'flask_http_request_total%7Bnamespace%3D%22shop%22%7D'; echo
    echo "Business metric";                         promq 'order_catalog_cache_lookups_total'; echo
  } > "$OUT/19-promql-five-layers.txt" 2>&1
  echo "  -> $OUT/20-targets.txt"
  kubectl -n monitoring exec "$PROM_POD" -c prometheus -- \
    wget -qO- 'http://127.0.0.1:9090/api/v1/targets?state=active' > "$OUT/20-targets.txt" 2>&1 || true
  echo "  -> $OUT/21-alerts.txt"
  kubectl -n monitoring exec "$PROM_POD" -c prometheus -- \
    wget -qO- 'http://127.0.0.1:9090/api/v1/rules' > "$OUT/21-alerts.txt" 2>&1 || true
else
  echo "  SKIP Prometheus queries -- pod not found"
fi

echo "[7] self-check"
run 22-verify.txt                ./scripts/verify.sh "$HOST"

echo
echo "Done. $(ls -1 "$OUT" | wc -l) files in $OUT/"
echo "Still to capture by hand: browser screenshots of the app over HTTPS,"
echo "the Grafana dashboard under load, and an alert in Firing state."
