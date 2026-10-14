# 方案：dflow 并行实施

> 状态：待用户批准（第 1 版）。日期 2026-10-14。worktree `devflow-dflow`，分支 `dflow`。
> pstack 来源（sparse clone 837067b）：`poteto-mode/playbooks/feature.md` 的吞吐检查、`orchestrate.md`、`autopilot-full.md`、`autopilot-stack.md`、`worktree-cleanup.md`、`scripts/orch/`、`scripts/worktree-audit.sh`、`principle-separate-before-serializing-shared-state`。
> 实测（Claude Code 2.1.299）：子 agent 开 `isolation: "worktree"` 后，worktree 建在 `<仓库>/.claude/worktrees/agent-<id>`，分支 `worktree-agent-<id>`，从主目录当时的 HEAD 拉出；两个子 agent 并行在各自 worktree 提交，主目录 HEAD 不变；有提交的 worktree 不会自动删除；主目录出现未被忽略的 `.claude/`。

## 1. 结论

在实施和无人值守里加一个"并行"分支，相当于**本地版的 pstack autopilot-stack**：

- agent 自己判断能不能并行；
- 每个独立单元交给一个后台子 agent，在自己的 worktree 里写代码、跑检查、本地提交；
- 主会话只做协调：发任务说明、按依赖顺序把单元的提交 cherry-pick 到工作分支、每次落地后重跑已完成的条件、最后清理。

交付物是一条本地分支，上面按单元排好提交。不推送，不开 PR，不自动合并。

只有方案里有两个以上互不相交、规模也不小的单元时才并行；其余情况按原来的顺序做。

## 2. pstack 怎么做，dflow 取舍什么

| pstack 机制 | 出处 | dflow 怎么用 |
|---|---|---|
| 吞吐检查：先做的步骤、独立工作流（互不相交的文件）、共享状态、最小安全拆法；单 worker 时写明原因 | `feature.md` 第 3 步 | **照搬**，作为是否并行的判断步骤，由 agent 自己做 |
| 代码强耦合的功能交给一个负责人；顶层并行只给独立产物 | `feature.md` 末段 | **照搬**：有共享写入的单元不并行 |
| 先分离再串行：每个写入者有自己的文件、分支；只有真正必须共享时才串行，而且用结构保证，不靠约定 | `principle-separate-before-serializing-shared-state` | **照搬**：每个单元声明自己的写入路径，脚本检查互不相交；共享文件（README、注册表等）留给主会话在落地后统一改 |
| 任务说明模板：GOAL、SCOPE、CONTEXT、ACCEPTANCE、VERIFY、TIMEBOX、FORBIDDEN、REPORT、STANDING；缺字段就不派发；依赖单元的报告要贴给下游 | `orchestrate.md` "The brief" | **照搬**并精简，按单元大小缩放 |
| 每个分支只有一个写入者；worker 不 rebase、不推送 | `orchestrate.md`、`autopilot-full.md` 第 3 步 | **照搬**；worker 只在自己的 worktree 分支上提交 |
| 滚动窗口：完成一个补一个，不按批次等最慢的 | `orchestrate.md` 第 4 步 | **照搬**，同时最多 3 路（可在框定里改） |
| 先跑一个单元当"试点"，验证任务说明和验证方法，再铺开 | `orchestrate.md` 第 3 步 | **照搬**：第一个单元先单独跑完并落地，再并行其余单元 |
| 完成通知是排队事件，不打断；在固定时点集中处理 | `orchestrate.md` "Queue and drain" | **简化**：每次收到完成通知就处理这一个单元（落地或退回），再补位 |
| 验证按单元大小缩放：一条命令的，worker 跑、协调者抽查；贵的才派另一个模型的验证者 | `orchestrate.md` "Verification" | **照搬**：worker 报告检查输出；主会话落地后重跑所有已完成条件（集成验证）；收尾仍由 codex 审查决策日志 |
| 失败按类型重试：超时换小范围、网络错原样重试、未知错重试一次；两次失败就放弃并重新规划 | `orchestrate.md` "Liveness and failure" | **照搬**：重试一次（新的子 agent，不续接旧的）；再失败就改由主会话按顺序做，或标为死路 |
| 协调者从不写代码，冲突合并也是任务 | `orchestrate.md` "Roles" | **照搬**：cherry-pick 冲突时，主会话放弃这次落地（`git cherry-pick --abort`），把单元基于新 HEAD 重新派发；不手工解冲突 |
| 状态存储：units.tsv、ledger.tsv、inbox、gates、frontier、带锁的 CLI | `scripts/orch/`（约 2800 行 TypeScript） | **不搬**。dflow 一次运行最多十来个单元，用一张单元表加现有决策日志就够 |
| worktree 清理：审计、分类、只删已合并且干净的；有未提交改动的先问 | `worktree-cleanup.md`、`worktree-audit.sh` | **照搬规则**，只清理本次运行创建且已落地的 worktree 和分支 |
| 云端 worker、子协调者、gt 堆栈、自动合并（autopilot-full）、orchestrate 的多天程序 | 多处 | **不做**：超出规模，且推送和合并要先问用户 |

