---
name: herdr-spawn
description: Spawn a team of named Claude sessions as Herdr panes instead of in-process subagents, so the operator can watch and interrupt them. Use when a task needs more than one agent, when delegated work will write files or run long, or when a PreToolUse hook has refused an Agent call and pointed here.
---

# Spawning a visible team

The `Agent` tool's subagents run in-process. They have no pane, no name and no session id, so
Herdr cannot see them and the operator cannot watch, prompt or interrupt one. This machine
redirects that work into real panes for every repo — `~/.claude/hooks/route-agent-to-herdr.sh`
blocks the Agent types that can write or run long, and points here. Outside Herdr
(`HERDR_ENV != 1`) the hook stands down and the Agent tool behaves normally.

One spawn produces three identities that refer to the same agent:

| Identity | Used for | Set by |
|---|---|---|
| herdr agent name | `herdr agent get/read/prompt/wait <name>` | `herdr agent start <name>` |
| Claude Code peer name | `SendMessage({to: "<name>"})` | `claude --name <name>` |
| session uuid | the join key; `herdr agent list` reports it as `agent_session.value` | `claude --session-id <uuid>` |

`~/.claude/scripts/herdr-spawn.sh` sets all three to agree, so after spawning `reviewer` you can
address it either way and mean the same pane.

## Topology

One tab per task, one pane per agent. The tab is labelled with the task slug and created on
first use; later agents for the same slug land beside their siblings.

```
workspace w7
├── tab "2"              you, the orchestrator
└── tab "review-KAN-32"  the team
    ├── pane reviewer
    ├── pane tester
    └── pane docs
```

## Spawn

Get your own name from `ListAgents` — the first line names this session — and pass it as
`--orchestrator` so the child can message you back.

```bash
bash ~/.claude/scripts/herdr-spawn.sh reviewer \
  --task review-KAN-32 \
  --orchestrator rollout-collection-8c \
  --prompt "Review the diff on this branch. Report findings only; change nothing."
```

Spawn siblings with the same `--task`. Do the spawns one after another, not in parallel: each
one reads the tab's current pane list to decide where to split.

Useful options:

| Option | When |
|---|---|
| `--env KEY=VALUE` | anything else the child needs; repeatable |
| `--cwd <path>` | a different directory, e.g. a worktree of its own |
| `--wait --timeout <ms>` | you want the spawn call to block until the first turn settles |
| `--dry-run` | print the herdr commands without running them |
| `-- <claude args...>` | passed to `claude` verbatim — see permissions below |

Every spawned pane receives `CC_TEAM_TASK`, `CC_TEAM_AGENT`, `CC_TEAM_ORCHESTRATOR`,
`CC_TEAM_ORCHESTRATOR_PANE` and `CC_TEAM_ORCHESTRATOR_SESSION_AT_START`. Tell the child to read
`CC_TEAM_ORCHESTRATOR` and reply to it with `SendMessage`; that is the return path, and it is
the one thing a spawned agent cannot work out for itself.

Pass `--orchestrator` from `ListAgents`, never from `$CLAUDE_CODE_SESSION_ID`. A
`claude --resume` gives the session a new messaging identity while the environment variable and
Herdr's `agent_session.value` both keep reporting the uuid from the original start — observed
2026-09-10, when the name moved from `rollout-collection-8c` to `rollout-collection-fc` and
neither of those two followed. `CC_TEAM_ORCHESTRATOR_PANE` is the handle that survives a resume;
the `_AT_START` variable is named for what it is and nothing should be built on it.

## Drive

Two channels, both addressing the same agent by name. Prefer `SendMessage` for instructions
and results, `herdr agent` for lifecycle and for seeing what is on screen.

```bash
herdr agent get reviewer                                      # idle|working|blocked|done
herdr agent read reviewer --source recent-unwrapped --lines 120
herdr agent wait reviewer --until blocked --timeout 120000    # it needs an answer
```

```js
SendMessage({to: "reviewer", message: "..."})                 // instructions, results
SendMessage({to: "reviewer", notify_when_idle: true})         // one-shot; never poll
```

`blocked` means Herdr recognised an approval or question dialog. Read the pane and ask the
operator before answering it — do not send keys at a dialog you have not looked at.

## Permissions, the thing that will bite first

A spawned session starts with default permissions and its own trust state. It will stop at
the first prompt and sit there as `blocked`, which looks like a hang. Either pass a mode:

```bash
bash ~/.claude/scripts/herdr-spawn.sh tester --task review-KAN-32 \
  --orchestrator <you> -- --permission-mode acceptEdits
```

or spawn read-only agents and keep the writing in your own session. Note that a peer's
permissions are its own: never route work a hook or a denial blocked in your session through
a spawned agent. That is permission laundering, and the answer is to go back to the operator.

## Tear down

Close the tab you created, which takes its panes with it:

```bash
herdr tab close w7:t3
```

Do this when the task is done — live agent names are unique, so a forgotten `reviewer` blocks
the next one. Never close a tab, pane or workspace you did not create.

## When not to use this

A single read-only lookup. `Explore` and `claude-code-guide` stay in-process on purpose: a
five-second search is not worth a pane, a process start and a teardown. The hook allows those
types; if you find yourself wanting a pane for one, you probably want `Explore`.
