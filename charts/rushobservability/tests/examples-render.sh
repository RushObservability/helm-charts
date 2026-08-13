#!/usr/bin/env bash
set -euo pipefail

chart_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo_dir="$(cd "$chart_dir/../.." && pwd)"

for values in "$repo_dir"/examples/*.yaml; do
  release="$(basename "$values" .yaml | tr -cd 'a-z0-9-')"
  helm template "$release" "$chart_dir" \
    -f "$values" \
    --set collectors.allowAnonymousIngest=true >/dev/null
done

echo 'all documented Helm examples rendered successfully'
