#!/usr/bin/env bash
#
# The Task 8 failure experiments, run in order with pauses so you can capture
# the dashboard and the alert state at each stage.
#
#   ./scripts/failure-drill.sh <host>
#
# Keep generate-load.sh running in another terminal throughout.
set -uo pipefail

HOST="${1:-}"
NS=shop
PAUSE="${PAUSE:-120}"

[ -z "$HOST" ] && { echo "usage: $0 <host>" >&2; exit 1; }

probe () {
  printf '    HTTP %s in %ss\n' \
    "$(curl -sk -o /dev/null -w '%{http_code}' --max-time 10 "https://${HOST}/")" \
    "$(curl -sk -o /dev/null -w '%{time_total}' --max-time 10 "https://${HOST}/")"
}

banner () { echo; echo "=============================================================="; echo "$1"; echo "=============================================================="; }

banner "BASELINE -- everything healthy"
kubectl -n $NS get pods
probe
echo "  Capture the dashboard now. Continuing in ${PAUSE}s..."
sleep "$PAUSE"

banner "EXPERIMENT A -- catalog service removed"
echo "  Expected: page still returns 200. Catalog panel shows unreachable."
echo "            Past orders still listed. New orders refused with 503."
kubectl -n $NS scale deployment catalog --replicas=0
sleep 15
probe
kubectl -n $NS get endpoints catalog
echo "  Capture now. Restoring in ${PAUSE}s..."
sleep "$PAUSE"
kubectl -n $NS scale deployment catalog --replicas=2
kubectl -n $NS rollout status deployment/catalog --timeout=120s

banner "EXPERIMENT B -- datastore removed"
echo "  Expected: page still 200 and still FAST. Order service healthy but"
echo "            reports store_available=false. Note this is a DIFFERENT"
echo "            failure from A, and the page says so."
kubectl -n $NS scale deployment redis --replicas=0
sleep 15
probe
kubectl -n $NS exec deploy/frontend -- \
  python -c "import requests; r=requests.get('http://orders:5000/orders',timeout=5); print('   orders API:', r.status_code, r.text[:120])" 2>/dev/null || true
echo "  Capture now. Restoring in ${PAUSE}s..."
sleep "$PAUSE"
kubectl -n $NS scale deployment redis --replicas=1
kubectl -n $NS rollout status deployment/redis --timeout=120s

banner "EXPERIMENT C -- scale the catalog independently"
kubectl -n $NS scale deployment catalog --replicas=5
kubectl -n $NS rollout status deployment/catalog --timeout=180s
kubectl -n $NS get pods -o wide
kubectl -n $NS get endpoints catalog
echo
echo "  Which catalog Pods actually answered:"
kubectl -n $NS exec deploy/frontend -- sh -c '
  for i in $(seq 1 30); do
    python -c "import requests;print(requests.get(\"http://catalog:5000/products\",timeout=5).json()[\"served_by\"])"
  done' 2>/dev/null | sort | uniq -c
echo "  Capture now. Restoring in ${PAUSE}s..."
sleep "$PAUSE"
kubectl -n $NS scale deployment catalog --replicas=2

banner "EXPERIMENT D -- did the orders survive?"
echo "  Redis has a PVC, so orders placed before Experiment B should still"
echo "  be here. Delete the Pod (not the PVC) and confirm."
kubectl -n $NS delete pod -l app=redis --wait=true
kubectl -n $NS rollout status deployment/redis --timeout=120s
sleep 10
kubectl -n $NS exec deploy/frontend -- \
  python -c "import requests; d=requests.get('http://orders:5000/orders',timeout=5).json(); print('   orders surviving Pod deletion:', len(d['orders']))" 2>/dev/null || true

banner "DRILL COMPLETE"
kubectl -n $NS get pods
