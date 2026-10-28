#!/usr/bin/env bash
#
# Substitute your own hostname into the Ingress and Certificate manifests.
#
#   ./scripts/render.sh myshop.australiaeast.cloudapp.azure.com   (Azure)
#   ./scripts/render.sh shop.13-55-2-9.sslip.io                   (AWS / Catalyst)
#
# Get the hostname from stage 1:  terraform -chdir=terraform/infra output -raw shop_host
set -euo pipefail

HOST="${1:-}"
if [ -z "$HOST" ]; then
  echo "usage: $0 <hostname>" >&2
  echo "example: $0 shop.13-55-2-9.sslip.io" >&2
  exit 1
fi

# Fail early on a hostname that will not resolve, rather than after a
# certificate has already been issued for it.
if ! getent hosts "$HOST" >/dev/null 2>&1; then
  echo "WARNING: $HOST does not resolve from this machine." >&2
  echo "         Azure publishes <label>.<region>.cloudapp.azure.com for any" >&2
  echo "         public IP with a DNS label. AWS and Catalyst use sslip.io," >&2
  echo "         which resolves <name>.<dashed-ip>.sslip.io to that address." >&2
  echo "         Get yours with:" >&2
  echo "           terraform -chdir=terraform/infra-<cloud> output -raw shop_host" >&2
  read -r -p "Continue anyway? [y/N] " reply
  [ "$reply" = "y" ] || exit 1
fi

TARGET="manifests/07-ingress.yaml"
[ -f "$TARGET" ] || { echo "run this from the repository root" >&2; exit 1; }

if ! grep -q '__SHOP_HOST__' "$TARGET"; then
  echo "ERROR: no __SHOP_HOST__ placeholder in ${TARGET}." >&2
  echo >&2
  if grep -q 'TO WRITE --' "$TARGET"; then
    echo "  That file is still the supplied skeleton. Write the Certificate" >&2
    echo "  and the Ingress first -- the skeleton says what they need." >&2
  else
    echo "  Either you have already rendered it, or you typed your hostname" >&2
    echo "  in directly. If it is the latter, put the placeholder back: a" >&2
    echo "  hardcoded hostname makes the repository non-reproducible, and" >&2
    echo "  Task 5 marks that." >&2
  fi
  exit 1
fi

sed -i.bak "s/__SHOP_HOST__/${HOST}/g" "$TARGET"
rm -f "${TARGET}.bak"

echo "Rendered ${TARGET} for ${HOST}:"
grep -n "$HOST" "$TARGET"
