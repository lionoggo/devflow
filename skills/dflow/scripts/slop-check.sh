#!/usr/bin/env bash
# Report AI-tell words (references/unslop.md) in files or stdin. Reports only; never edits.
# Usage: slop-check.sh <file>... | slop-check.sh -
# Skips fenced code blocks, lines starting with ">", and `inline code`.
# A line containing "<!-- slop-ok:" is exempt. Exit: 0 no hits, 1 hits, 2 usage error.
set -u
here=$(cd "$(dirname "$0")" && pwd)
words="$here/slop-words.tsv"
[ $# -ge 1 ] || { echo "usage: slop-check.sh <file>... | -" >&2; exit 2; }
for f in "$@"; do
    [ "$f" = - ] || [ -r "$f" ] || { echo "slop-check: cannot read $f" >&2; exit 2; }
done
hits=0
for f in "$@"; do
    name=$f; [ "$f" = - ] && name=stdin
    out=$(awk -v name="$name" -F'\t' '
        NR == FNR { if ($0 !~ /^#/ && NF >= 3) { n++; rule[n] = $1; lang[n] = $2; term[n] = tolower($3); skip[n] = $4 } next }
        /^[ \t]*```/ { fence = !fence; next }
        fence || /^[ \t]*>/ || /<!-- slop-ok:/ { next }
        {
            line = $0; gsub(/`[^`]*`/, "", line); low = tolower(line)
            for (i = 1; i <= n; i++) {
                rest = low; off = 0; found = 0
                while ((p = index(rest, term[i])) > 0) {
                    pre = p + off > 1 ? substr(low, p + off - 1, 1) : ""
                    post = substr(low, p + off + length(term[i]), 1)
                    after = skip[i] != "" && p + off > length(skip[i]) && substr(low, p + off - length(skip[i]), length(skip[i])) == skip[i]
                    if (!after && (lang[i] != "en" || (pre !~ /[a-z]/ && post !~ /[a-z]/))) { found = 1; break }
                    off += p; rest = substr(rest, p + 1)
                }
                if (found) printf "%s:%d: [rule %s] %s: %s\n", name, FNR, rule[i], term[i], $0
            }
        }' "$words" "$f")
    if [ -n "$out" ]; then echo "$out"; hits=1; fi
done
exit $hits
