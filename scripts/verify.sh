#!/usr/bin/env bash
#
# Self-check before submission. Run on the node.
# Every line that prints FAIL is a mark you are about to lose.
set -uo pipefail

HOST="${1:-}"
pass=0; fail=0

check () {
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then
    printf '  PASS  %s\n' "$label"; pass=$((pass+1))
  else
    printf '  FAIL  %s\n' "$label"; fail=$((fail+1))
  fi
}

echo "== cluster =="
check "node Ready"                kubectl get nodes --no-headers -o wide
check "shop namespace exists"     kubectl get ns shop
check "cert-manager running"      kubectl -n cert-manager get deploy cert-manager
check "ingress-nginx running"     kubectl -n ingress-nginx get deploy ingress-nginx-controller
check "prometheus running"        kubectl -n monitoring get statefulset -l app.kubernetes.io/name=prometheus

echo "== workloads =="
for d in catalog orders frontend redis; do
  check "deployment/$d available" kubectl -n shop wait --for=condition=available --timeout=5s deploy/$d
done
check "redis PVC bound"           bash -c '[ "$(kubectl -n shop get pvc redis-data -o jsonpath={.status.phase})" = Bound ]'

echo "== config =="
check "ConfigMap present"         kubectl -n shop get configmap shop-config
check "Secret present"            kubectl -n shop get secret shop-secrets
check "secret reaches container"  bash -c 'kubectl -n shop exec deploy/orders -- printenv DB_PASSWORD | grep -q .'

echo "== endpoints wired =="
for s in catalog orders frontend redis; do
  check "endpoints/$s non-empty"  bash -c "[ -n \"\$(kubectl -n shop get endpoints $s -o jsonpath='{.subsets[*].addresses[*].ip}')\" ]"
done

echo "== TLS =="
check "Certificate Ready"         bash -c '[ "$(kubectl -n shop get certificate shop-tls -o jsonpath={.status.conditions[0].status})" = True ]'
check "tls secret has a cert"     bash -c 'kubectl -n shop get secret shop-tls -o jsonpath={.data."tls\.crt"} | grep -q .'
check "Ingress has an address"    bash -c '[ -n "$(kubectl -n shop get ingress shop -o jsonpath={.status.loadBalancer.ingress[0].ip})" ]'

echo "== monitoring =="
check "ServiceMonitor present"    kubectl -n shop get servicemonitor shop-services
check "PrometheusRule present"    kubectl -n shop get prometheusrule shop-alerts
check "app metrics exposed"       bash -c 'kubectl -n shop exec deploy/orders -- python -c "
import urllib.request
d=urllib.request.urlopen(\"http://127.0.0.1:5000/metrics\",timeout=5).read().decode()
assert \"flask_http_request_total\" in d
assert \"order_catalog_cache_lookups_total\" in d
"'

if [ -n "$HOST" ]; then
  echo "== end to end (https://$HOST/) =="
  check "HTTPS responds 200"      bash -c "curl -sk -o /dev/null -w '%{http_code}' https://$HOST/ | grep -q 200"
  check "HTTP redirects to HTTPS" bash -c "curl -s -o /dev/null -w '%{redirect_url}' http://$HOST/ | grep -q '^https://'"
  check "cert CN matches host"    bash -c "echo | openssl s_client -connect $HOST:443 -servername $HOST 2>/dev/null | openssl x509 -noout -text | grep -q $HOST"
else
  echo "== end to end: skipped (pass your hostname as argument) =="
fi

echo
echo "passed: $pass   failed: $fail"
[ "$fail" -eq 0 ]
