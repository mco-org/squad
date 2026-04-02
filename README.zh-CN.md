<h1 align="center">squad</h1>

<p align="center"><strong>多 AI 智能体终端协作 — 通过简单的 CLI 命令实现。</strong></p>

<p align="center">
  <a href="https://github.com/mco-org/squad/stargazers"><img src="https://img.shields.io/github/stars/mco-org/squad?style=flat-square&color=f59e0b" alt="GitHub stars" /></a>
  <a href="./LICENSE"><img src="https://img.shields.io/badge/License-MIT-22c55e?style=flat-square" alt="License: MIT" /></a>
  <img src="https://img.shields.io/badge/Rust-1.77%2B-orange?style=flat-square&logo=rust&logoColor=white" alt="Rust 1.77+" />
  <img src="https://img.shields.io/badge/Platforms-4%20supported-7c3aed?style=flat-square" alt="4 supported platforms" />
</p>

<p align="center">squad 让多个 AI CLI 工具通过 Shell 命令 + SQLite 进行通信。<br/>无守护进程、无后台进程 — 每条命令都是一次性操作。</p>

<p align="center"><a href="./README.md">English</a> | 简体中文</p>

<table align="center">
  <tr>
    <td align="center"><a href="https://github.com/anthropics/claude-code"><img src="https://github.com/anthropics.png?size=96" alt="Claude Code" width="48" /></a></td>
    <td align="center"><a href="https://github.com/google-gemini/gemini-cli"><img src="https://github.com/google-gemini.png?size=96" alt="Gemini CLI" width="48" /></a></td>
    <td align="center"><a href="https://github.com/openai/codex"><img src="https://github.com/openai.png?size=96" alt="Codex CLI" width="48" /></a></td>
    <td align="center"><a href="https://github.com/sst/opencode"><img src="https://raw.githubusercontent.com/sst/opencode/master/packages/console/app/src/asset/brand/opencode-logo-light-square.svg" alt="OpenCode" width="48" /></a></td>
  </tr>
  <tr>
    <td align="center"><strong>Claude Code</strong></td>
    <td align="center"><strong>Gemini CLI</strong></td>
    <td align="center"><strong>Codex CLI</strong></td>
    <td align="center"><strong>OpenCode</strong></td>
  </tr>
  <tr>
    <td align="center"><code>claude</code></td>
    <td align="center"><code>gemini</code></td>
    <td align="center"><code>codex</code></td>
    <td align="center"><code>opencode</code></td>
  </tr>
</table>

> 一条斜杠命令，多个 Agent 实时协作。
>
> 分配 Manager、启动 Worker、添加 Inspector — 各自在独立终端中运行，通过 SQLite 通信。

---

## 快速开始

## 安装

```bash
# Homebrew (macOS)
brew install mco-org/tap/squad

# Windows（GitHub Releases）
# 1. 下载 squad-x86_64-pc-windows-msvc.zip
# 2. 解压，把 squad.exe 放到类似 C:\Tools\squad 的目录
# 3. 把该目录加入 PATH

# 或从 GitHub Releases 下载其他预编译二进制
# https://github.com/mco-org/squad/releases

# 或从源码编译
cargo install --git https://github.com/mco-org/squad.git
```

## 快速开始

```bash
# 安装 /squad 斜杠命令到已有的 AI 工具
squad setup

# 初始化项目工作区
squad init

# 在任意 AI CLI 终端中使用斜杠命令
/squad manager      # 终端 1
/squad worker       # 终端 2
/squad inspector    # 终端 3
```

就这么简单。每个 Agent 加入后会读取角色指令，然后进入持续检查消息的工作循环。Manager 会分析你的目标并分配任务给 Worker。

## 可选的 tmux 启动器

如果你在类 Unix 环境里使用 Claude Code，这个仓库还带了一个可选辅助脚本：

```bash
scripts/squad-tmux-launch.sh /path/to/project --dry-run
```

