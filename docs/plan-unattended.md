# 方案：无人值守改为 pstack 方式，并入 devflow-impl

> 状态：待用户批准。日期 2026-10-14。仓库 devflow `main` a471776。
> 取代：`docs/plan-progress-view.md`、`docs/plan-autorun-simplify.md` 中关于 autorun 的设计（第 3 阶段完成后生效）。
> 来源：pstack（cursor/plugins，v0.15.23）的 `poteto-mode/playbooks/autonomous-run.md`、`show-me-your-work/SKILL.md`、`docs/guide/07-overnight.md`。
> 用户已确认：保留 devflow 主体；无人值守照搬 pstack；接受"靠提示词约束"；先试后删。
> 冻结：写作时 ludus 的 `p1-bench-r5` 正在运行。它结束前，除本文件外不改 devflow 仓库。

## 1. 结论

保留 devflow 的 plan、impl、verify、debug、commit、research、report。把 pstack 的无人值守做法几乎原样搬进 devflow-impl，替换掉自造的 autorun 机制（两个技能、守卫、检查脚本、启动脚本、契约和标记文件）。

用户的使用方式变成：在普通会话里说一句"我要离开，跑到 <完成条件> 为止"，看一屏框定，回复"开始"。回来时看结果、决策日志和另一个模型挑出的审查要点。

## 2. 背景

### 2.1 pstack 的工作流程

- **一个入口**：所有任务都从 `/poteto-mode` 进。用户只说目标，最多再加四样：能判对错的完成条件、想看的证据、已知线索、硬约束（如"先复现""先别改代码"）。它从 23 个剧本里匹配一个，把步骤原样抄进 todo 列表；跳过的步骤留在列表里，写明 `skip: 原因`。匹配不上就用 `figure-it-out` 现场设计一套。
- **离开时只加一句话**：没有启动仪式。过夜合同就是四行提示：

  ```
  /poteto-mode im going to bed. <在新 worktree 里做什么>.
  done means <能判对错的条件>.
  keep a decision log. don't ask me before committing.
  /loop until done. if you're truly stuck after a few hours, stop and write up why.
  ```

  "going to bed"让它不再提问；"done means"给出每轮都能检查的条件；"worktree"负责隔离；"don't ask before committing"提前授权；`/loop` 负责唤醒；最后一句是逃生口。
- **每轮的纪律**（autonomous-run）：只做证据支持的最小改动，对照完成条件验证，有进展就提交，没进展就丢弃；每轮记一行日志。瓶颈期不算停止理由，要换思路；真正走投无路才停下并写明原因；绝不放宽完成条件。可撤销的事自己做，不把问题停给人。只有不可逆的操作、实验无法回答的产品或偏好问题、真正的死路，才交给人。
- **只有人能做的决定**：在完全授权下，先按默认做，详细报告，并用大白话说明对方可以怎么改。
- **早上验收**（show-me-your-work）：
  - 日志只追加，每行写 时间、阶段、决定、理由、证据指针、结果。
  - 结束前对照对话记录核对日志，补上漏记的分叉，用新行更正错误。
  - 交给另一个模型家族审查日志和对话记录，回复末尾加"Attention"段，第一行写审查模型。
- **规模变大才上重型机器**：Autopilot-full/stack（一队 PR）、Orchestrate（跨多天，`orch.ts` 记账）、多阶段计划（`check-plan.mjs` 校验结构）。文档明说 Orchestrate 是"刻意的重型方案"。
- **安全**：提示词里的授权规则（可撤销的直接做；强推共享分支、部署、删数据、对外发消息必须停下），加上 worktree 或云端 VM 隔离，再加上"先赢得信任再开循环"。没有结构性守卫。
- **脚本只用在机械记账上**：`check-plan.mjs`、`orch.ts`、`watch-pr`，都是"一条命令进、一行结果出"，判断留给提示词。

### 2.2 devflow autorun 的实际效果（ludus，10/12–10/14）

| 契约 | 运行次数 | 结果 |
|---|---|---|
| p0、p1-core | 各 1 | 完成（各约 15 分钟） |
| p1-web | 2 | 跑满轮数上限 → 完成 |
| p1-godot | 3 | 部分完成 → 受阻（等用户决定）→ 完成 |
| p1-bench | 5（第 5 次写作时在跑） | 受阻 → 受阻 → 部分完成 → 部分完成 → … |

