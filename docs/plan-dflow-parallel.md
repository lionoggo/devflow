# 方案：dflow 并行实施

> 状态：待用户批准（第 3 版，两轮 codex 评审均已处理，见第 9、10 节）。日期 2026-10-14。worktree `devflow-dflow`，分支 `dflow`。
> pstack 来源（sparse clone 837067b）：`poteto-mode/playbooks/feature.md`（吞吐检查）、`orchestrate.md`、`autopilot-full.md`、`autopilot-stack.md`、`worktree-cleanup.md`、`scripts/orch/`、`scripts/worktree-audit.sh`、`principle-separate-before-serializing-shared-state`。
> 实测（Claude Code 2.1.299，`claude -p`）：
> - 子 agent 开 `isolation: "worktree"` 后，worktree 建在 `<仓库>/.claude/worktrees/agent-<id>`，分支 `worktree-agent-<id>`，从主目录当时的 HEAD 拉出；
> - 两个后台子 agent 并行在各自 worktree 提交，主目录 HEAD 不变；
> - 子 agent 完成时会唤醒主会话（同一次运行出现 3 个结果回合）；
> - 有提交的 worktree 不会自动删除；主目录出现未被 Git 忽略的 `.claude/`；
> - 子 agent 的对话记录在 `~/.claude/projects/<项目>/<会话 id>/subagents/agent-<id>.jsonl`，id 与 worktree 名一致。

## 1. 结论

在实施和无人值守里加一个**用户选择启用**的"并行"分支，做法相当于本地版的 pstack autopilot-stack：

- agent 先做吞吐检查，判断能不能并行，在回复或框定里给出建议和预计代价；
- 用户说"并行"（或在无人值守框定里选并行后回复"开始"），才启用。这句话同时就是建 worktree 的明确授权，不需要改全局规则；
- 每个独立单元交给一个后台子 agent，在自己的 worktree 里写代码、跑仓库里已有的检查、本地提交；
- 主会话负责协调：写任务说明、把每个单元**压成一个提交**落到工作分支、跑完整检查（含受保护的检查）、最后清理。

交付物是一条本地分支，每个单元一个提交。不推送，不开 PR，不自动合并。

## 2. pstack 怎么做，dflow 取舍什么

| pstack 机制 | 出处 | dflow | 说明 |
|---|---|---|---|
| 吞吐检查：先做的步骤、独立工作流（互不相交的文件）、共享状态、最小安全拆法 | `feature.md` 第 3 步 | 照搬 | 作为是否建议并行的判断 |
| 代码耦合的工作交给一个负责人；顶层并行只给独立产物（审计、调研、对照实验） | `feature.md` 末段 | **改动** | pstack 在功能内部也并行，只是由负责人在内部拆（"owner fans out internally after the blocking phase"）。dflow 的主会话就是这个负责人，所以在主会话下直接拆，不再多一层负责人 |
| 先分离再串行；指令和约定不是并发控制 | `principle-separate-before-serializing-shared-state` | 照搬 | 写入路径由脚本检查互不相交；共享文件留给主会话；worker 的危险命令由收尾扫描检测 |
| 任务说明模板，缺字段不派发，依赖单元的报告贴给下游 | `orchestrate.md` "The brief" | 照搬并精简 | |
| 每个分支一个写入者，worker 不 rebase、不推送 | `orchestrate.md`、`autopilot-full.md` 第 3 步 | 照搬 | |
| 滚动窗口，完成一个补一个 | `orchestrate.md` 第 4 步 | 照搬 | 同时最多 3 路 |
| 试点 | `orchestrate.md` 第 3 步 | **按其收拢规则不做** | orchestrate 第 1 步：一个 agent 在预算内能做完的工作，收拢成直接做，不要存储、登记表、试点。dflow 的规模属于这一档 |
| 验证按单元缩放；一条命令的由 worker 跑、协调者抽查 | `orchestrate.md` "Verification" | 改动 | worktree 里没有被忽略的文件（依赖、缓存、`.dflow/` 下的检查脚本），所以 worker 只跑仓库里已跟踪的检查；完整检查由主会话在落地后跑 |
| 冲突合并是任务，交给 worker 处理 | `orchestrate.md` "Roles" | **改动** | 冲突时放弃这次落地，把单元基于新 HEAD 重新派发；不在主会话里手工解冲突 |
| 失败按类型重试，两次后放弃并重新规划；不续接旧 agent | `orchestrate.md` "Liveness and failure" | 照搬 | |
| 约 70% 预算时停止派发，只落地已验证的 | `orchestrate.md` 第 1 步 | 照搬 | 用于无人值守的截止时间 |
| worktree 清理：只删干净且已合并的，有未提交工作的先问 | `worktree-cleanup.md` | 照搬规则 | |
| 状态存储 CLI（units、ledger、inbox、gates、frontier，约 2800 行） | `scripts/orch/` | 不搬 | 一张单元表加现有决策日志 |
| 云端 worker、子协调者、gt 堆栈、自动合并、多天程序 | 多处 | 不做 | 超出规模；推送和合并要先问 |