## 3. 方案

### 3.1 什么时候并行（吞吐检查）

在实施剧本"先定结构"之后、写代码之前，以及无人值守框定时，agent 写出四项：

1. **必须先做的步骤**：其他单元依赖的接口、类型、共享配置。它们先按顺序做完并提交。
2. **独立单元**：每个单元列出写入路径（glob）。两两不相交，并且不依赖彼此尚未落地的代码。
3. **共享状态**：多个单元都要改的文件（README、注册表、`__init__`、共同的测试入口）。默认从单元里拿出来，留给主会话在全部落地后统一改。
4. **结论**：并行几路，或者"按顺序做：<原因>"。

**启用条件**（全部满足才并行）：
- 至少 2 个独立单元；
- 每个单元预计改动在 50 行以上，或者需要跑超过 2 分钟的检查（更小的单元，并行的协调成本比省下的时间多）；
- `scripts/parallel.sh overlap` 确认写入路径互不相交。

不满足时写一行"并行：不启用，<原因>"，照常按顺序做。

### 3.2 授权

用户的全局规则是"未经明确要求不创建 worktree"。并行一定要建 worktree，所以：

- **无人值守**：框定里写明"并行 N 路，临时 worktree 建在 `.claude/worktrees/`，结束后清理"，回复"开始"即授权。
- **实施（用户在场）**：实施剧本平时不停下等人。建议在 `~/.codex/AGENTS.md` 那条 worktree 规则后加一句例外："dflow 并行实施可以在 `.claude/worktrees/` 下创建临时 worktree，结束后清理。"这是改全局规则文件，**随本方案一起请用户批准**；不批准的话，实施里遇到可并行的情况就停一次问"要不要并行"，其余照旧。

### 3.3 运行流程