- **起作用的**：能判对错的完成条件，加上提交或撤销（p1-bench 四次都没有谎报完成）；决策日志；遇到只有用户能做的决定就停下。pstack 都有。
- **守卫**：12 次运行的日志里，没有一次记录它拦下过违规。
- **启动仪式本身出错**：p1-godot、p1-bench-r5 都先手写了 start 行和标记，事后才发现守卫当时没生效，只好重来。
- **卡住就收尾**：用户要做决定、重新起草契约、重新启动。p1-bench 因此有 5 份契约，每次只跑 15–90 分钟，用户约每小时回来一次。
- **进展页**：A6 实测看不懂、状态显示错误，已在 1863760 删除。

### 2.3 为什么不整体采用 pstack

1. **为 Cursor 写的**：用 `/add-plugin` 安装，只有 `.cursor-plugin/plugin.json`。每个技能都读 `~/.cursor/rules/pstack-models.mdc`，依赖 Custom Mode、`poteto-agent` 子 agent 类型、云端子 agent，以及 `cursor-team-kit` 的 `deslop`、`control-ui`、`control-cli`。SKILL.md 格式通用，但这些依赖都要改。
2. **与用户规则冲突**：pstack 可撤销的事直接做；每个剧本最后开 PR（正式 PR，不是草稿）；babysit 一路推到合并。用户规则是提交、推送前先确认，并用中文回复。
3. **成本高**：53 个技能；新功能剧本强制做设计竞赛，验证 10 路并行，还有多模型对抗审查。用户的 CLAUDE.md 要求只有能实质降低总成本时才用子 agent。
4. **devflow 其余技能已按用户规则调好**，问题只出在 autorun。

无人值守那部分只是提示词，与 Cursor 无关，`/loop` 两边都有，所以直接搬。

### 2.4 Claude Code 自带 deny 规则的实测

环境：Claude Code 2.1.299，`--permission-mode bypassPermissions`，临时仓库加本地裸远端（`scratchpad/denytest`）。规则：

```json
{"permissions":{"deny":["Bash(git push*)","Bash(git -C * push*)","Bash(* git push*)","Bash(bash -c*)","Bash(sh -c*)","Edit(tests/**)"]}}
```

| 写法 | 结果 |
|---|---|
| `git push origin main`、`cd . && git push …` | 拦住 |
| `git -C . push …`、`bash -c '…'`、`sh -c '…'`、`env git push …`、`GIT_DIR=.git git push …` | 拦住 |
| `/usr/bin/git push origin main` | **没拦住，实际推送成功** |
| `git --git-dir=.git push …`、`zsh -c '…'` | **没拦住** |
| Write、Edit 写 `tests/t.txt`；`echo x > tests/t.txt`、`tee`、`cp` | 拦住 |

写法上有两个坑：`Bash(git -C * push:*)` 这种写法里的 `*` 不展开；`Write(...)` 规则不生效，只认 `Edit(...)`。

结论：deny 规则能拦住常见写法，但有绕过方式，补规则是打地鼠。本方案不采用（决定 9）。

## 3. 计划

**目标**：在普通会话里说一句"我要离开，跑到 <完成条件> 为止"，看一屏框定、回复"开始"之后，Claude 自己循环推进，直到完成或真正走投无路；用户回来时看到结果、决策日志和另一个模型的审查要点。确认可行后删掉 autorun 整套机制。

**非目标**：
- 不搬 pstack 的其他部分：剧本路由、并行竞赛、开 PR、推到合并、云端子 agent、原则名体系；
- 不做进展页，不做结构性守卫或 deny 规则；
- 不改 devflow 的 plan、verify、debug、commit、research、report 的行为。

### 3.1 决定

1. **入口**：devflow-impl 新增 `references/unattended.md`，SKILL.md 里加一行触发：用户说"我要离开 / 去睡了 / 跑到…为止 / 别停 / 无人值守"时读它。不再有单独的 autorun 命令。没有批准过的计划时，完成条件由这一句话加上框定确定，不要求先走 devflow-plan。
2. **框定（用户在场，只停一次）**：一屏写清以下几项，然后停下等"开始"。
   - 完成条件：每条是命令加期望结果，以及现在的基线输出；
   - 分支：工作区干净时，从 HEAD 建本地分支 `auto/<slug>`；不干净就说明是哪些文件并停下，不清理、不暂存；
   - 不会做的事（见决定 4）；
   - 时长上限（默认 8 小时）。

   如果有比当前实现更便宜、却违背意图的做法也能通过完成条件，就补一条能区分两者的条件。

   回复"开始"即授权在该分支本地提交，这一点覆盖 devflow-impl 平时"不提交"的规则。之后：
   - 把 `.devflow/` 写进本地 exclude，写 `start` 行；
   - 用 `caffeinate -i -t <秒>` 防休眠；
   - 用 Skill 工具启动 `loop`（不带间隔，动态模式），参数为 `/devflow-impl 继续无人值守 <slug>`；不可用时请用户自己输入这一行。
