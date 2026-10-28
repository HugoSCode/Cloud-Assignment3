#!/usr/bin/env bash
#
# Build all three service images and push them to the MicroK8s registry.
# Each service has its own build context: you can rebuild one without
# touching the others.
#
#   ./scripts/build-images.sh v1
set -euo pipefail

TAG="${1:-v1}"
REGISTRY="localhost:32000"

SERVICES=(
  "app/catalog:catalog-service"
  "app/orders:order-service"
  "app/frontend:frontend"
)

for entry in "${SERVICES[@]}"; do
  dir="${entry%%:*}"
  name="${entry##*:}"
  image="${REGISTRY}/${name}:${TAG}"

  echo "--- ${image} (context: ${dir}) ---"
  docker build -t "${image}" "${dir}"
  docker push "${image}"
done

echo
echo "Registry now holds:"
curl -s "http://${REGISTRY}/v2/_catalog"
echo
