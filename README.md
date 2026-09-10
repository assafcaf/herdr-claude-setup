# herdr-claude-setup

Makes Claude Code delegate work to **Herdr panes** instead of in-process subagents, and carries
that setup to any machine.

## The problem

The `Agent` tool's subagents run in-process inside the calling session — no PTY, no child
process, no session id. Herdr recognises agents by inspecting what occupies a pane, so an
in-process subagent is invisible to it and always will be. It never appears in
`herdr agent list`, occupies no pane, and cannot be watched, prompted or interrupted.

So a delegated agent is spawned as a real `claude` process in a real pane instead.

## What one spawn gets you

```bash
bash ~/.claude/scripts/herdr-spawn.sh reviewer --task review-42 \
  --orchestrator <caller's name from ListAgents> --prompt "..."
```

Three identities that already agree:

| Identity | Used for | Set by |
|---|---|---|
| herdr agent name | `herdr agent get/read/prompt/wait reviewer` | `herdr agent start` |
| Claude Code peer name | `SendMessage({to: "reviewer"})` | `claude --name` |
| session uuid | the join key — `herdr agent list` reports it as `agent_session.value` | `claude --session-id` |

One tab per task, one pane per agent, laid out as a grid. A `PreToolUse(Agent)` hook enforces
the split: subagent types that write or run long are refused and pointed here, while cheap
read-only ones (`Explore`, `claude-code-guide`) still run in-process, because a five-second
search is not worth a pane, a process start and a teardown.

Outside Herdr (`HERDR_ENV != 1`) the hook stands down and the `Agent` tool behaves normally, so
this is inert on a machine that isn't running Herdr.

## Install

Herdr itself must already be installed — `install.sh` checks for it and refuses to guess at a
download source.

```bash
git clone https://github.com/assafcaf/herdr-claude-setup
cd herdr-claude-setup

bash install.sh --dry-run     # read this first
bash install.sh
herdr integration install claude
```

Then merge `settings-fragment.json` into `~/.claude/settings.json` — **merge, never replace**;
that file also holds the machine's theme, permissions and auto-mode settings — and restart
Claude Code, since hooks and `CLAUDE.md` are read at session start.

`claude/skills/setup-herdr/SKILL.md` is the full procedure including verification, and it is
installed onto the machine too, so afterwards `/setup-herdr` can repair or re-run the setup
without the clone.

## What lands where

```
claude/          ->  ~/.claude/
  CLAUDE.md                            tells every session to spawn rather than call Agent
  scripts/herdr-spawn.sh               the spawner
  hooks/route-agent-to-herdr.sh        the PreToolUse(Agent) redirect
  hooks/json-field.sh                  its JSON parser — there is no jq on Windows
  skills/herdr-spawn/SKILL.md          spawn, drive, tear down
  skills/herdr/SKILL.md                Herdr's own CLI skill
  skills/setup-herdr/SKILL.md          this procedure
  statusline.ps1                       line 2: herdr workspace/tab/pane + session id
  subagent-statusline.ps1              one row per visible subagent
herdr/config.toml -> Herdr's config dir, only if the machine has none
```

`install.sh` backs up anything it would overwrite to `<file>.bak`, once, and skips files that
are already identical — so re-running it is a no-op.

## What it deliberately will not do

**Install Herdr.** No install source has been verified, so the skill stops and asks rather than
inventing a download URL.

**Rewrite `~/.claude/settings.json`.** An installer that overwrites it silently discards
whatever else the machine had. Unmerged keys are printed instead.

**Copy `herdr-agent-state.ps1`.** That file carries `HERDR_INTEGRATION_ID=claude` and is
overwritten whenever the integration updates — `herdr integration install claude` owns it. A
copy would go stale silently.

**Carry the `autoMode` block.** It is written by `/auto-mode-setup` against the environment it
finds; one machine's is wrong on another.

## Notes

`claude/skills/herdr/SKILL.md` is Herdr's own documentation, vendored here so a fresh machine
gets a working set in one clone. It is not this repo's work — check Herdr's licence before
redistributing it anywhere public.

The PowerShell status lines are Windows-only; `install.sh` skips them elsewhere. Everything else
is portable bash.
