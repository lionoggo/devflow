# devflow

个人开发流程插件 `dflow`，在 Claude Code 和 Codex 里都以插件安装（Codex 侧的对应做法见 `plugins/dflow/skills/dflow/references/hosts.md`）。

| Skill | 用途 |
|---|---|
| dflow | 唯一入口：按目标选流程（讲解、调研、排查、方案、评审、实施、验收、无人值守、交接、进展、复盘、周报、提交与发布、调优、影响面、原型、润色），可撤销的步骤不停下等人，收尾给证据。只在点名时启用 |
| retro | 复盘的直达入口 |
| report | 周报：按 Git 记录汇总个人工作进展，也是 dflow 周报流程的实现 |

`archive/devflow-*` 是已下线的旧流程，源码留作参考，`test.sh` 不跑它们的测试。

## 调用

| 宿主 | 主入口 | 复盘直达 | 周报直达 |
|---|---|---|---|
| Claude Code | `/dflow:dflow`（没有别的 `/dflow` 时也可直接 `/dflow`） | `/dflow:retro` | `/dflow:report` |
| Codex | `$dflow:dflow` | `$dflow:retro` | `$dflow:report` |

点名直达：入口后的第一个词恰好是流程的中文名或 id（见 `plugins/dflow/skills/dflow/SKILL.md` 流程表），就直接用那个流程，例如 `/dflow retro alpha`、`/dflow 复盘 全部`、`/dflow debug 登录页白屏`。只看第一个词；不是流程名时照常匹配。

复盘的参数：slug 只审那一份；`全部` 审过去一天写过的每份日志；不给参数审最新一份，过去一天有多份时先列汇总表。

## 安装

插件在 `plugins/dflow/`，仓库根目录带有两边的本地 marketplace（名字都是 `devflow`）。根目录的 `skills` 是指向 `plugins/dflow/skills` 的兼容链接，供仍在用旧路径的会话使用。

```sh
# Claude Code
claude plugin marketplace add /path/to/devflow
claude plugin install dflow@devflow

# Codex
codex plugin marketplace add /path/to/devflow
codex plugin add dflow@devflow
```

不要再在 `~/.claude/skills`、`~/.agents/skills`、`~/.codex/skills` 里放同名技能的软链接：Claude Code 里它会遮住插件里的同一份，Codex 里同一技能会列出两份。

改动如何生效：

- Claude Code：从本地路径加的 marketplace 直接读源目录，不复制；`claude --plugin-dir /path/to/devflow/plugins/dflow` 也是。改完在会话里 `/reload-plugins` 或开新会话。
- Codex：安装时把 `plugins/dflow/` 复制到 `~/.codex/plugins/cache/devflow/dflow/local/`，改完要重新执行 `codex plugin add dflow@devflow` 再开新会话。

撤销：`claude plugin uninstall dflow@devflow` 和 `claude plugin marketplace remove devflow`；`codex plugin remove dflow@devflow` 和 `codex plugin marketplace remove devflow`。

## 测试

```sh
./test.sh   # 运行 plugins/dflow/skills/*/scripts/*-test.sh
```

修改 `scripts/` 下任何脚本后必须运行。

## 注意

- 有无人值守运行正在进行（任何项目里存在 `.dflow/<slug>.lock/`）时，不要修改本仓库：Claude Code 的插件是实时读取源目录的。
- 提交信息：`<type>(<scope>): <subject>`，不超过 72 字符。