## 3. 方案

### 3.1 吞吐检查与建议

在实施剧本"先定结构"之后、写代码之前，以及无人值守框定时，agent 写出四项：

1. **必须先做的步骤**：其他单元依赖的接口、类型、共享配置。它们先按顺序做完并落地。
2. **独立单元**：每个单元列出写入路径（glob），两两不相交，且不依赖彼此尚未落地的代码。
3. **共享状态**：多个单元都要改的文件（README、注册表、`__init__`、共同的测试入口）。从单元里拿出来，留给主会话在全部落地后统一改。
4. **结论**：
   - 可以并行时写"并行：可拆 N 路（单元 …），预计多花约 X、墙钟约省 Y（暂定估算）。说'并行'即可启用"，然后**按顺序开始做**，不等回复；
   - 不适合时写"并行：不适合，<原因>"。

**建议条件**（暂定，验收 P8 出数据后再调）：至少 2 个独立单元；每个单元预计改动 50 行以上，或者检查要跑 2 分钟以上；`parallel.sh overlap` 确认写入路径互不相交。

### 3.2 启用与授权

- **实施（用户在场）**：用户在请求里说"并行"，或者看到建议后回复"并行"，才启用。没说就按顺序做。
- **无人值守**：框定里给出吞吐检查和"顺序 / 并行"两种安排及代价，默认顺序；用户回复"开始，并行"才启用。
- 用户的这句话就是建 worktree 的明确授权（全局规则要求的"明确要求"），所以**不改** `~/.codex/AGENTS.md`。
- 授权范围只限 `parallel.sh` 创建和清理的 worktree 与分支。SKILL.md 的"先问"清单、无人值守的"不会做"清单、`timeline.py` 的危险命令扫描，都为这两个子命令加同一条例外，其他 worktree、分支、cherry-pick 操作照旧。

### 3.3 运行流程

1. **准备**：
   - 用 `git rev-parse --git-path info/exclude` 找到 exclude 文件（在链接 worktree 里也正确），确认有 `.claude/worktrees/` 一行；
   - 主目录必须干净（`git status --porcelain --untracked-files=all` 除 `.dflow/` 外为空）。用户在场时如果有未提交改动，列出文件，说明并行需要干净的工作区，改按顺序做；
   - 写单元表 `.dflow/<slug>.units.tsv`（用点号，避开 `.dflow/<slug>-<name>` 这个受保护检查脚本的命名），列为 `id deps paths state base agent branch dispatched_at tries landed`，只由主会话写。
