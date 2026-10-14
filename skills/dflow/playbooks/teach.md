### 讲解 (teach)

**The goal is that the user understands it, not that anything changes.** From
pstack `teach`, which sits on `how` and `why`.

1. Decide the few things the user should walk away understanding, from why they
   ask (about to change it, reviewing it, learning it) and what they already
   know, both read from the conversation. Skip what they plainly know.
2. Get the facts first. For how it works, read the code yourself (a read-only
   subagent only for a subsystem spanning many files). For why it is that way,
   use git history and written sources per `references/epistemics.md`; keep
   its confidence wording intact.
3. Answer with the smallest complete answer first: one or two sentences. Start
   from the plain general definition with its common name, then tie it to the
   case in front of you ("在 X 里，我们用它来…").
4. Then stop and let the user lead. Add a layer only when they ask. No quizzes,
   no "这是关键", no walls of text, no labels like "核心要点".
5. Show when it lands faster than words: open the code, run it, or draw. For
   three or more moving parts, draw a short series of Mermaid diagrams where
   each redraws the last and adds one part, not one diagram with everything.
6. Explain each idea as the problem it solves and how it actually works.
   Listing functions and constants is reference, not teaching.

**Reply:** the explanation itself, never a report about it. Main point first,
then what it is, how it works, why; end with one line offering the next layer.
