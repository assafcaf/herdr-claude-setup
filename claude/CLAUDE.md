# Delegating work on this machine

Terminals here run inside **Herdr**, so delegated agents belong in panes where they can be
watched and interrupted. The `Agent` tool's subagents run in-process — no pane, no name, no
session id — and Herdr cannot see them.

When work needs its own agent and it writes files, runs long, or runs alongside others, spawn
it instead of calling `Agent`:

```bash
bash ~/.claude/scripts/herdr-spawn.sh <name> --task <slug> \
  --orchestrator <this session's name from ListAgents> --prompt "..."
```

One tab per task, one pane per agent. Afterwards `herdr agent get|read|wait <name>` and
`SendMessage({to: "<name>"})` both address it. Read `~/.claude/skills/herdr-spawn/SKILL.md`
before the first spawn of a session.

Cheap read-only lookups still belong in-process — use `Agent` with `subagent_type: Explore`.
A `PreToolUse` hook enforces the split and stands down outside Herdr.

Never enable `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`; its teammates are invisible to Herdr.
