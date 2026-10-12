# Diagrams

A diagram earns its place only when it shows a relationship that prose makes
hard to follow. It never replaces the explanation; each diagram is followed by
text naming the code behind its key nodes.

## Choosing a Diagram

| Content | Mermaid type |
|---|---|
| Module relationships, layers, ownership | `flowchart` (architecture view, subgraphs for layers) |
| Ordered steps with branches | `flowchart TD` |
| Calls or messages between components over time | `sequenceDiagram` |
| State transitions (animation states, lifecycles) | `stateDiagram-v2` |
| Data model relationships | `classDiagram` or `erDiagram` |
| Timeline or frame scheduling | `gantt` or a table |

## Rules

- Use Mermaid in fenced ```mermaid blocks so documents render in common
  Markdown viewers.
- Node labels use real names from code (function, class, file) where they
  exist, plus a short Chinese gloss when helpful.
- Keep one diagram to one idea and roughly 15 nodes; split larger views.
- Quote labels containing punctuation, parentheses, or non-ASCII characters:
  `A["加载配置 (config.ts)"]`.
- Terminal output cannot render Mermaid. In a short direct answer, prefer a short numbered list or
  an ASCII sketch unless the user asks for Mermaid.