2. **派发**：每个依赖都已落地的单元就是"就绪"单元。为它写任务说明（`references/unit-brief.md`），在单元表记下 `base`（当前 HEAD）和状态 `dispatched`，然后在一条消息里启动后台子 agent（`isolation: "worktree"`，`run_in_background: true`，模型 `sonnet`）。同时最多 3 路，完成一个补一个。
3. **处理完成通知**（每到一个处理一个）：
   1. 读 worker 报告：分支、HEAD、跑过的检查和输出、偏差。单元表记 `agent`（子 agent id）和 `branch`。
   2. `parallel.sh scope <slug> <id>`：分支相对 `base` 的改动只能在这个单元声明的路径内。越界就退回。
   3. `parallel.sh land <slug> <id>`：先确认工作区干净、`base` 是分支的祖先；再把 `base..branch` 的改动压成工作区里的未提交改动（`git cherry-pick -n`）。冲突时 `git cherry-pick --abort`（开始时工作区是干净的，所以不会丢别人的改动），报告冲突文件，以 1 退出。
   4. 主会话在主目录跑这个单元的检查，加上所有已完成阶段的条件，以及受保护的检查。通过就只 `git add` 单元路径，提交**一个**提交（提交信息写单元名），单元表记 `landed <sha>`，决策日志记一行，证据是这个 SHA；不通过就 `parallel.sh unland <slug> <id>`（恢复单元路径的暂存区和工作区，删除本次新增的文件），单元退回。
   5. 冲突或退回：`tries` 加 1，用新的子 agent、基于新 HEAD 重做，任务说明附上失败原因。第二次仍失败，就改由主会话按顺序做（在一步内改完并提交，期间到达的完成通知排队，提交后再处理），或标为死路。
   6. **超时**：派发后超过任务说明时限的 2 倍仍没有完成通知，就按接手规则判断该单元（分支有提交就落地；没有就退回；有未提交改动就保留并报告），并计入 `tries`。
4. **共享文件**：所有单元落地后，主会话统一修改共享文件，作为普通单元提交。
5. **清理**：`parallel.sh cleanup <slug>`：
   - 已落地单元：先用 `git status --porcelain --untracked-files=all` 列出 worktree 里剩下的文件并写进输出，再 `git worktree remove --force`、`git branch -D`；
   - 未落地但有提交的：保留，报告分支名；
   - 有未提交的已跟踪改动的：保留，报告文件，不删除；
   - 只处理单元表里登记的 worktree，不碰其他 worktree。
6. **收尾**：照常走影响面、决策日志对照和 codex 审查。时间线和危险命令扫描包括所有子 agent 的对话记录。回复加一行"并行：N 路，落地 X 个单元，退回 Y 次，保留的 worktree：…"。

### 3.4 任务说明模板（`references/unit-brief.md`）

照 orchestrate 的 brief，按单元大小缩放，缺字段就不派发：

```
目标     一句话，不看对话也能执行
范围     只能改的路径；不能改的路径；当前目录就是你的 worktree，只在这里提交
上下文   相关文件；依赖单元的报告原文（你看不到其他单元）
验收     能判对错的条件，每行一条
验证     只跑仓库里已跟踪的检查命令；跑不了的写明原因，不要假装跑过
时限     大约多久；到时交回已有结果
禁止     push、rebase、merge、reset、stash、切换分支、改范围外文件、改受保护路径
报告     状态、分支、HEAD、实际跑过的命令和输出、偏差、建议的后续
规则     提交信息格式 <type>(<scope>): <subject>；只提交通过检查的改动
```

### 3.5 和无人值守的关系

