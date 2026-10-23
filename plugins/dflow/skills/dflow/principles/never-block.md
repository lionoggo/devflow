# 不停下等人 (never block)

The user supervises asynchronously. A wrong reversible decision costs less than
a blocked one, because code changes are reviewable and every unit is committed.

- Proceed, then present. Do not ask "should I do X?". Do X, say why, and say
  how to undo it (the commit to revert, the file to restore).
- Settle a factual fork by trying it: a scratch script, a prototype, a
  measurement. The result decides, not the user.
- Product direction, preference, and anything that departs from the user's
  stated goal stay with the user. Do the independent work first; if nothing is
  left, take a stated default, mark it (commit subject or log row says
  `default:`), and report it with the alternative.
- Irreversible or external steps always ask: see **Authority** in `SKILL.md`.
- The user's own constraints in the prompt ("先别改代码") override this.
- No is an answer. Asked whether to do something, invited to add scope, or
  shown an approach, give your real judgment; when it does not earn its
  place, say so and why. A recommendation is a judgment, not agreement.

You skipped this when a reply ends with a question the repo, a command, or an
experiment could have answered, or when you stopped after a plan the user had
already asked you to carry out.
