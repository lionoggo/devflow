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
        # A code span opens with a run of n backticks and closes at the next run of exactly n;
        # a run with no closer stays as text.
        function nocode(s,    out, i, j, n, m, rest, closed) {
            out = ""
            while ((i = index(s, "`")) > 0) {
                out = out substr(s, 1, i - 1); s = substr(s, i)
                for (n = 0; substr(s, n + 1, 1) == "`"; n++) ;
                rest = substr(s, n + 1); closed = 0
                while ((j = index(rest, "`")) > 0) {
                    for (m = 0; substr(rest, j + m, 1) == "`"; m++) ;
                    if (m == n) { closed = 1; break }
                    rest = substr(rest, j + m)
                }
                if (closed) s = substr(rest, j + n)
                else { out = out substr(s, 1, n); s = substr(s, n + 1) }
            }
            return out s
        }
        NR == FNR { if ($0 !~ /^#/ && NF >= 3) { n++; rule[n] = $1; lang[n] = $2; term[n] = tolower($3); skip[n] = $4 } next }
        /^[ \t]*```/ { fence = !fence; next }
        fence || /^[ \t]*>/ || /<!-- slop-ok:/ { next }
        {
            line = nocode($0); low = tolower(line)
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