- **任何一次唤醒**（完成通知或 `/loop`）都按 Round 执行，第 1 步先跑 `run-state.sh check`，非 0 就不落地。
- 一轮可以派出多个后台子 agent，然后结束本轮。子 agent 完成时会唤醒会话（已实测）；动态 `/loop` 另外保留一个较长的兜底唤醒。
- 有子 agent 在跑时，由 `/loop` 唤醒的轮次只处理已到的完成通知，不派发新单元，避免超过 3 路的上限。
- "每轮结束工作区必须干净"仍成立：worker 在自己的 worktree 里改；主目录的未提交改动只在落地那一步短暂存在，同一步内提交或还原。
- 每个单元一个提交，所以 `run-state.sh check` 的"最多一个未记录提交"规则不变：落地提交后、写日志前中断，接手时按现有规则补记。
- 截止时间用掉约 70% 时停止派发，只落地已完成的单元。收尾前等待或停止仍在跑的子 agent，再清理。
- **接手**（新会话）时，按单元表里 `dispatched` 的单元的实际情况处理：
  - 分支有提交：按第 3 步落地；
  - 没有提交：重新派发；
  - 有未提交改动：保留并报告，不删除。

  会话被杀时本地子 agent 是否一起结束，实施第 0 步实测后写进规则；实测前的默认是：接手时把 `dispatched` 的单元视为可能仍在运行，等满 1 倍时限再按上面三种情况判断。

### 3.6 新增脚本 `scripts/parallel.sh`

| 子命令 | 作用 |
|---|---|
| `overlap <slug>` | 读单元表，检查写入路径两两不相交（把 glob 展开到当前已跟踪文件，并比较 glob 前缀），且都在清单 `allow` 内、与 `protect` 不相交；不满足就列出并以 1 退出 |
| `scope <slug> <id>` | 先确认 `base` 是分支的祖先；再检查分支相对 `base` 的改动都在声明路径内；不满足就列出并以 1 退出 |
| `land <slug> <id>` | 工作区不干净或 `base` 不是祖先就以 1 退出；否则 `git cherry-pick -n <base>..<branch>`；冲突时 `--abort`，列出冲突文件，以 1 退出 |
| `unland <slug> <id>` | 恢复单元路径的暂存区和工作区，删除本次落地新增的文件 |
| `cleanup <slug>` | 按 3.3 第 5 步处理单元表里登记的 worktree 和分支，输出每个的处理结果 |

测试 `parallel-test.sh` 覆盖：不相交、相交、越出 `allow` 或碰到 `protect`、越界、`base` 不是祖先、干净落地、工作区不干净时拒绝落地、冲突后工作区恢复干净、`unland` 删除新增文件、清理时保留有未提交改动的 worktree 并列出未跟踪文件、已落地单元的分支用 `-D` 删除、只处理登记过的 worktree。

`timeline.py` 改两处：
- 传入会话 id 时，同时读取该会话 `subagents/` 下的所有对话记录；
- 先从命令中删去 `parallel.sh land|cleanup <参数>` 这一段，再扫描剩下的部分，所以 `parallel.sh land x 1 && git push` 仍会被标危险（测试覆盖）；
- 子 agent 记录的来源列用文件名里的 `agent-<id>`，不用会话 id。

## 4. 实施步骤

0. **实测**：
   - 在 tmux 交互会话里杀掉会话，看后台子 agent 是否随之结束；
   - 在链接 worktree（例如 `devflow-dflow`）里派子 agent，看它的 worktree 建在哪里、从哪个 HEAD 拉出。

   结果写进 `references/parallel.md`。
1. `parallel.sh` 和测试；`timeline.py` 的两处修改和测试。
2. `references/parallel.md`、`references/unit-brief.md`。
3. 修改 `build.md`、`unattended.md`、`SKILL.md`（吞吐检查、启用方式、例外条款）。
4. 验收（第 6 节）。

## 5. 文件变更

| 操作 | 路径 |
|---|---|
| 新增 | `skills/dflow/references/parallel.md`、`references/unit-brief.md` |
| 新增 | `skills/dflow/scripts/parallel.sh`、`parallel-test.sh` |
| 修改 | `skills/dflow/scripts/timeline.py`、`timeline-test.sh`：读取子 agent 记录；`parallel.sh` 的例外 |
| 修改 | `skills/dflow/playbooks/build.md`：吞吐检查与建议；用户说"并行"时按 `references/parallel.md` 执行；回复加"并行"一行 |
| 修改 | `skills/dflow/playbooks/unattended.md`：框定给出顺序和并行两种安排；"不会做"清单加 `parallel.sh` 例外；任何唤醒都按 Round 执行；接手规则；"开始"第 2 步改用 `git rev-parse --git-path info/exclude` |
| 修改 | `skills/dflow/SKILL.md`：路由触发语加"并行"；"先问"清单加 `parallel.sh` 例外；子 agent 规则写明并行实施；Codex 宿主里说"并行"时回复不支持并按顺序做 |