它可以：
- 从 `.squad/launcher.yaml` 读取项目级启动配置
- 从 `.squad/run-task.md` 读取本次任务说明
- 或自动发现 `docs/superpowers/...` 下最新的 implementation plan 和匹配 spec
- 或通过 `.squad/launcher.yaml -> task_discovery` 使用自定义发现规则
- 在 `.squad/quickstart/` 下生成 manager / inspector prompt
- 启动平铺布局的 `tmux` 会话，并自动向配置好的 AI CLI pane 注入 `/squad` 命令
- 在启动 agent 前可选地创建独立 git worktree

依赖：
- `tmux`
- `ruby`（用于解析 `launcher.yaml`）
- 你在配置里指定的 AI CLI 命令（例如 `claude`、`codex`、`gemini`、`opencode`）

这个启动器刻意保持在核心 Rust CLI 之外。它是给需要固定化多终端协作流程的用户准备的可选自动化能力。

### Launcher 客户端配置

Launcher 现在支持“通用默认客户端 + 角色级覆盖”：

```yaml
runtime:
  command: codex
  args:
    - --dangerously-bypass-approvals-and-sandbox

  worker_command: claude
  worker_args:
    - --dangerously-skip-permissions
```

上面的配置表示：
- manager pane 默认使用 `codex --dangerously-bypass-approvals-and-sandbox`
- worker pane 使用 `claude --dangerously-skip-permissions`
- inspector pane 如果没有单独覆盖，则继续继承默认的 `codex`

支持的运行时字段：
- `runtime.command` / `runtime.args`：所有 pane 的默认客户端命令
- `runtime.manager_command` / `runtime.manager_args`
- `runtime.worker_command` / `runtime.worker_args`
- `runtime.inspector_command` / `runtime.inspector_args`

为了向后兼容，`runtime.claude_command` 和 `runtime.claude_args` 仍然可用，并会被当作默认客户端配置的旧别名。

### Launcher 任务发现规则

任务输入按下面的优先级解析：

1. `--task-file <path>`
2. `<project>/.squad/run-task.md`
3. 自动发现

默认的自动发现规则会寻找：

- 最新的 `docs/superpowers/plans/????-??-??-*-implementation.md`（文件名需以 `YYYY-MM-DD-` 日期前缀开头）
- 以及同主题、最新匹配的 `docs/superpowers/specs/????-??-??-*-design.md`（同样要求 `YYYY-MM-DD-` 前缀）

如果你的仓库目录或命名规则不同，可以在 `.squad/launcher.yaml` 里配置：

```yaml
task_discovery:
  plan_globs:
    - workitems/plans/*-plan.md
  spec_globs:
    - workitems/specifications/*-spec.md
  plan_suffix: -plan.md
  spec_suffix: -spec.md
```

`plan_globs` 和 `spec_globs` 都是相对于你传入的 `project-dir` 解析的。配置后，launcher 会选出最新的 plan，从文件名里提取 topic，再自动附带同一 topic 的最新 spec。

## 使用流程

```
你（用户）
  │
  ├── 终端 1: /squad manager
  │     Manager 加入，询问目标，
  │     拆分任务并分配给 Worker。
  │
  ├── 终端 2: /squad worker
  │     Worker 加入，通过 squad receive 检查任务，
  │     执行分配的工作，汇报结果。
  │
  └── 终端 3: /squad worker
        自动分配为 worker-2（ID 冲突自动解决）。
        同样的行为 — 检查、执行、汇报。
```

相同角色的多个 Agent 会自动获得唯一 ID（`worker`、`worker-2`、`worker-3`）。

## 命令一览

