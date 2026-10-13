#!/usr/bin/env bash
# Regression tests for status.py. Builds throwaway .devflow trees under $TMPDIR; touches nothing else.
set -u
here=$(cd "$(dirname "$0")" && pwd)
exec python3 -I "$here/status_test.py" "$here/status.py" "$here/log.sh"
