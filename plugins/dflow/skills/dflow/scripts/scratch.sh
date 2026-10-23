#!/usr/bin/env bash
# Print a fresh scratch directory for this dflow session and create it:
# <repo>/.dflow/tmp/<YYYYmmddTHHMMSS>[-<name>][-<n>] (or under $PWD outside a repo).
# Always a new directory: when the name is taken in the same second, -2, -3, ... is added.
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
mkdir -p "$root/.dflow/tmp" || exit 1
n=1; p=$d
until mkdir "$p" 2>/dev/null; do # exclusive: never reuse an existing directory
    n=$((n + 1)); p="$d-$n"
    [ "$n" -le 100 ] || { echo "FAIL cannot create $d" >&2; exit 1; }
done
echo "$p"
