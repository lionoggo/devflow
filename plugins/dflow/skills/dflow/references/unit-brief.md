# 单元任务说明 (unit brief)

One brief per unit; a field you cannot fill means the unit is not scoped yet,
so do not dispatch it. Scale it to the unit: a one-command unit collapses to
a paragraph that still names goal, scope, verify, and report; its first
line is still the marker. From pstack `orchestrate` "The brief". The first
line marks line mode (`SKILL.md`); in 并行, `<attempt>` is `tries`+1. 常驻
and 回执 are for 多线 (`playbooks/lines.md`); 并行 leaves them out.

```text
dflow 线 <slug>/<id>/<attempt>
目标     <一句话，不看对话也能执行>
准备     （Claude Code 的 worktree 子 agent；Codex 换成"工作目录 <path>：每条命令都在这里运行，只在这里提交"）
         先运行 git branch --show-current 得到分支名，再运行 git switch -C <这个分支名> <base>，
         分支名照抄输出的字面值，不要用变量或 $(...)（收尾扫描只认字面分支名）
         （新 worktree 从仓库默认分支拉出，不一定是 base；这一步把它对齐到 base，分支名不变；只在还没有任何改动时做）
范围     只能改：<globs>；不能改：<受保护路径和其他单元的路径>；当前目录就是你的 worktree，只在这里提交
上下文   <相关文件>；<依赖单元的报告原文>（你看不到其他单元）
验收     <能判对错的条件，每行一条>
验证     <只跑仓库里已跟踪的检查命令>；跑不了的写明原因，不要假装跑过
时限     约 <n> 分钟；到时交回已有结果
禁止     push、rebase、merge、reset（准备那一步除外）、stash、改其他分支、改范围外文件、改受保护路径
报告     状态、分支、HEAD、实际跑过的命令和输出、偏差、建议的后续；
         决策行：本单元里的分叉、换思路、放弃的做法，每行六列
         （ts phase decision why evidence result），证据指向提交或 path:line
常驻     <.dflow/<slug>/standing.md 原文，整段粘贴>
回执     最后写 <主仓库绝对路径>/.dflow/<slug>/reports/<id>-<attempt>.md，第一行固定为
         RECEIPT <id> <attempt> <done|partial|blocked> <提交号|只读产物路径>
         下面写报告的内容；写完回执后不再改任何文件
规则     按线模式执行：只做本说明，不重新匹配流程，不交接，不开无人值守，不切分支（准备那一步除外），
         不加载其他流程类 skill（如 devflow-*）；
         提交信息 <type>(<scope>): <subject>，不超过 72 字符；只提交通过检查的改动；
         新写的测试要调用被测代码并断言用户看到的确切结果：把被测行为改坏（返回错值、跳过或重复副作用）后
         仍能通过的测试不算覆盖验收项；只改内部、结果不变时会失败的测试也要改写
```
