#!/usr/bin/env bash
#
# How much of the assessment is still unwritten?
#
# Run from the repository root:   ./scripts/check-progress.sh
#
# This only checks that you have REPLACED each skeleton. It cannot tell you
# whether what you wrote is any good -- that is what scripts/verify.sh is for,
# and after that, the rubric.
set -uo pipefail

[ -f TASKS.md ] || { echo "run this from the repository root" >&2; exit 1; }

CLOUD="${1:-}"
todo=0
done_=0

red=''; green=''; dim=''; off=''
if [ -t 1 ]; then red=$'\033[31m'; green=$'\033[32m'; dim=$'\033[2m'; off=$'\033[0m'; fi

item () {
  local task="$1" path="$2"
  if [ ! -e "$path" ]; then
    printf '  %sTO WRITE%s  %-46s %s(missing)%s\n' "$red" "$off" "$path" "$dim" "$off"
    todo=$((todo+1)); return
  fi
  # A skeleton still in place carries its "TO WRITE" banner.
  if grep -q 'TO WRITE --' "$path" 2>/dev/null; then
    printf '  %sTO WRITE%s  %-46s %s(skeleton untouched)%s\n' "$red" "$off" "$path" "$dim" "$off"
    todo=$((todo+1)); return
  fi
  if grep -q 'TODO-' "$path" 2>/dev/null; then
    local n; n=$(grep -c 'TODO-' "$path")
    printf '  %sTO WRITE%s  %-46s %s(%s placeholder(s) left)%s\n' "$red" "$off" "$path" "$dim" "$n" "$off"
    todo=$((todo+1)); return
  fi
  printf '  %swritten %s  %-46s\n' "$green" "$off" "$path"
  done_=$((done_+1))
}

echo
echo "Task 1  Infrastructure as code (12 marks)"
if [ -n "$CLOUD" ]; then
  item 1 "terraform/infra-$CLOUD/main.tf"
  item 1 "terraform/infra-$CLOUD/outputs.tf"
else
  found=0
  for c in aws azure catalyst; do
    if [ -d "terraform/infra-$c" ]; then
      item 1 "terraform/infra-$c/main.tf"
      item 1 "terraform/infra-$c/outputs.tf"
      found=$((found+1))
    fi
  done
  if [ "$found" -gt 1 ]; then
    echo "  ${dim}note: all $found cloud directories are still present. Pick one, write it,"
    echo "        and delete the others before you submit. Pass the name as an argument"
    echo "        to check only yours:  ./scripts/check-progress.sh azure${off}"
  fi
fi

echo
echo "Task 2  Platform orchestration (10 marks)"
item 2 "terraform/platform/main.tf"

echo
echo "Task 3  Microservices and images (12 marks)"
item 3 "app/orders/Dockerfile"
item 3 "app/frontend/Dockerfile"

echo
echo "Task 4  Kubernetes workloads and storage (12 marks)"
item 4 "manifests/01-config.yaml"
item 4 "manifests/02-redis.yaml"
item 4 "manifests/04-orders.yaml"
item 4 "manifests/05-frontend.yaml"

echo
echo "Task 5  Hostname, TLS and secure publication (13 marks)"
item 5 "manifests/06-tls.yaml"
item 5 "manifests/07-ingress.yaml"

echo
echo "Task 6  Monitoring with Prometheus (14 marks)"
item 6 "monitoring/alerts.yaml"

echo
echo "Task 7  Grafana dashboard (7 marks)"
item 7 "monitoring/grafana-dashboard.json"

echo
printf '  written: %s   still to write: %s\n' "$done_" "$todo"

# --- things that are not files -------------------------------------------
echo
echo "Not checked by this script -- do not forget them:"
echo "  - a business metric of your own, added to app/orders or app/frontend  (Task 6)"
echo "  - the teaching example removed:  kubectl -n shop get ingress"
echo "    (exactly one Ingress, yours -- not example-catalog-http)"
echo "  - the hostname rendered into 07-ingress.yaml by scripts/render.sh"
echo "  - your implementation report, with the evidence each task asks for"
echo "  - your critical evaluation, 1500 words max                            (Task 8)"

# --- the one thing that can cap a criterion regardless of quality ----------
echo
echo "Secret scan:"
if git rev-parse --git-dir >/dev/null 2>&1; then
  hits=$(git grep -In -E 'BEGIN [A-Z ]*PRIVATE KEY|aws_secret_access_key|client_secret|OS_PASSWORD=' \
         -- . ':!*.md' ':!scripts/check-progress.sh' 2>/dev/null | head -20)
else
  hits=$(grep -rIn -E 'BEGIN [A-Z ]*PRIVATE KEY|aws_secret_access_key|client_secret|OS_PASSWORD=' . \
         --exclude-dir=.git --exclude-dir=.terraform --exclude='*.md' \
         --exclude='check-progress.sh' 2>/dev/null | head -20)
fi
if [ -n "$hits" ]; then
  printf '  %sLOOK AT THESE%s\n%s\n' "$red" "$off" "$hits"
  echo "  A committed credential caps Criterion 4 at Not achieved."
else
  printf '  %snothing obvious%s -- still check by eye before you submit\n' "$green" "$off"
fi
echo

[ "$todo" -eq 0 ]
