# Coding agents in Dever: Claude Code and Codex

An audit of how Dever could work with the two coding agents the team uses most, what form that takes,
and in what order. Facts were read from the official documentation on 2026-11-13 and from one Mac
(read-only, structure only); every claim carries its source and its status. Phases 0 and 1 of the
[plan](#8-plan) are done; the rest is not built.

Contents: [the gap](#1-the-gap-today) · [facts](#2-facts) · [shapes compared](#3-shapes-compared) ·
[decisions](#4-decisions) · [design](#5-design) · [core or plugin](#6-core-or-plugin-and-mcp-for-both) ·
[risks](#7-risks) · [plan](#8-plan) · [open points](#9-open-points)

Status tags: **[stable]** documented without a preview label · **[preview]** documented as beta,
experimental or research preview · **[internal]** exists but the vendor says it may change, or does not
document it · **[unverified]** not confirmed in the pages read · **[observed]** seen on the audit Mac.

---

## 1. The gap today

Where a developer's work on a ticket begins and ends in Dever:

| Moment | What Dever does | What Dever sees |
| --- | --- | --- |
| Pick | "Start here" on the Delivery board, the Overview's "for you" | Linear issues, their state, blockers |
| Begin | **Start** / **Take it** moves the issue in Linear and copies its branch name | the issue's `branchName` |
| Work | nothing | **nothing** until a pull request exists |
| Pull request | matched to the issue by branch or identifier; CI, review, preview, each with its age | head ref, author login, checks, reviews |
| End | "Merged, ticket not moved", Move to …, reply in the Slack thread | merge, issue state |

The blind stretch is the development phase itself. Between "Copy branch" and the first pull request
Dever knows nothing of: the local clone (it only knows GitHub repositories, never a path), the branch
actually checked out, a worktree, uncommitted or unpushed work, and whether an agent session is running
on the ticket, waiting for an answer, or finished. With agents that stretch is also where the developer
is absent: several sessions run in parallel and each one is a window to go and look at.

Two smaller gaps: Dever does not read a pull request's body or its commits, so it cannot tell an
agent-written pull request from another; and the context an agent needs (the issue, its comments, the
Slack thread it came from, the state of CI and of the preview) is exactly what Dever already holds in
its stores, but only a human can read it there.

---

## 2. Facts

### 2.1 On the audit Mac [observed]

- Both desktop apps are installed. The Claude app registers the `claude` URL scheme, the Codex app
  (bundle `com.openai.codex`) registers `codex`. The Codex app bundles its own `codex` binary.
- **No `claude` command on the `PATH`**: Claude Code runs from inside the desktop app. The `codex`
  command installed through npm is broken (its vendored binary is missing). A design that needs the
  CLIs on the `PATH` fails on this machine; one that needs "the tool the user actually opens" does not.
- Claude Code: `~/.claude/projects/<path with - for separators>/<session uuid>.jsonl`, one folder per
  working directory. Lines carry `sessionId`, `cwd`, `gitBranch`, `version`, `entrypoint`, `timestamp`;
  a `custom-title` line names the session. Files reach 25 MB. User `settings.json` already holds hooks,
  and the desktop app's sessions run them.
- Codex: `~/.codex/sessions/YYYY/MM/DD/rollout-<timestamp>-<uuid>.jsonl`; the first line (`session_meta`)
  carries `id`, `cwd`, `originator`, `cli_version` and `git` (`branch`, `commit_hash`, `repository_url`).
  Also `session_index.jsonl`, `history.jsonl`, several SQLite files, `hooks.json` (SessionStart,
  UserPromptSubmit, PreToolUse, PostToolUse, Stop), and `config.toml` with `[mcp_servers.*]`,
  `[plugins.*]`, `notify`.
- Both transcripts therefore name the working directory and the branch: a session can be tied to an
  issue by its branch, the same key Dever already uses for pull requests.

### 2.2 Claude Code

Sources: `code.claude.com/docs/en/<page>` unless a full link is given.

| Topic | Fact | Status |
| --- | --- | --- |
| Headless | `claude -p "…"` with `--output-format text\|json\|stream-json`, `--input-format stream-json`; `--resume <id>`, `--continue`, `--session-id <uuid>`, `--fork-session`, `--append-system-prompt`, `--permission-mode`, `--allowedTools`, `--mcp-config`, `--add-dir`, `--worktree`, `--name` ([headless](https://code.claude.com/docs/en/headless), [cli-reference](https://code.claude.com/docs/en/cli-reference)) | stable |
| Interactive with a prompt | `claude "query"` ([cli-reference](https://code.claude.com/docs/en/cli-reference)) | stable |
| SDK | Agent SDK in TypeScript and Python only; from Swift the route is spawning the CLI with `stream-json` ([headless](https://code.claude.com/docs/en/headless)) | stable |
| Deep link, terminal | `claude-cli://open?cwd=/abs/path&q=…` (or `repo=owner/name`) opens a terminal session with the prompt **filled in, not sent**; the handler is registered after one interactive use ([deep-links](https://code.claude.com/docs/en/deep-links)) | stable |
| Deep link, VS Code | `vscode://anthropic.claude-code/open` ([deep-links](https://code.claude.com/docs/en/deep-links)) | stable |
| Deep link, desktop app | none documented ([desktop](https://code.claude.com/docs/en/desktop)); the app registers `claude://` and answers `claude://code/new?q=&folder=` (section 2.5) | internal, observed |
| Web session with a prefilled prompt | no URL documented | unverified |
| Transcripts | path `~/.claude/projects/<encoded cwd>/<session>.jsonl` is documented; the line format is "internal and changes between versions"; kept `cleanupPeriodDays` (30) ([sessions](https://code.claude.com/docs/en/sessions)) | path stable, format internal |
| Listing sessions | SDK `listSessions()`, `getSessionMessages()`, `getSessionInfo()` ([agent-sdk/sessions](https://code.claude.com/docs/en/agent-sdk/sessions)); `claude agents --json` gives `state` (working, blocked, done, failed, stopped) and `status` (busy, waiting, idle) per session ([agent-view](https://code.claude.com/docs/en/agent-view)) | SDK stable; `claude agents` preview |
| Hooks | 30+ events, among them SessionStart, SessionEnd, UserPromptSubmit, PreToolUse, PostToolUse, PermissionRequest, Notification, Stop, SubagentStop, WorktreeCreate. Every payload has `session_id`, `transcript_path`, `cwd`, `permission_mode`, `hook_event_name`. Handler types `command`, `http`, `mcp_tool`, `prompt`, `agent`. An `http` hook may post to `http://localhost` (subject to `allowedHttpHookUrls` when an organisation sets it). Configured in user, project, local or managed settings, or in a plugin ([hooks](https://code.claude.com/docs/en/hooks)) | stable (`agent` type preview) |
| Telemetry | OpenTelemetry metrics and events to a local collector; prompts redacted by default ([monitoring-usage](https://code.claude.com/docs/en/monitoring-usage)) | stable (traces preview) |
| MCP client | `claude mcp add --transport http\|stdio`, scopes local / project (`.mcp.json`, approval asked) / user; OAuth; output capped at 25k tokens by default ([mcp](https://code.claude.com/docs/en/mcp)) | stable |
| Channels | an MCP server can push events into a running session; allow-listed plugins only ([channels](https://code.claude.com/docs/en/channels)) | preview |
| Plugins | one unit bundling skills, hooks and MCP servers (`.claude-plugin/plugin.json`, `hooks/hooks.json`, `.mcp.json`), served from a marketplace file; installed once, shared by terminal, desktop and VS Code; not loaded by cloud sessions ([plugins](https://code.claude.com/docs/en/plugins/overview)) | stable |
| Worktrees | `claude -w <name>` creates `<repo>/.claude/worktrees/<name>` on branch `worktree-<name>`; the desktop app's worktrees are off by default, with a branch prefix setting ([worktrees](https://code.claude.com/docs/en/worktrees), [desktop](https://code.claude.com/docs/en/desktop)) | stable |
| Cloud | `claude --cloud "task"`, `--teleport` to bring it back ([claude-code-on-the-web](https://code.claude.com/docs/en/claude-code-on-the-web)); branch prefix and commit author of cloud sessions | stable; prefix and author unverified |
| On GitHub | `attribution.commit` adds `Co-Authored-By: <model> <noreply@anthropic.com>`, `attribution.pr` adds a "Generated with Claude Code" footer; both can be turned off ([settings](https://code.claude.com/docs/en/settings-reference)). `anthropics/claude-code-action` answers `@claude` as the Claude GitHub App ([github-actions](https://code.claude.com/docs/en/github-actions)) | stable; branch naming unverified |
| Permissions | modes `default`, `acceptEdits`, `plan`, `auto`, `dontAsk`, `bypassPermissions`; defaults differ by version and by interactive / headless, so a launcher passes the mode explicitly; `auto` and `bypassPermissions` are ignored when set from a project's settings ([permission-modes](https://code.claude.com/docs/en/permission-modes)) | stable |
| Live status from outside | no local API. Supported: hooks, `claude agents --json` (preview). `~/.claude/jobs/*/state.json` and the daemon socket are declared not an interface ([agent-view](https://code.claude.com/docs/en/agent-view)) | internal |

### 2.3 Codex

Sources: `learn.chatgpt.com/docs/<page>` (where `developers.openai.com/codex` now redirects). Four long
pages (CLI reference, app server, config reference, managed configuration) were read in part.

| Topic | Fact | Status |
| --- | --- | --- |
| Headless | `codex exec` with `--json` (events `thread.started` carrying `thread_id`, `turn.*`, `item.*`), `-o`, `--output-schema`, `-C`, `--sandbox`, `-a on-request\|never`; read-only by default; `codex exec resume <id>\|--last`. `--full-auto` is no longer supported ([non-interactive](https://learn.chatgpt.com/docs/non-interactive-mode)) | stable |
| Interactive with a prompt | `codex [PROMPT]`: "Optional user prompt to start the session" (`codex --help`, 0.154) | observed |
| SDK | TypeScript `@openai/codex-sdk`, Python `openai-codex` ([codex-sdk](https://learn.chatgpt.com/docs/codex-sdk)) | stable |
| App server | `codex app-server`, JSON-RPC over stdio, documented "for deep integration", with thread status (`idle`, `active` + `waitingOnApproval`) for threads the client itself starts; "isn't supported for production workloads" ([app-server](https://learn.chatgpt.com/docs/app-server)) | preview |
| Codex as an MCP server | `codex mcp-server` has been removed ([mcp-server](https://learn.chatgpt.com/docs/mcp-server)) | removed |
| Deep link, desktop app | `codex://new?prompt=…&path=/abs/dir` (or `originUrl=<git remote>`): the prompt fills the composer; `codex://threads/<id>` opens a thread; `codex://plugins/install/<name>?marketplace=<m>` ([commands](https://learn.chatgpt.com/docs/reference/commands.md)); `codex app [PATH]` | stable |
| Transcripts | only `CODEX_HOME`, `config.toml`, `auth.json`, `history.jsonl` are named; the rollout path, its schema and the SQLite state are not, and rollout files may be compressed ([config-advanced](https://learn.chatgpt.com/docs/config-file/config-advanced), [app-server README](https://github.com/openai/codex/blob/main/codex-rs/app-server/README.md)) | internal |
| Listing sessions | `codex resume [id] [--last] [--all]`, `codex fork <id> [--worktree]`; programmatic listing only through the app server ([developer-commands](https://learn.chatgpt.com/docs/developer-commands?surface=cli)) | stable; listing preview |
| Hooks | on by default; `~/.codex/hooks.json`, `[hooks]` in `config.toml`, the same in a trusted repository, or a plugin. Events SessionStart, SessionEnd, UserPromptSubmit, PreToolUse, PermissionRequest, PostToolUse, Stop, Interrupt, SubagentStart/Stop, Pre/PostCompact. Payload `session_id`, `transcript_path`, `cwd`, `hook_event_name`, `model`. Handlers `command` and `mcp_tool` only (no `http`); hooks that are not managed need the user's trust review once ([hooks](https://learn.chatgpt.com/docs/hooks)) | stable |
| `notify` | a program run at `agent-turn-complete` with `thread-id`, `cwd`, `input-messages`, `last-assistant-message` ([config-advanced](https://learn.chatgpt.com/docs/config-file/config-advanced)) | stable |
| MCP client | `codex mcp add <name> -- <cmd>` (stdio) or `--url` (streamable HTTP) with `--bearer-token-env-var`, OAuth; `[mcp_servers.<name>]`; one configuration shared by the desktop app, the CLI and the IDE extension ([mcp](https://learn.chatgpt.com/docs/extend/mcp?surface=cli)) | stable |
| Skills, plugins | `AGENTS.md`; skills as `SKILL.md` folders under `.agents/skills`; plugins bundle skills, `mcp.json` and `hooks/hooks.json`, served from one's own marketplace (`codex plugin marketplace add`). The public directory refuses plugins with hooks or a local server ([build-skills](https://learn.chatgpt.com/docs/build-skills), [plugins](https://developers.openai.com/codex/plugins/build)) | stable |
| Worktrees | the app creates managed worktrees under `$CODEX_HOME/worktrees`, **detached HEAD**, no automatic branch (the branch dialog suggests `codex/…`) ([git-worktrees](https://learn.chatgpt.com/docs/environments/git-worktrees)) | stable |
| Cloud | cloud tasks from web, desktop, CLI (`codex cloud`, preview), Slack, Linear (assign the issue to Codex; it reports in the issue's activity, the pull request is not automatic) ([cloud](https://learn.chatgpt.com/docs/cloud), [linear](https://learn.chatgpt.com/docs/third-party/linear)) | stable |
| On GitHub | `@codex review` posts a review from the `chatgpt-codex-connector` bot ([github](https://learn.chatgpt.com/docs/third-party/github)). For pull requests Codex creates, the documentation gives no branch pattern, author, label, body marker or trailer | review stable; the rest unverified |
| Permissions | sandbox `read-only`, `workspace-write`, `danger-full-access` (Seatbelt on macOS, network off by default); approvals `on-request` or `never`; default for a git folder is `workspace-write` + `on-request` ([agent-approvals-security](https://learn.chatgpt.com/docs/agent-approvals-security)) | stable |
| Live status from outside | no way to attach to a session owned by the app or a terminal; hooks are the documented indirect route | hooks stable |

### 2.4 What the facts allow

- **Hooks are the one stable, documented, symmetrical signal.** Both tools fire SessionStart,
  UserPromptSubmit, PermissionRequest, Stop and SessionEnd with `session_id` and `cwd`, in the terminal
  and in the desktop app alike. Everything else that tells "working / waiting / finished" is either a
  preview (`claude agents`, the Codex app server) or an internal file.
- **MCP is stable on both sides as a client**, with local HTTP and stdio servers. Neither tool is worth
  consuming as a server (Codex removed it).
- **Plugins are the install unit on both sides**: one plugin carries the hooks, the MCP server entry
  and a skill, and the desktop apps share it with the terminal.
- **Launching is uneven.** Codex app and Claude Code in a terminal have documented deep links that fill
  the prompt without sending it. The Claude desktop app, which is what this team opens, has none.
- **GitHub signals for agent authorship are weak**: a co-author trailer and a footer that users can
  switch off (and that this repository forbids), a bot account for Codex reviews only. Recognising an
  agent's pull request from GitHub alone is guessing; recognising it because Dever saw the session is not.
- **Transcripts are private and unstable.** They hold whole conversations, their formats are disclaimed
  by both vendors, and Dever does not need them.

### 2.5 Phase 0: what was checked afterwards

**The Claude desktop app has a way in** [internal, observed in version 5.11492]. Read from the app's
own bundle, where its Finder service "New Claude Code Session Here" uses it:

| Link | Does |
| --- | --- |
| `claude://code/new?q=<prompt>&folder=<absolute path>` | opens the Code tab's new session on that folder with the prompt in the composer. `prompt` is accepted for `q`; the text is cut at 14,336 characters; `folder` may repeat |
| `claude://code/needs-input?session=<local session id>` | brings forward a session that waits for the user (no id: the list of those) |
| `claude://code/continue?session=last` | the last session |
| `claude://resume?session=<uuid>` | imports a CLI session by its id and opens it: the id is the `session_id` of the hooks, so this is "Open session" for phase 2 |

None of this is documented, so it can change with any update of the app: the launch must fail in
words when the app does not answer. Not checked by a click: that the prompt is filled in and not sent
(the app's own service relies on it for the folder; the prompt takes the same path).

**Hook payloads** [stable, from the hooks pages of both tools]. `Stop` carries
`last_assistant_message` (string or null) in Claude Code and in Codex: the last sentence needs no
transcript. Claude Code's `Notification` carries `message` and a `notification_type` (among them
`permission_prompt`, `idle_prompt`, `agent_needs_input`, `agent_completed`); `SessionStart` has
`source` (startup, resume, clear, compact, fork); `SessionEnd` has `reason` (Codex: always `other`).
`PermissionRequest` has `tool_name` and `tool_input` in both. Neither payload says which client
(terminal or desktop app) runs the session.

**Installing a plugin without the CLI** [unverified]. Claude Code documents an "Add plugins" entry in
the desktop app and accepts a local directory as a marketplace; whether that works with no `claude`
on the `PATH` is not stated. Codex has `codex://plugins/install/<name>?marketplace=<m>`. To settle
with a real install at the start of phase 2.

---

## 3. Shapes compared

| Shape | What the developer gets | Effort | Fragility | Privacy | Needs on the Mac |
| --- | --- | --- | --- | --- | --- |
| **(a) Launch**: "Start with Claude Code / Codex" on an issue | the brief is ready, in the right folder and branch; the session is born tied to its issue | medium | low for Codex app and terminals (documented links); the Claude desktop app has no documented entry | the brief leaves Dever for a tool the user already trusts | local clones, the tool installed |
| **(b) Observe**: the issue shows its agent working, waiting, finished | the blind stretch of section 1 is filled; "waiting for you" is found without touring windows | medium | low with hooks; high if read from session files | state and one sentence, in memory | a plugin installed in each tool |
| **(c) Context**: Dever as an MCP server | the agent reads the issue, the thread, CI and the preview itself, fresh; it can report back | medium to large | low (MCP is stable); Dever must be running | Slack and Linear content reaches the agent's model provider, on the agent's request | the plugin, Dever open |
| **(d) Review**: agent work comes back as "review its work" | the agent's own account, the acceptance criteria, CI and preview on one tile; follow-up writes one click away | medium, on top of (b) and (c) | low | the agent's summary only | (b) and (c) |
| **(e) Orchestration**: Dever starts and steers several agents | a control room | very large: Dever becomes an agent client (headless runs, approvals, diffs) | high: preview protocols, two of them | everything flows through Dever | both CLIs, kept in step with their versions |

**Which make the development phase clearer.** (b) is the one that does, directly: it puts the missing
row in the table of section 1. (d) makes the end of the phase clear: "the agent is done" becomes a
state with what to check, where today it is a pull request like any other. (a) alone is a button, but
it is what makes (b) exact instead of guessed, because a session Dever launched is tied to its issue
from the first second. (c) alone is invisible to the developer; its value is that the brief stays short
and the follow-up (move the ticket, answer the thread) starts from the agent instead of from memory.
(e) as orchestration is rejected: both vendors ship that surface themselves and change it monthly. Its
cheap half is kept: a board that lists the sessions Dever already knows about, and steers none.

The four pains the user named (preparing the brief, knowing where agents are, reviewing what they made,
keeping Linear and Slack up to date) map one to one onto (a), (b), (d) and the "propose" half of (c).

---

## 4. Decisions

Taken with the user, one question at a time (2026-11-13).

| # | Question | Decision |
| --- | --- | --- |
| 1 | Where the agents run | The desktop apps and the terminal. Not the IDE extensions, not the cloud: no cloud work in this plan |
| 2 | Where time is lost | All four: the brief, knowing where agents are, reviewing their work, keeping Linear and Slack up to date |
| 3 | Start agents or only watch | **Launch and follow** |
| 4 | Where a launched session opens | **In the user's usual tool** (desktop app or terminal, chosen in Settings), in the right folder, brief filled in and not sent. For the Claude desktop app, which has no documented entry, the app is to be inspected to find a clean one (phase 0) |
| 5 | The signal for working / waiting / finished | **Hooks installed by Dever.** No reading of session files |
| 6 | What is shown of a session | Tool, state, age, branch, and **the agent's last sentence or question**. Nothing stored on disk |
| 7 | What an agent may do through Dever | **Read freely, propose writes.** Moving an issue or replying in a thread arrives in Dever as a proposal the user applies. Nothing leaves in the user's name without them |
| 8 | Finding the local clone | **One root folder in Settings**; each repository found under it by its GitHub remote; asked for when missing |
| 9 | Where the agent works | **A worktree on the issue's branch** (the branch name Linear gives) |
| 10 | The brief | **Short**: the issue, its acceptance criteria, the branch, the identifier. The rest (thread, comments, linked issues, CI) is fetched by the agent through Dever's MCP tools |
| 11 | Where sessions appear | On the issue page and its Delivery row, and **a board of agents** across projects. Not in the Overview's "for you", no macOS notification (both tools already notify) |
| 12 | When the agent has finished | **A "review its work" step**: the agent's account, the acceptance criteria to tick, CI and preview, then its proposals |
| 13 | Colleagues | **Local only.** Each developer sees their own agents; nothing is written anywhere to share the state |
| 14 | Installing into the tools | **A "Connect" button per tool in Settings › Agents**, showing exactly what is added, installed by the tool's own plugin command, removed by "Disconnect". Dever never edits their configuration files by hand |
| 15 | Core or plugin | **Core, on the plugin system's mechanism** (section 6) |

---

## 5. Design

### 5.1 The pieces

```
 Dever.app
 ├─ AgentStore            app-lifetime, memory only: sessions by issue (tool, state, age, branch, last sentence)
 ├─ AgentBridge           loopback listener: receives hook events, serves MCP (streamable HTTP, bearer token)
 ├─ AgentLauncher         clone lookup, worktree on the issue's branch, brief, open the tool
 └─ ProposalStore         writes proposed by agents, waiting for the user

 dever plugin for Claude Code          dever plugin for Codex
 ├─ hooks  → AgentBridge               ├─ hooks (command) → AgentBridge
 ├─ MCP server entry → AgentBridge     ├─ MCP server entry → AgentBridge
 └─ skill: how to use the tools        └─ skill: the same text
```

One listener, two thin plugins with the same content. Dever already listens on loopback for OAuth, and
is not sandboxed, so nothing new is asked of macOS.

### 5.2 Launch

On a "Start here" tile and on the issue page, **Start with Claude Code ⌄** (a `MenuTriggerButton`
opening a `MenuPanel`: Claude Code, Codex, and where each opens) sits beside **Start**. It:

1. finds the clone: the repository of the issue's project under the root folder, by its `origin` remote;
2. creates the worktree itself with `git worktree add` on the issue's `branchName`, so both tools
   start the same way (Claude Code's own `-w` names the branch `worktree-…`, Codex's worktrees are
   detached: neither gives the branch Dever matches pull requests on);
3. writes the brief (title, description, acceptance criteria, branch, identifier, one line naming the
   `dever` tools);
4. opens the tool on that folder with the brief filled in: `codex://new?prompt=…&path=…` for the Codex
   app, `claude-cli://open?cwd=…&q=…` for Claude Code in a terminal, a terminal command for the Codex
   CLI, and for the Claude desktop app whatever phase 0 finds (fallback: open the folder, brief on the
   clipboard, said in the button's tooltip);
5. does what **Start** does today (moves the issue, optimistic, Undo), and records the launch so the
   first SessionStart from that folder is tied to the issue without guessing.

Permissions are left to each tool's own defaults and prompts. Dever passes no flag that widens them.

### 5.3 Observe

Hooks post five events to the bridge: session started, prompt submitted (working), permission or
question asked (waiting for you), turn finished (finished, with the last sentence), session ended.

- **Tied to an issue** by the launch record; for a session started outside Dever, by the branch checked
  out in the hook's `cwd`, with the matching `PullRequestMatching` already does. A session on no known
  branch appears on the board only, under its folder name.
- **States**: Working · Waiting for you · Finished · Ended. A state carries its age, like CI. A
  "working" that has sent nothing for ten minutes is drawn as old ("last heard 14 min ago"), never as
  current: Dever only knows what the last hook said, and a killed terminal sends no SessionEnd.
- **Where**: a line on the issue page and on its Delivery row with **Open session** (`codex://threads/<id>`
  for Codex; for Claude Code, bringing its app forward, or better if phase 0 finds it). In the Delivery
  ranking, "waiting for you" sits with the actionable situations at the top and "working" moves the
  issue out of "Start here" (it is started). The board lists every session, grouped by project.
- **Not Dever's data to fetch**: nothing is polled. The store is fed by events, lives in memory, and is
  empty after a relaunch until the next event of each session.

### 5.4 Context: the MCP server

Read tools, answering from the stores Dever already keeps fresh (no second copy, no new polling):
`get_issue` (description, acceptance criteria, comments, linked issues, blockers), `get_thread` (the
Slack thread linked to the issue), `get_delivery` (the issue's pull requests, checks, reviews, preview,
each with its age), `list_my_issues`. Tool results carry the age of what they return.

One write-shaped tool, `propose_update`: a status for the issue, a reply for the thread, a short account
of what was done and what was not verified. It writes nothing. It lands in `ProposalStore` and shows on
the issue as "Proposed by the agent" with **Apply**, **Review & send** and **Dismiss**; applying goes
through the existing optimistic writes and their invalidations.

The server binds to loopback, requires a token generated at "Connect" and kept in the Keychain, and
answers only while Dever runs; the skill tells the agent to carry on without it when it does not answer.

### 5.5 Review

A new Delivery situation, **Agent finished · review its work**, ranked with the top actionable ones:
the agent's account (from `propose_update`, else its last sentence), the acceptance criteria as a
checklist (ticks are the user's, local), the pull request with CI and preview and their ages, the
proposals, **Open PR** and **Open session**. It ends when the user applies or dismisses the proposals,
or when the pull request is merged. Authorship comes from the session Dever saw, never from a trailer
or a branch prefix.

### 5.6 Data contract (for the implementing changes)

```
Data contract
- Reads:        AgentStore (session by issue; new), ProposalStore (new); IssueStore, SlackStore, GitHubStore, PreviewStore (existing, served to MCP)
- Writes:       none of its own; an applied proposal is an existing Linear or Slack write (optimistic, restored on refusal)
- Invalidates:  what that existing write already invalidates (issue rows, Overview)
- Budget:       event-driven, no clock; "working" older than 10 min without an event is shown as old
- Loading:      none: no value means no line
- Failure:      bridge not reachable from a hook → the hook exits silently; the line keeps its last state and its age
- Exits:        "Open session" leaves for the agent's app; nothing to mark dirty (state arrives by events)
- Cost:         no request to Slack, Linear or GitHub; MCP reads are served from the stores
```

A row "Agent session state" joins the budget table of `docs/data-freshness.md`, and the board a row in
its section 5, in the changes that add them.

---

## 6. Core or plugin, and MCP for both

Agents are **core**: the whole team uses them, and they change the Delivery board itself. But the two
directions of MCP are one brick used twice:

| | Dever as MCP **server** | Dever as MCP **client** |
| --- | --- | --- |
| Who calls | Claude Code, Codex | Dever |
| For | agents reading project context and proposing updates | niche integrations offered as plugins: the internal time-and-availability tool is the first case |
| Shared with the other side | the loopback listener, the token handling, the JSON-RPC and tool-schema code, the Settings pattern ("Connect", what it adds, "Disconnect") | the same |

So: build the protocol layer once in this work (phases 2 and 3), and let the plugin system reuse it as
a client. One mechanism serves both, with one limit: a Dever plugin that needs to draw something in the
app (a panel, a row) needs more than MCP, and that part belongs to the plugin system's own design.

---

## 7. Risks

| Risk | Why | Answer |
| --- | --- | --- |
| The Claude desktop app has no documented way in | only `claude-cli://` (terminal) is documented | phase 0 inspects the app; whatever is found is undocumented and may break on any update, so the clipboard fallback stays, and the launch is tested at each app update |
| Hook payloads change | fields are documented but both tools move fast | the bridge reads five events and three fields; unknown fields are ignored; a version check in Settings › Agents says when a tool is newer than the last one tested |
| Hooks blocked by an organisation | `allowedHttpHookUrls`, managed hooks, Codex's trust review | Claude Code hooks use a `command` too if `http` is refused; Settings says "installed, not trusted yet" for Codex until its review is done |
| Private conversations | transcripts hold everything | Dever never opens them; the one sentence shown comes from the hook, stays in memory, and is gone at quit |
| Slack and Linear content reaching a model provider | an agent that calls `get_thread` sends the thread to Anthropic or OpenAI | it only happens on the agent's call, in a tool the user chose; said once at "Connect"; per-tool switch for thread access in Settings › Agents. This is new for an app whose AI is otherwise on-device, and the README's claim must stay true as worded |
| A local server other processes can call | loopback is reachable by anything on the Mac | bearer token from the Keychain, loopback only, read tools only, proposals never applied without a click |
| Prompt injection through project content | a Slack message can tell the agent what to do | Dever's tools cannot write; the worst outcome is a bad proposal the user reads before applying |
| A stale state taken for a live one | a killed session sends nothing | ages on every state, "working" turns old after ten minutes |
| Worktrees pile up | one per issue | Dever lists the ones it created and offers to remove those whose pull request is merged; it never deletes one with uncommitted work |
| Dever not running | the bridge is the app | hooks and tools fail silent and fast; nothing in the agent depends on Dever |
| Two tools to keep level | each feature exists twice | one bridge, the same five events, the same tools; anything only one tool can do is left out |

---

## 8. Plan

Smallest useful step first. Days are rough, for one developer who knows the code.

| Phase | What | Useful alone? | Effort |
| --- | --- | --- | --- |
| **0. Checks** (done, section 2.5) | Inspect the Claude desktop app for a way to open a session on a folder with a prompt, and to bring a session forward. Verify on real installs: the fields of Stop and PermissionRequest (is the last sentence there, in both tools), the plugin install commands from a Mac with no CLI on the `PATH`, Codex's trust review, `codex "prompt"`, the length a deep link's prompt may reach | decides the shape of 1 and 2 | 1–2 d |
| **1. Launch** (done) | Settings › Agents with the clones' root folder; clone lookup; worktree on the issue's branch; the brief (complete enough to stand without MCP: issue, criteria, link to the thread); "Start with … ⌄" on the Start tile and the issue page | yes: the brief and the right folder in one click | 3–4 d |
| **2. Observe** | The two plugins (hooks only) and "Connect / Disconnect"; `AgentBridge`; `AgentStore`; the state line on the issue and its Delivery row; the ranking; "Open session" | yes: this is the phase that fills the blind stretch | 4–5 d |
| **3. Context** | MCP server with the read tools, the token, the skill; the brief shrinks to its short form | for the agent; invisible to the developer | 4–5 d |
| **4. Propose and review** | `propose_update`, `ProposalStore`, "Proposed by the agent", the "review its work" situation with the criteria checklist | yes: closes the loop with Linear and Slack | 5–6 d |
| **5. Board** | The agents board across projects; worktree clean-up | once several agents run at once | 2–3 d |
| **6. Plugins** | The MCP client on the same layer, first case the time-and-availability tool | belongs to the plugin system's plan | there |

What phase 1 built: `Model/AgentLaunch.swift` (tools, where each opens, clone lookup by `origin`
remote, worktree folder and `git worktree add` arguments, the brief, the links), `Services/AgentLauncher.swift`
(git, opening the tool), `Views/AgentStart.swift` (the menu), Settings › Agents, "Start with ⌄" beside
**Start** and "Continue with ⌄" beside **Copy branch** on the Start tile, "Open with ⌄" in the issue
page's Details. Worktrees go to `.dever/worktrees/<repository>/<branch>` in the code folder; a branch
already checked out anywhere (the clone, a worktree another tool made) is opened where it is. Not
verified by a click: the four openings against the real apps, and a worktree in a real repository
(the test makes its own).

Phases 1 and 2 can swap: 2 first gives the clearer development phase sooner, with sessions tied to
issues by branch alone; 1 first gives the launch record that makes the tie exact.

Each phase comes with tests in `Tests/DeverTests` for what it derives (session to issue matching, state
ageing, the ranking, proposal application), a row in the buttons gallery for any new role use, and the
data contract of section 5.6.

---

## 9. Open points

- What the desktop apps show when opened on a worktree they did not create.
- Whether a Mac with only the desktop apps can install a plugin without the CLI (the Codex app has an
  install deep link; Claude's route is to be checked).
- "Open session" for the Claude desktop app: `claude://resume?session=` is the candidate (section 2.5).
- A project with several repositories: the menu asks which one and remembers it; whether an issue
  could name its repository itself.
- Sessions an agent starts itself (subagents, side sessions): one line per top session, the rest ignored.
- The wording shown at "Connect" about project content reaching the agent's provider.
