# 润色 (unslop)

**Cut AI tells from writing in Chinese or English. Keep the meaning and the
intended tone.** From pstack `unslop`; rules 3–33 keep pstack's numbers
(other skills cite them, a removed rule leaves a gap); rules 34+ are Chinese
additions. Each rule says where it applies: 中英 (both), 仅英文, or 仅中文.

Use it when the user asks ("润色", "去 AI 腔", "精简这段"), and for text
others will read later (plan docs, reports, handoff prompts, commit messages,
PR bodies). For a file: rewrite it, run `scripts/slop-check.sh <file>`, fix
or justify each unexempted hit, commit locally, and write the 影响面 line
(`无需行为冒烟，仅改文字`). Before and after, the numbers, negations, scope,
owners, and sources must be unchanged; check each one.

`scripts/slop-check.sh` catches the word-list part only. Sentence patterns
need your judgment. It skips code blocks and `>` quotes; a line ending in
`<!-- slop-ok: <理由> -->` is exempt.

## Content

3. **Superficial -ing phrases** (仅英文). "highlighting...", "ensuring...",
   "reflecting...", "showcasing...". Delete or expand with real sources.
5. **Vague attributions** (中英). "Experts believe", "Industry reports
   suggest"; "业内普遍认为", "研究表明", "专家指出", "大家都知道". Name the
   source or delete.

## Language

7. **AI vocabulary** (中英). Additionally, crucial, delve, enduring, enhance,
   fostering, garner, interplay, intricate, landscape (abstract), pivotal,
   showcase, tapestry (abstract), testament, underscore, vibrant. 中文：赋能、
   抓手、闭环、打通、沉淀、心智、底层逻辑、颗粒度、对齐（非字面）、助力、
   深耕、全方位、多维度. Replace with plain words.
8. **Fancy ways to say "is"** (中英). "serves as", "stands as", "boasts";
   "作为…而存在", "扮演着…的角色", "承担着…的使命". Say "is"/"是" or
   "has"/"有".
9. **"Not just X, but Y"** (中英). "不仅仅是…更是…", "不只是…而是…". State
   the point directly.
10. **Rule of three** (中英). Don't force ideas into groups of three; use the
    natural number.
11. **Synonym cycling** (中英). One object, one name: not 剧本 / 流程 / 工作流
    for the same thing in one paragraph.
12. **False ranges** (中英). "from X to Y" / "从 X 到 Y" where X and Y are
    not on one scale. List the items.

## Style

13. **Dash overuse** (中英). No em dashes in English. In Chinese avoid
    "——" used to splice sentences; end the sentence or use a comma.
14. **Colon overuse** (中英). Colons ("：") before a list or an example are
    fine; not as a mid-sentence connector.
15. **Boldface overuse** (中英). Bold only the few words the reader must not
    miss.
16. **Inline-header lists** (中英). "**性能：** 性能提升了…" restates the
    label; write it as a sentence. A bold lead-in that names the item and is
    followed by new detail is fine.
17. **Title case headings** (仅英文). Use sentence case.
18. **Decorative emojis** (中英). Remove from headings and bullets.
19. **Curly quotes** (仅英文). Use straight quotes.

## Communication artifacts

20. **Chatbot phrases** (中英). "I hope this helps!", "Let me know if...";
    "希望对你有帮助", "如有问题随时告诉我", "当然！", "好的，我来…". Remove.
22. **Sycophantic tone** (中英). "Great question!"; "好问题！", "你说得完全
    正确！". Respond directly.

## Filler

23. **Filler phrases** (中英). "In order to" → "To"; "值得注意的是",
    "需要指出的是", "总的来说", "众所周知", "在…的背景下". Delete.
24. **Excessive hedging** (中英). "could potentially possibly"; "可能也许在
    一定程度上". Keep one hedge, or state the evidence level.
25. **Generic conclusions** (中英). "The future looks bright"; "未来可期",
    "意义重大", "具有重要价值". State a specific plan or fact.

## Jargon

26. **Abstract metaphor nouns** (中英). Substrate, wedge, vector, locus,
    nexus, primitive (noun), harness (metaphor), surface ("API surface"),
    bedrock, scaffolding (metaphor), paradigm, north star, flywheel; 中文：
    底座、飞轮、北极星、护城河、基建（非字面）、链路（非网络）、矩阵（非数学）.
    Use the concrete word.

## Plain speech

27. **Say what it does, not how it feels** (中英). Name the mechanism or a
    number. If the sentence could appear unchanged in another project's docs,
    cut it.
28. **Shorten or split dense sentences** (中英). One idea per sentence.
29. **Active voice** (中英). Name the actor: "被…所…" → who does what.
30. **Cut adverbs** (中英). "显著提升" → the measured delta.
31. **Prefer the plain word** (中英). utilize/leverage → use; 进行优化 → 优化;
    予以 → 给.
32. **Mannered prose** (中英). Aphorisms, personified code, figurative verbs
    where a literal phrase exists.
33. **Over-compression** (中英). Dropped verbs, arrows, symbol-speak,
    abbreviations the reader must decode. "解析失败 → 退出 2" → "解析失败
    时以退出码 2 退出，不写入文件。"

## Chinese additions

34. **Translationese** (仅中文). "对…进行了…的操作", "作为一个…", "基于…的
    考虑". Use a direct verb: "对代码进行了重构" → "重构了代码".
35. **Nominalization stacks** (仅中文). "实现对数据的有效管理" → "管好数据".
36. **Four-character pileups** (仅中文). "全面系统深入扎实" → the concrete
    actions.
37. **Coined terms, internal IDs, English field names** (中英). Terms the
    reader never learned, ticket or stage IDs, raw field names
    (`close_state`, `parked:`) in prose for a person. Say what it means. The
    user's history has this correction more than any other writing issue.
38. **Needless code-switching** (仅中文). "这个 feature 的 scope" → "这个功能
    的范围", when a common Chinese word exists. Keep established technical
    terms (API, commit, PR) and code names.