| 命令 | 说明 |
|------|------|
| `squad init [--refresh-roles]` | 初始化工作区，创建 `.squad/`，将 `.squad/` 加入 `.gitignore`，并在缺失时向 `CLAUDE.md`、`AGENTS.md`、`GEMINI.md` 追加 squad 说明。`--refresh-roles` 只会重写 `.squad/roles/` 下内置的 `manager`/`worker`/`inspector` 文件。 |
| `squad join <id> [--role <role>] [--client <claude\|gemini\|codex\|opencode>] [--protocol-version <n>]` | 以 Agent 身份加入（ID 冲突时自动添加后缀；省略能力元数据时数据库存 `NULL`） |
| `squad leave <id>` | 归档 Agent，并保留未读工作 |
| `squad agents [--all] [--json]` | 列出在线 Agent（`--json` 每行输出一个 JSON 对象，包含原始/生效能力字段和基于协议版本推导的支持布尔值） |
| `squad send [--task-id <id>] [--reply-to <message-id>] <from> <to> <message>` | 发送普通消息（`@all` 广播给所有人，或用 `squad send [flags] --file <path-or-> <from> <to>` 从文件/标准输入读取内容） |
| `squad receive <id> [--wait] [--timeout N] [--json]` | 检查收件箱（`--wait` 阻塞等待直到消息到达；`--json` 每行输出一个 JSON 对象） |
| `squad task create <from> <to> --title <title> [--body <body>]` | 创建结构化任务分配 |
| `squad task ack <agent> <task-id>` | 领取排队中的任务 |
| `squad task complete <agent> <task-id> --summary <text>` | 用结果摘要完成已 ack 的任务 |
| `squad task requeue <task-id> [--to <agent>]` | 将任务重新排队，并可选地改派给新执行者 |
| `squad task list [--agent <id>] [--status <status>]` | 按可选过滤条件查看任务 |
| `squad pending` | 查看所有未读消息 |
| `squad history [agent] [--from <id>] [--to <id>] [--since <RFC3339\|unix-seconds>]` | 查看带时间戳的消息历史，并支持基础过滤 |
| `squad roles` | 列出可用角色 |
| `squad teams` | 列出可用团队 |
| `squad team <name>` | 查看团队模板 |
| `squad setup [platform]` | 安装 `/squad` 斜杠命令到 AI 工具 |
| `squad setup --list` | 列出支持的平台和状态 |
| `squad clean` | 清除所有状态 |

## 安装斜杠命令

```bash
squad setup           # 自动检测已安装的工具并安装
squad setup claude    # 只安装到 Claude Code
squad setup --list    # 查看支持的平台
```

| 平台 | 二进制 | 命令位置 |
|------|--------|---------|
| Claude Code | `claude` | `~/.claude/commands/squad.md` |
| Gemini CLI | `gemini` | `~/.gemini/commands/squad.toml` |
| Codex CLI | `codex` | `~/.codex/prompts/squad.md` |
| OpenCode | `opencode` | `~/.config/opencode/commands/squad.md` |

安装后，在任何执行过 `squad init` 的项目中使用 `/squad <角色>` 即可。生成的 slash 模板会自动带上所属平台的 `client` 值和当前支持的协议版本。

`squad init` 不只是创建 `.squad/`：它还会把 `.squad/` 追加到 `.gitignore`，并在 `CLAUDE.md`、`AGENTS.md`、`GEMINI.md` 尚未包含相关段落时，补上一段简短的 squad 协作说明。已有内置角色文件默认不会被覆盖，除非你显式运行 `squad init --refresh-roles`。

## 工作原理

Agent 通过共享的 SQLite 数据库（`.squad/messages.db`）通信。每个 Agent 在自己的终端中运行，使用 CLI 命令收发消息。

```
终端 1 (manager)              终端 2 (worker)              终端 3 (worker-2)
┌─────────────────────┐      ┌─────────────────────┐      ┌─────────────────────┐
│ /squad manager       │      │ /squad worker        │      │ /squad worker        │
│                      │      │ (自动 ID: worker)    │      │ (自动 ID: worker-2)  │
│                      │      │                      │      │                      │
│ squad task create    │─────>│ squad receive worker │      │                      │
│   manager worker     │      │                      │      │                      │
│   "task-a" "详情"    │      │                      │      │                      │
│                      │      │                      │      │                      │
│ squad task create    │──────────────────────────────────>│ squad receive         │
│   manager worker-2   │      │                      │      │   worker-2           │
│   "task-b" "详情"    │      │                      │      │                      │
│                      │      │                      │      │                      │
│ squad receive manager│<─────│ squad task complete  │      │                      │
│                      │      │   worker <task-id>   │      │                      │
│                      │      │   "完成 A"           │      │                      │
│                      │      │                      │      │                      │
│                      │<──────────────────────────────────│ squad task complete   │
│                      │      │                      │      │   worker-2 <task-id> │
│                      │      │                      │      │   "完成 B"           │
└─────────────────────┘      └─────────────────────┘      └─────────────────────┘
```