## 6. 验收

演示仓库新建一个方案，包含：1 个必须先做的接口单元；3 个互不相交的独立单元；1 个依赖其中两个的单元；1 个共享文件（README）。

- **P1 吞吐检查与建议**：
  - 不说"并行"时，回复里有四项检查和"可拆 N 路，说'并行'即可启用"，并按顺序完成；
  - 另用一个小方案（两个十行的单元），结论是"不适合"。
- **P2 并行执行**：说"按方案并行实施"。接口单元先落地；独立单元在同一条消息里以多个后台 Agent 调用派发；依赖单元在两个上游落地后才派发。
- **P3 落地与集成验证**：工作分支上每个单元恰好一个提交，顺序符合依赖；每次落地后都在主目录跑了完整检查；README 最后统一修改。
- **P4 冲突**：在脚本测试里构造冲突（两个分支改同一行）。另在演示中构造一个真实场景：下游单元基于旧 HEAD 派发后，主会话落地了一个改到同一文件的共享修改。冲突时工作区恢复干净，单元基于新 HEAD 重新派发后成功落地。
- **P5 越界**：一个改了声明路径以外文件的单元被 `scope` 拦下并退回。
- **P6 清理**：结束后 `git worktree list` 只剩主目录；本次的 `worktree-agent-*` 分支都已删除；预置一个有未提交改动的登记 worktree，它被保留并报告；未登记的 worktree 不受影响。
- **P7 危险命令覆盖子 agent**：在一个单元的任务说明里故意不写禁止 `git stash`，并诱导它使用；收尾扫描在子 agent 记录里标出这条命令。
- **P8 无人值守并行**：在 tmux 交互会话里用"开始，并行"跑同一个方案；中途杀掉会话，接手时正确处理 `dispatched` 的单元，不重复落地。
- **P9 成本对比**：同一方案顺序做一次、并行做一次，记录墙钟时间和费用，据此修正 3.1 的暂定门槛。

## 7. 不做

- 自动合并、推送、开 PR（autopilot-full）。
- orchestrate 的多天程序、子协调者、云端 worker、状态存储 CLI、试点流程。
- 在主会话里手工解决合并冲突。
- Codex 宿主里的并行。
- 修改 `~/.codex/AGENTS.md`：用户说"并行"本身就是授权。

## 8. 风险

- **成本**：并行是花钱换时间，每个子 agent 都要重新熟悉代码。所以默认不启用，只给建议，由用户选择。
- **路径不相交不等于语义不冲突**：缓解办法是每次落地后在主目录重跑所有已完成条件，倒退就还原并退回该单元。
- **worktree 里检查不完整**：缺依赖、缓存和不提交的检查脚本。worker 的检查只算初筛，证据以主会话落地后的检查为准。
- **Claude Code 的 worktree 行为可能随版本变化**：目录、分支名、自动清理、子 agent 记录位置都是实测得到的。`parallel.sh` 从单元表和 `git worktree list` 读取实际路径，不写死目录名；版本变化后，第 0 步的实测要重做。
- **磁盘和首次构建**：每个 worktree 是一份完整工作目录，大仓库（例如 ludus 的 node_modules、Godot 导入缓存）会占空间，首次构建也慢。框定里写明，并发上限 3 路。

## 9. codex 评审处理（第 1 版）

结论"修改后执行"：3 条 P0、5 条 P1、5 条 P2。

