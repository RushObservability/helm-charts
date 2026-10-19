#!/usr/bin/env bash
set -euo pipefail
"${RUSH_TEST_PYTHON:-python3}" "$(dirname "$0")/spool-init.py"
