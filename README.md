# devflow

个人开发流程 Skill。主入口是 `dflow`，在 Claude Code 和 Codex 里都能用（Codex 侧的对应做法见 `plugins/dflow/skills/dflow/references/hosts.md`）。

| Skill | 用途 | 软链接位置 |
|---|---|---|
| dflow | 唯一入口：按目标选流程（调研、排查、方案、审查、实施、验收、影响面、原型、去 AI 腔、无人值守、交接、进展、复盘、报告、发布、调优），可撤销的步骤不停下等人，收尾给证据。只在点名时启用 | ~/.agents/skills、~/.claude/skills |
| dflow-report | 报告 | ~/.codex/skills、~/.claude/skills |
| retro | 复盘的直达入口，只做插件入口 | 不链接（全局名 `retro` 太泛） |

`archive/devflow-*` 是已下线的旧流程，源码留作参考，`install.sh` 不链接它们，`test.sh` 也不跑它们的测试。

## 调用

| 宿主 | 主入口 | 复盘直达 |
|---|---|---|
| Claude Code，软链接 | `/dflow` | `/dflow retro` |
| Claude Code，插件 | `/dflow:dflow`（没有别的 `/dflow` 时也可直接 `/dflow`） | `/dflow:retro`（或 `/dflow:dflow retro`） |
| Codex，软链接 | `$dflow` | `$dflow retro` |
| Codex，插件 | `$dflow:dflow` | `$dflow:retro` |

点名直达：入口后的第一个词恰好是流程的中文名或 id（见 `plugins/dflow/skills/dflow/SKILL.md` 流程表），就直接用那个流程，例如 `/dflow retro alpha`、`/dflow 复盘 全部`、`/dflow debug 登录页白屏`。只看第一个词；不是流程名时照常匹配。

复盘的参数：slug 只审那一份；`全部` 审过去一天写过的每份日志；不给参数审最新一份，过去一天有多份时先列汇总表。

## 安装

两种方式选一种，不要同时启用。实测同时存在时：Claude Code 里软链接的 `dflow`、`dflow-report` 会遮住插件里的同一份，`/dflow:dflow` 不出现；Codex 里同一技能列出两份。

### 软链接（开发期推荐）

```sh
./install.sh          # 建立符号链接；已存在的实体目录或指向别处的链接只报告，不覆盖
./install.sh --check  # 只检查
```

各工具目录里是指向本仓库的符号链接，改完即生效。

### 插件

插件在 `plugins/dflow/`，仓库根目录带有两边的本地 marketplace（名字都是 `devflow`）。根目录的 `skills` 是指向 `plugins/dflow/skills` 的兼容链接，供仍在用旧路径的会话使用。

```sh
# Claude Code
claude plugin marketplace add /path/to/devflow
claude plugin install dflow@devflow

# Codex
codex plugin marketplace add /path/to/devflow
codex plugin add dflow@devflow
```

改动如何生效：

- Claude Code：从本地路径加的 marketplace 直接读源目录，不复制；`claude --plugin-dir /path/to/devflow/plugins/dflow` 也是。改完在会话里 `/reload-plugins` 或开新会话。
- Codex：安装时把 `plugins/dflow/` 复制到 `~/.codex/plugins/cache/devflow/dflow/local/`，之后的改动要重新安装才生效。开发期继续用 `install.sh` 软链接。

撤销：`claude plugin uninstall dflow@devflow` 和 `claude plugin marketplace remove devflow`；`codex plugin remove dflow@devflow` 和 `codex plugin marketplace remove devflow`。

## 测试

```sh
./test.sh   # 运行 plugins/dflow/skills/*/scripts/*-test.sh
```

修改 `scripts/` 下任何脚本后必须运行。

## 注意

- 有无人值守运行正在进行（任何项目里存在 `.dflow/<slug>.lock/`）时，不要修改本仓库：脚本是实时读取的。
- 提交信息：`<type>(<scope>): <subject>`，不超过 72 字符。