3. **每一轮**（照搬 autonomous-run）：
   1. 读日志最后 15 行和完成条件，以文件为准，不信记忆。
   2. 选最小的下一步，风险最高的先做，说出假设。
   3. 改动，然后跑这一步的检查和全部完成条件。
   4. 有进展（某个条件更接近通过，且没有倒退）就 `git add <路径>` 加本地提交，记一行，证据写 `commit <sha>`。没有进展就撤销本轮自己的改动、删掉本轮新建的文件，记一行写明原因和下一步换什么思路。
   5. 停止条件：
      - 全部完成条件通过，进入收尾；
      - 到达时长上限；
      - 连续 3 轮没有进展，且已经换过至少一次思路；
      - 必须做决定 4 里的事才能继续。

      瓶颈期不停。绝不放宽或重新解释完成条件。
4. **不会做的事**（提示词约束）：
   - push、merge、rebase、reset、stash、clean、cherry-pick，切换或删除分支，改 tag，动 worktree；
   - 修改完成条件用到的测试、样本、脚本；
   - 发布或对外发送任何东西。

   需要其中任何一项才能继续，就记一行并停下。
5. **只有用户能做的决定**（产品或偏好问题，实验无法回答）：先按默认做；日志里写明问题、默认值、理由，以及用户可以怎么改；发一次通知；继续推进，不收尾等人。能用实验回答的问题自己做实验，不算这一类。
6. **日志**：
   - 位置 `.devflow/<slug>.tsv`，沿用现有六列 `ts phase decision why evidence result`。`log.sh` 从 devflow-autorun 移到 `devflow-impl/scripts/`。
   - 规则照 show-me-your-work：只追加，错了追加更正行；记决策点，不记每条命令；每轮至少一行；新会话接手时先写 `start` 行，注明接手的时间范围。
   - 日志文字写给人看，用大白话。
7. **通知**：用 PushNotification，只在两个时刻发，各一次：
   - 按默认替用户做了一个决定（"已按默认处理：<问题>，可改为 <选项>"）；
   - 运行结束（"<slug> 完成 / 部分完成 / 受阻"）。

   发送失败不重试，也不记日志。
8. **收尾**：
   1. 工作区里除 `.devflow/` 外有未提交改动，就如实报告，不清理。
   2. 在最终提交上重跑全部完成条件，记录真实输出。
   3. 日志对照 `git log <基线>..HEAD`：每个"有进展"行都对应真实提交；不对就追加更正行。
   4. 写 `close` 行，决定列只写"完成 / 部分完成 / 受阻"之一，说明放在其他列。
   5. 跨模型审查：`codex exec -s read-only --ephemeral -C <仓库>`，输入为日志、`git log -p <基线>..HEAD` 和完成条件；要求它列出证据薄弱的决定、没有证据就声称通过的验证、事后看有风险的选择、粗看容易漏掉的问题。
   6. 停止循环，发通知，回复。

   回复用 devflow-impl 的收尾格式，再加：
   - 按默认做的决定清单，每条写明可以怎么改；
   - 日志路径；
   - 末尾"需要你注意"段，第一行写审查模型。Codex 不可用就写"未审查：<原因>"，不用 Claude 代审。
9. **不加 deny 规则**：实测（2.4）有绕过方式。按用户确认，靠提示词约束。
10. **删除（第 3 阶段，用户确认 E1 后）**：
    - 技能目录 `skills/devflow-autorun`、`skills/devflow-autorun-tick`，包括 guard.sh、check.sh、arm.sh、log.sh（已移走）、三组测试、contract.md；
    - `install.sh` 末尾的守卫检查；对已删技能留下的 `~/.agents/skills`、`~/.claude/skills` 下的链接，先列出给用户，确认后再移除；
    - `README.md` 的 autorun 段落、测试说明、"有 autorun 运行时不改本仓库"的规则；
    - `skills/devflow-plan/references/plan.md` 里"契约拆分表 / 人工项表"一段；
    - 两份旧方案文档开头加"已被 `docs/plan-unattended.md` 取代"。

    `~/.claude/settings.json` 的 `hooks.PreToolUse` 里有一条 `$HOME/.agents/skills/devflow-autorun/scripts/guard.sh`。必须先经用户确认移除这一条，再删 guard.sh；顺序反了，每次 Bash 或编辑调用都会报钩子错误。

