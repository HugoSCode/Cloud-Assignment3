#!/usr/bin/env bash
#
# Drive traffic at the deployment so the dashboards and alerts have something
# to show. Needed for Task 8 (performance under load).
#
#   ./scripts/generate-load.sh <host> [seconds] [mode] [concurrency]
#
#   mode = browse   steady GETs of the front page          (default)
#          order    places orders, exercising the full chain
#          errors   requests a product that does not exist, raising the 4xx rate
#          mixed    a realistic blend of all three
#
# NOTE: "errors" produces 4xx, not 5xx. A missing product is a client error,
# and an alert filtered on status=~"5.." will correctly NOT fire for it. To
# raise genuine server errors, break a dependency instead:
#
#   kubectl -n shop scale deploy/catalog --replicas=0
#   ./scripts/generate-load.sh <host> 600 order 8
#
# The order service then returns 503 because it cannot reach the catalog.
# Note where that 5xx is visible: on the orders job, not at the ingress --
# the frontend still renders a page. That is worth a sentence in Task 8.
#
# Run this in one terminal and watch Grafana in another.
set -uo pipefail

HOST="${1:-}"
DURATION="${2:-300}"
MODE="${3:-browse}"
CONCURRENCY="${4:-4}"

if [ -z "$HOST" ]; then
  echo "usage: $0 <host> [seconds] [browse|order|errors|mixed] [concurrency]" >&2
  echo "example: $0 myshop.australiaeast.cloudapp.azure.com 300 mixed 8" >&2
  exit 1
fi

BASE="https://${HOST}"
# -k because the certificate is signed by our own CA, which curl does not trust.
# For a run that validates the chain instead, use:  --cacert ca.crt
CURL="curl -sk --max-time 10"

echo "Driving ${BASE} for ${DURATION}s, mode=${MODE}, concurrency=${CONCURRENCY}"
echo "Ctrl+C to stop early."

worker () {
  local id="$1"
  local end=$(( $(date +%s) + DURATION ))
  local n=0
  while [ "$(date +%s)" -lt "$end" ]; do
    case "$MODE" in
      browse)
        $CURL -o /dev/null "${BASE}/"
        ;;
      order)
        $CURL -o /dev/null -X POST "${BASE}/order" \
          -d "product_id=$(( (RANDOM % 4) + 1 ))&quantity=1"
        ;;
      errors)
        # product 99 does not exist -> the order service returns 404
        $CURL -o /dev/null -X POST "${BASE}/order" -d "product_id=99&quantity=1"
        ;;
      mixed)
        case $(( RANDOM % 10 )) in
          0|1) $CURL -o /dev/null -X POST "${BASE}/order" \
                 -d "product_id=$(( (RANDOM % 4) + 1 ))&quantity=1" ;;
          2)   $CURL -o /dev/null -X POST "${BASE}/order" -d "product_id=99&quantity=1" ;;
          *)   $CURL -o /dev/null "${BASE}/" ;;
        esac
        ;;
      *)
        echo "unknown mode: $MODE" >&2; exit 1
        ;;
    esac
    n=$(( n + 1 ))
    sleep 0.15
  done
  echo "  worker ${id} sent ${n} requests"
}

for i in $(seq 1 "$CONCURRENCY"); do worker "$i" & done
wait

echo "Done."