1. **准备**：确认 `.git/info/exclude` 有 `.claude/worktrees/`（Claude Code 会建这个目录）。写单元表 `.dflow/<slug>-units.tsv`：`id deps paths state branch head landed`。只由主会话写。
2. **试点**：取第一个独立单元，按下面第 3、4 步跑完并落地。任务说明或验证方法有问题，就在这时修正，再铺开。
3. **派发**：为每个就绪单元（依赖都已落地）写任务说明（`references/unit-brief.md`），在一条消息里启动后台子 agent：`isolation: "worktree"`，`run_in_background: true`，模型 `sonnet`（写代码用，按全局规则不超过 Opus）。同时最多 3 路，完成一个补一个。worktree 从主目录当时的 HEAD 拉出，所以依赖单元落地后再派发的下游单元，能看到上游的代码。
4. **处理完成通知**（每到一个就处理一个）：
   1. 读 worker 的报告：分支、HEAD、跑过的检查及输出、偏差。
   2. `scripts/parallel.sh scope <分支> <单元写入路径>`：改动不能越出这个单元声明的路径。越界就退回。
   3. `scripts/parallel.sh land <分支>`：把这个分支相对派发时基线的提交，依次 cherry-pick 到当前工作分支。有冲突就自动 `--abort`，工作区恢复干净，报告冲突文件。
   4. 落地成功：重跑这个单元的检查，加上所有已完成阶段的条件。通过就在单元表记 `landed`，决策日志记一行（证据是落地后的提交 SHA）；不通过就 `git revert` 落地的提交，单元退回。
   5. 冲突或退回：用新的子 agent、基于新 HEAD 重做一次，任务说明里附上失败原因。第二次仍失败，就改由主会话按顺序做，或标为死路。不续接旧的子 agent。
5. **共享文件**：所有单元落地后，主会话统一改第 3.1 节第 3 项里的共享文件，作为一个普通单元提交。
6. **清理**：`scripts/parallel.sh cleanup`：
   - 删除本次运行创建、且已落地的 worktree（`git worktree remove`）和分支；
   - 未落地但有提交的：保留，报告分支名；
   - 有未提交改动的：保留，报告文件，不删除（照 `worktree-cleanup.md`：干净且已合并的直接删，有未提交工作的先问）。
7. **收尾**：照常走影响面、决策日志的对照和 codex 审查。回复里加一行"并行：N 路，落地 X 个单元，退回 Y 次，保留的 worktree：…"。

### 3.4 任务说明模板（`references/unit-brief.md`）

照 orchestrate 的 brief，按单元大小缩放；缺字段就不派发：

```
目标     一句话，不看对话也能执行
范围     只能改的路径；不能改的路径；你的 worktree 就是当前目录，只在这里提交
上下文   相关文件；依赖单元的报告原文（你看不到其他单元）
验收     能判对错的条件，每行一条
验证     要跑的命令；已知的坑
时限     大约多久；到时交回已有结果，不要硬撑
禁止     push、rebase、merge、reset、改分支、改范围外文件、改受保护路径
报告     状态、分支、HEAD、实际跑过的命令和输出、偏差、建议的后续
规则     dflow 的回复与提交规则：提交信息格式、只提交通过检查的改动
```

### 3.5 和无人值守的关系

- 一轮可以派出多个后台子 agent，然后结束本轮，等完成通知唤醒（Claude Code 的后台任务会唤醒会话）；同时动态 `/loop` 保留一个较长的兜底唤醒。
- "每轮结束工作区必须干净"仍成立：worker 在自己的 worktree 里改，主目录不变。
- 租约仍保证只有一个协调会话。
- 接手（新会话）：单元表里状态为"已派发"的单元，按分支实际情况处理：
  - 有提交，按第 4 步落地；
  - 没有提交，重新派发；
  - 有未提交改动，保留并报告，不删。
- 收尾检测里的 `scope` 照常检查整个运行分支。

### 3.6 新增脚本 `scripts/parallel.sh`

| 子命令 | 作用 |
|---|---|
| `overlap <单元表>` | 检查各单元写入路径两两不相交（按 glob 展开到当前文件，再加上 glob 本身的前缀比较）；相交就列出并以 1 退出 |
| `scope <分支> <glob…>` | 分支相对其基线的改动都在给定路径内；越界就列出并以 1 退出 |
| `land <分支> [<基线>]` | 把基线到分支的提交依次 cherry-pick 到当前分支；冲突时 `--abort`，列出冲突文件，以 1 退出；成功时输出新 HEAD |
| `cleanup <单元表>` | 按单元表删除已落地单元的 worktree 和分支；未落地或有未提交改动的保留并列出；从不删除本次运行以外的 worktree |