| 意见 | 处理 |
|---|---|
| P0 无人值守禁令和危险命令扫描与并行冲突 | 采纳：`parallel.sh land`、`cleanup` 在三处统一作为例外（3.2、3.6） |
| P0 一个单元多个提交，打破"最多一个未记录提交" | 采纳：每个单元 `cherry-pick -n` 后只提交一个；失败就还原路径，不用 revert |
| P0 worker 的禁令没有检测 | 采纳：已实测子 agent 记录位置，`timeline.py` 一并扫描；增加 P7 |
| P1 "照搬"与 pstack 原文不符 | 采纳：表格如实标为"改动"或"按收拢规则不做"；去掉试点 |
| P1 花钱换时间，与成本规则冲突 | 采纳：默认不启用，只给建议和预计代价，用户说"并行"才启用；门槛标为暂定 |
| P1 worktree 里跑不了完整检查 | 采纳：worker 只跑已跟踪的检查，完整检查由主会话落地后跑 |
| P1 P4 按规则造不出来 | 采纳：改为脚本测试加"下游基于旧 HEAD"的真实场景 |
| P1 唤醒和会话被杀未实测 | 部分采纳：唤醒已实测；会话被杀放到实施第 0 步 |
| P2 链接 worktree 的 exclude 路径 | 采纳：用 `git rev-parse --git-path`；第 0 步实测链接 worktree |
| P2 清理时 `-d` 删不掉 cherry-pick 过的分支 | 采纳：以单元表的 `landed` 为准，用 `-D`，`worktree remove --force` 只在没有未提交已跟踪改动时 |
| P2 基线靠可选参数 | 采纳：派发时记进单元表 |
| P2 截止时间附近 | 采纳：约 70% 停止派发 |
| P2 Claude Code 是否读 `~/.codex/AGENTS.md` | 不再适用：不改该文件。另外 `~/.claude/CLAUDE.md` 第一行引用了它 |
| 更简单方案 A：同目录并行、不建 worktree | 不采纳：多个单元在同一目录同时跑检查会互相干扰，各单元也看到彼此的半成品 |
| 更简单方案 B：整个方案交给一个子 agent | 不采纳：只有隔离，没有并行，达不到目的 |
| 更简单方案 C：每单元一个提交 | 采纳，即 P0 第 2 条的处理 |

## 10. codex 评审处理（第 2 版）

结论"修改后执行"：1 条 P0、5 条 P1、5 条 P2，没有方向性问题。按"最多两轮"不再做第三轮，全部采纳：

| 意见 | 处理 |
|---|---|
| P0 落地失败时恢复工作区可能清掉用户改动；`cherry-pick -n` 会混入用户已暂存的内容 | 并行要求主目录干净；`land` 开头检查；冲突用 `--abort`；提交只 `git add` 单元路径；测试覆盖 |
| P1 危险命令例外可被 `&& git push` 绕过 | 先删去例外片段再扫描，测试覆盖 |
| P1 单元表名撞上受保护检查脚本的命名 | 改名 `.dflow/<slug>.units.tsv` |
| P1 `base` 不是分支祖先时会带进无关历史 | `scope`、`land` 开头检查祖先关系 |
| P1 worker 死掉时单元永远停在已派发 | 记派发时间，超过 2 倍时限按接手规则判断，计入重试 |
| P1 完成通知唤醒的轮次是否先跑检查 | 任何唤醒都按 Round 执行，先跑 `check` |
| P2 `worktree remove --force` 静默删未跟踪文件 | 删除前列出 |
| P2 还原没有脚本 | 新增 `unland` |
| P2 单元路径没对照 `allow`、`protect` | `overlap` 一并检查 |
| P2 主会话按顺序补做和落地抢主目录 | 一步内改完并提交，期间的通知排队 |
| P2 其他遗漏（exclude 路径、子 agent 来源标记、Codex 宿主、会话被杀前的默认） | 都写进对应位置 |
