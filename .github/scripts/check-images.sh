#!/usr/bin/env bash
# Check that every image the charts and the compose stack use exists in its
# registry and has a linux/amd64 build. Render tests can't catch a tag that
# doesn't exist (Dependabot has proposed several), so this pulls manifests.
#
#   .github/scripts/check-images.sh
#
# Needs helm, docker and python3, built chart dependencies, and network access.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
core="$root/charts/rush-observability"
stack="$root/charts/rush-observability-stack"
dev=(--set queryApi.config.runtime.environment=development)
stack_dev=(--set rush.queryApi.config.runtime.environment=development)

rendered="$(
  helm template check "$core" "${dev[@]}" --set anomalyEngine.enabled=true
  helm template check "$core" "${dev[@]}" --set clickhouse.mode=standalone --set clickhouse.enabled=false
  helm template check "$stack" "${stack_dev[@]}" --set rush.queryApi.integrations.sreAgent.enabled=true
  cat "$root/compose/docker-compose.yml"
)"

images="$(python3 - "$rendered" <<'PY'
import re, sys
found = set()
for line in sys.argv[1].splitlines():
    m = re.match(r'\s*(?:-\s*)?image:\s*"?([^"\s]+)"?\s*$', line)
    if m and not m.group(1).startswith("{{"):
        found.add(m.group(1))
print("\n".join(sorted(found)))
PY
)"

failed=0
while read -r image; do
  [ -n "$image" ] || continue
  if ! manifest="$(docker manifest inspect --verbose "$image" 2>/dev/null)"; then
    echo "::error::image not found: $image"
    failed=1
    continue
  fi
  # --verbose prints one entry per platform (a list for multi-arch images, an
  # object for a single-platform one), each with its Descriptor.platform.
  if ! python3 -c '
import json, sys
m = json.load(sys.stdin)
entries = m if isinstance(m, list) else [m]
platforms = [e.get("Descriptor", {}).get("platform", {}) for e in entries]
sys.exit(0 if any(p.get("os") == "linux" and p.get("architecture") == "amd64" for p in platforms) else 1)' <<<"$manifest"; then
    echo "::error::image has no linux/amd64 build: $image"
    failed=1
    continue
  fi
  echo "ok  $image"
done <<<"$images"

exit "$failed"