所有消息通过 SQLite 传递 — 无守护进程、无 socket、无后台进程。

### 消息流程

当任务状态需要被显式跟踪时，Agent 应优先使用 `squad task ...`；`squad send` / `squad receive` 仍然是自由协作的兜底路径。Agent 使用 `squad receive --wait` 阻塞等待消息：

```
Agent 加入
  → squad receive <id> --wait          ← 阻塞等待消息到达
  → 收到 Manager 分配的任务
  → squad task ack <id> <task-id>
  → 执行任务
  → squad task complete <id> <task-id> --summary "完成：摘要..."
  → squad receive <id> --wait          ← 再次阻塞等待下一条消息
```

`squad receive <id>`（不带 `--wait`）检查一次后立即返回，适用于脚本或手动检查。

### ID 自动后缀

当多个 Agent 使用相同 ID 加入时，squad 自动分配唯一 ID：

```bash
squad join worker --role worker --client codex --protocol-version 2
# → Joined as worker

squad join worker --role worker --client opencode --protocol-version 2
# → ID 'worker' was taken. Joined as worker-2
```

这是服务端原子操作（`INSERT OR IGNORE`），即使多个终端同时加入也不会冲突。

## Agent 能力元数据

`squad join` 现在可以选择性记录 Agent 的能力元数据：

```bash
squad join worker --role worker --client codex --protocol-version 2
```

- 如果省略 `--client` 或 `--protocol-version`，数据库中对应字段会存为 `NULL`。
- `squad agents` 的人类可读输出会使用生效后的 fallback 视图，因此 legacy 记录也会显示为 `client: unknown, protocol: 1`。
- `squad agents --json` 会暴露 `client_type_raw`、`protocol_version_raw`、`effective_client_type`、`effective_protocol_version`、`supports_task_commands`、`supports_json_receive`。
- 当前阶段里，`supports_task_commands` 和 `supports_json_receive` 都只根据生效后的协议版本推导，阈值为 `>= 2`。

## 角色模板

角色是 `.squad/roles/` 下的 `.md` 文件，定义 Agent 行为。内置三个角色：

- **manager** — 分解目标、分配任务、协调审查
- **worker** — 执行任务、汇报结果
- **inspector** — 审查代码、发送 PASS/FAIL 结论

自定义角色只需添加 `.md` 文件：

```bash
echo "你是数据库专家..." > .squad/roles/dba.md
squad join db-expert --role dba
```

如果 `.squad/roles/` 里的内置角色模板和当前内置默认值发生漂移，可运行 `squad init --refresh-roles`，它只会刷新 `manager.md`、`worker.md`、`inspector.md`，不会触碰自定义角色文件。

## 团队模板

团队是 `.squad/teams/` 下的 YAML 文件，定义所需角色组合：

```yaml
# .squad/teams/dev.yaml
name: dev
roles:
  manager:
    prompt_file: manager
  worker:
    prompt_file: worker
  inspector:
    prompt_file: inspector
```

使用 `squad team <name>` 查看团队配置。

## 广播

向所有 Agent 发送消息：

```bash
squad task create manager worker --title "auth-module" --body "实现 JWT 登录模块"
squad task ack worker <task-id>
squad task complete worker <task-id> --summary "JWT 登录已完成"
squad send --task-id <task-id> inspector worker "请继续检查边界场景"
squad receive worker --json
squad send manager @all "API 接口已更新，请更新你们的实现"
```

## 系统要求

- Rust 1.77+（编译需要）
- macOS 或 Linux

## 许可证

MIT
