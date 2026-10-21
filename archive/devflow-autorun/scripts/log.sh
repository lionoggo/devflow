#!/usr/bin/env bash
# Append one row to a devflow-autorun decision log (TSV).
# Usage: log.sh <logfile> <phase> <decision> <why> <evidence> <result>
#
# Adapted from pstack show-me-your-work/scripts/log.sh
# (https://github.com/cursor/plugins/tree/main/pstack).
# MIT License, Copyright (c) 2026 Lauren Tan.
set -euo pipefail

if [ "$#" -ne 6 ]; then
    printf 'usage: log.sh <logfile> <phase> <decision> <why> <evidence> <result>\n' >&2
    exit 1
fi

logfile="$1"
shift

logdir="$(dirname "$logfile")"
if [ -n "$logdir" ] && [ "$logdir" != "." ] && [ ! -d "$logdir" ]; then
    mkdir -p "$logdir"
fi

# Append only (`>>`): a failed existence test costs one stray header, never rows.
if [ ! -s "$logfile" ]; then
    printf 'ts\tphase\tdecision\twhy\tevidence\tresult\n' >> "$logfile"
fi

ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
# Keep cells single-line, and quote cells a spreadsheet would run as formulas.
clean() {
    local v
    v=$(printf '%s' "$1" | tr '\t\n\r' '   ')
    case "$v" in
        =*|+*|-*|@*) printf "'%s" "$v" ;;
        *) printf '%s' "$v" ;;
    esac
}
printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$ts" "$(clean "$1")" "$(clean "$2")" "$(clean "$3")" "$(clean "$4")" "$(clean "$5")" \
    >> "$logfile"
