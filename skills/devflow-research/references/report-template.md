# Research Report Template

Always include 结论与解释 and 证据与边界. For a document meant for others, also
include the header line (repo, commit, date, scope) and 问题与难点.

Everything else: include it only when the content or the
user's stated purpose needs it. Sections follow purpose; the
structures below are writing aids, not quotas. What is required is the
content, not the exact heading: for example 结论与解释 may be split into 核心思路
and 关键设计, and 证据与边界 may be titled 未验证项与盲区. Write in Simplified
Chinese.

Suggested order: problem → overview → key designs → flow → worked example.
Keep the body explanatory; put code locations in evidence lines, table columns,
or the code index rather than interrupting every sentence.

```markdown
# <调研主题>

> <仓库名> @ <commit hash> · <YYYY-MM-DD> · 范围：<包含>；不含 <不包含>

## 问题与难点
<一两段：直接做会怎样失败，所以真正的难点是什么。术语在第一次出现时就地解释。>

## 结论与解释
<核心思路，以及决定结果的关键设计。设计多且复杂时，可以每个设计用下面的结构：>

### <设计名>
- 问题：<它要解决什么>
- 做法：<怎么做的，写明适用条件和默认路径>
- 为什么：<不这样会怎样>
- 代价：<换来了什么限制或成本>
- 证据：`path:line`

## 整体架构
<架构图 + 各部分职责。职责表不要和代码索引重复。>

## 核心流程
<流程图或时序图。关键设计里讲过的原因不再重复。>

## 案例演练
<标明「实际演练」（本次实际运行的输出）或「推演」（依据代码或测试断言推演，或写成"如果……则……"的假设）。不需要为了"实际演练"去跑测试。>

## 通俗类比
<类比元素 → 实际代码的对照表。>

## 业内对照
<见 industry-comparison.md，只做定位，不做选型建议。>

## 可借鉴的思路
<仅当用户说明文档要给别人借鉴时。不重复关键设计。>

## 扩展点
<读者可能要改代码时：新增或修改某类行为要改哪些表、函数、配置。>

## 证据与边界
- [推测] <内容> — 验证方式：<需要什么证据>
- 未覆盖：<没看的部分及原因>

## 代码索引
| 概念 | 位置 |
|---|---|
| ... | `path:line` |
```

Rules:

- Record the commit hash with `git rev-parse --short HEAD`, and note if the
  working tree was dirty.
- Thresholds and parameters belong inside the design or flow they explain,
  with the intuition first and the number second.
