#!/usr/bin/env bash
set -euo pipefail

test_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${RUSH_TEST_PYTHON:-python3}" "$test_dir/spool-persistence-render.py"
