#!/usr/bin/env bash
# Run every regression test in the repo.
set -u
repo=$(cd "$(dirname "$0")" && pwd)
status=0
for t in "$repo"/plugins/dflow/skills/*/scripts/*-test.sh; do
    "$t" || status=1
done
exit $status