配测试 `parallel-test.sh`，覆盖：不相交、相交、越界、干净落地、冲突后工作区恢复干净、清理时保留有未提交改动的 worktree。

## 4. 文件变更

| 操作 | 路径 |
|---|---|
| 新增 | `skills/dflow/references/parallel.md`（第 3.1、3.3、3.5 节的执行规则） |
| 新增 | `skills/dflow/references/unit-brief.md` |
| 新增 | `skills/dflow/scripts/parallel.sh`、`parallel-test.sh` |
| 修改 | `skills/dflow/playbooks/build.md`：先定结构之后加吞吐检查，满足条件时按 `references/parallel.md` 执行；回复加"并行"一行 |
| 修改 | `skills/dflow/playbooks/unattended.md`：框定里加并行和 worktree 授权；一轮可以派发多个单元；接手时处理已派发的单元 |
| 修改 | `skills/dflow/SKILL.md`：子 agent 规则里写明并行实施的情况 |
| 修改（需用户批准） | `~/.codex/AGENTS.md`：worktree 规则后加并行实施的例外 |

## 5. 验收

演示仓库新建一个方案，含 1 个必须先做的接口单元、3 个互不相交的独立单元、1 个依赖其中两个的单元、1 个共享文件（README）。

- **P1 吞吐检查**：回复里有四项检查和"并行 N 路"的结论；`overlap` 通过。另用一个小方案（两个十行的单元），结论是"不启用"。
- **P2 并行执行**：先做接口单元并落地；试点单元单独跑完后，其余独立单元同时在不同 worktree 里运行（对话记录里有同一条消息内的多个后台 Agent 调用）；依赖单元在两个上游落地后才派发。
- **P3 落地与集成验证**：每个单元的提交按依赖顺序出现在工作分支上；每次落地后重跑已完成条件；README 最后统一修改。
- **P4 冲突**：预置两个声明不相交、实际都要改同一行的单元（例如都需要在同一个注册表里加一项）。第二个落地时冲突：工作区恢复干净，单元基于新 HEAD 重新派发后成功落地。
- **P5 越界**：任务说明之外改了别的文件的单元被 `scope` 拦下并退回。
- **P6 清理**：结束后 `git worktree list` 只剩主目录，本次的 `worktree-agent-*` 分支都已删除；预置一个有未提交改动的 worktree，它被保留并报告。
- **P7 无人值守并行**：在 tmux 交互会话里用无人值守跑同一个方案；中途杀掉会话，新会话接手时正确处理"已派发"的单元，不重复落地。
- **P8 成本对比**：同一方案顺序做一次、并行做一次，记录墙钟时间和费用。

## 6. 不做

- 自动合并、推送、开 PR（autopilot-full）。
- orchestrate 的多天程序、子协调者、云端 worker、状态存储 CLI。
- 手工解决合并冲突：冲突一律退回重做。
- Codex 宿主里的并行（无人值守只支持 Claude Code，并行同理）。

## 7. 风险

- **成本**：每个子 agent 都要重新熟悉代码，并行总花费高于顺序做。P8 会给出实测数字；启用门槛据此再调。
- **"互不相交"判断不准**：路径不相交不代表语义不冲突（比如两个单元都假设某个函数的旧行为）。缓解：每次落地后重跑所有已完成条件，倒退就撤回并退回单元。
- **Claude Code 的 worktree 行为可能随版本变化**：目录、分支命名、自动清理都是实测得到的，没有文档承诺。`parallel.sh` 从 `git worktree list` 读取实际路径，不写死目录名。
- **磁盘和构建缓存**：每个 worktree 都是一份完整的工作目录，大仓库（如 ludus 带 node_modules、Godot 导入缓存）会占空间、首次构建也慢。框定里写明预计占用；同时最多 3 路。
- **全局规则冲突**：如果不批准 AGENTS.md 的例外，实施（用户在场）时每次并行都要问一次。