### 3.2 用户看到的流程（示例）

```
你：我要去睡了，跑到 python3 -m unittest -q tests.test_greet 通过为止
Claude：（一屏）完成条件 C1 …，现在失败（3 个错误）；
        分支 auto/greet；不会 push、不改 tests/；最长 8 小时。回复"开始"。
你：开始
Claude：已启动循环。
  …第 1 轮：加 greet，错误 3→2，提交 a1b2c3d
  …第 2 轮：问候语用中文还是英文只有你能定；先按英文，通知你"已按默认处理，可改为中文"
  …第 3 轮：加 farewell，C1 通过，提交 d4e5f6a
  …收尾：重跑 C1 通过；日志与 2 个提交一致；Codex 审查；通知"greet 完成"
早上你看到：结果、提交范围、按默认做的决定（可改为中文）、需要你注意（reviewed by codex …）。
```

### 3.3 待决事项

无。

## 4. 验收

- **A1**：新会话里说"我要离开，跑到 `<命令>` 通过为止"，只需再回复一次"开始"，循环就自动启动；全程没有用到契约文件、`.running` 标记、arm.sh。验证：在 a6-demo（重置到 68939cd，删除旧 `.devflow/`）实跑，查看对话记录和 `.devflow/` 目录。
- **A2**：每个"有进展"日志行都对应一个真实提交；没进展的改动被撤销，不留在工作区。验证：对照 demo 的 `git log` 和日志，再看 `git status`。
- **A3**：问候语言问题按默认处理，通知一次，写进日志（含"可以怎么改"），运行一直跑到完成，中途没有停下等人。验证：demo 日志、通知、对话记录。
- **A4**：收尾回复包含完成条件的真实输出、提交范围、按默认做的决定，以及以审查模型开头的"需要你注意"段（或明确写"未审查"）。验证：demo 收尾回复。
- **A5**：运行期间，本地远端和受保护路径都没有变化。验证：demo 加一个本地裸远端，结束后检查远端引用和 `git diff <基线> -- tests/`。这只证明这一次没发生，不证明不会发生。
- **E1**：r5 收尾后，用户在 ludus 用新方式跑一次真实任务。记录是否完成，或是否带着清楚原因停下，以及用户介入的次数，和 2.2 节的 12 次运行对比。由用户判断"不比原来差"，才进入第 3 阶段。
- **A6**（第 3 阶段后）：`skills/`、`README.md`、`install.sh` 里不再出现 autorun、guard、check.sh、arm.sh、`.running`；`./test.sh` 通过；`install.sh --check` 不报守卫缺失；新会话里任意 Bash 调用没有钩子报错。

## 5. 范围

- **新增或修改**：
  - `skills/devflow-impl/SKILL.md`（加一行触发）；
  - `skills/devflow-impl/references/unattended.md`（新增，内容为决定 2–8）；
  - `skills/devflow-impl/scripts/log.sh`（从 autorun 移来）。
- **删除**：见决定 10。
- **其他**：`README.md`、`install.sh`、`skills/devflow-plan/references/plan.md`、两份旧方案文档。
- **仓库外**：
  - 用户的 `~/.claude/settings.json` 只改一处（移除守卫钩子），先确认；
  - 已删技能的链接，先列出再移除。

## 6. 阶段

1. **加新**（r5 收尾后）：只新增，不删 autorun，完成 A1–A5。
2. **试用**：用户在 ludus 发起 E1。
3. **删除**：用户确认 E1 后，先移除钩子，再删除，完成 A6。

## 7. 风险

- **没有结构性守卫**：模型若不守规矩，push 或改测试都不会被拦（2.4 节实测 deny 规则也拦不全）。A5 只能证明一次没发生。
- **动态 `/loop` 由模型自定节奏**：会话被关闭，或休眠超出防休眠时长，循环就停。续跑靠新会话读日志接手（写 `start` 行）。
- **"只有用户能做的决定"可能被滥用**：模型可能把本该停下的事当成"按默认做"继续推进。收尾的跨模型审查和"按默认做的决定清单"用来暴露这一点。
- **第 1、2 阶段期间两套并存**：两套都能用，用户可能混用。第 3 阶段结束这种状态。
