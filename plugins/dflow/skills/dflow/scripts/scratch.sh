#!/usr/bin/env bash
# Print a fresh scratch directory for this dflow session and create it:
# <repo>/.dflow/tmp/<YYYYmmddTHHMMSS>[-<name>] (or under $PWD outside a repo).
# Inside a repo, makes sure .git/info/exclude ignores .dflow/ (local only, never committed).
# Usage: d=$(scratch.sh [name])
set -u
root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
if ex=$(git rev-parse --git-path info/exclude 2>/dev/null); then
    case $ex in /*) ;; *) ex="$PWD/$ex" ;; esac
    mkdir -p "$(dirname "$ex")"
    grep -qx '.dflow/' "$ex" 2>/dev/null || echo '.dflow/' >> "$ex"
fi
d="$root/.dflow/tmp/$(date +%Y%m%dT%H%M%S)${1:+-$1}"
mkdir -p "$d" && echo "$d"
