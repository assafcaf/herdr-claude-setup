---
name: setup-herdr
description: "Set a machine up to run Claude Code agents as Herdr panes — install the spawner, the redirect hook, the skills and the status lines into ~/.claude, and wire Herdr's own Claude integration. Use when standing up a new machine, or repairing one where the spawner or the Agent redirect has stopped working."
disable-model-invocation: true
---

# Setting a machine up for Herdr-spawned agents

Reproduces, on any machine with this repo cloned, the setup where delegated agents run as
Herdr panes instead of in-process subagents. Everything installs under `~/.claude` and Herdr's
own config directory; nothing is written into the repo.

Four steps. Two you can run; two need the operator, and both are marked.

## 1. Herdr must already be installed — check, do not guess

```bash
herdr --version
```

If that fails, **stop and ask the operator to install Herdr**, then resume. Do not attempt an
install: no install source has been verified for this repo, and inventing a download URL or a
package name is exactly the kind of unverifiable claim that gets things wrong. The operator
knows where their copy came from.

If it succeeds, note the version and carry on. The rest is safe to place even without Herdr —
the hook stands down when `HERDR_ENV != 1` and the spawner refuses to run outside a pane — so
a machine can be prepared before Herdr arrives.

## 2. Copy the files

Two modes. `--user` installs into `~/.claude` and covers every project on the machine.
`--project <path>` adds it to one project's `.claude/`, beside whatever skills are already there.

```bash
bash install.sh --user --dry-run    # read this first
bash install.sh --user
```

Without a clone, `npx github:assafcaf/herdr-claude-setup` and
`uvx --from git+https://github.com/assafcaf/herdr-claude-setup herdr-claude-setup` take the same
flags — both are launchers around this same script.

Both modes install `scripts/herdr-spawn.sh`, `hooks/route-agent-to-herdr.sh` with its
`json-field.sh` parser, the `herdr-spawn` skill, and a `skills/herdr/SKILL.md` generated from
`herdr --skill` so it always matches the installed binary. `--user` adds `CLAUDE.md`, this skill,
the two PowerShell status lines (Windows only) and Herdr's `config.toml` if the machine has none
— all user-level concerns a project install leaves alone, and a project's own `CLAUDE.md` is
never overwritten.

In `--project` mode it asks where to wire the redirect: `.claude/settings.local.json` (yours
only, the default) or `.claude/settings.json` (committed, everyone). `--wire local|shared|none`
answers in advance; with no TTY it takes `local` without asking. **Choose `shared` only if the
whole team runs Herdr** — otherwise their `Agent` calls are refused with a pointer to a spawner
they cannot use. That merge is done with a real JSON parser and drops any previous copy of the
same hook, so re-running never stacks duplicates.

Anything it would overwrite is backed up to `<file>.bak` first, once. Identical files are
skipped, so re-running it is a no-op. In `--user` mode it never touches `settings.json`; that is
step 4.

## 3. Wire Herdr's Claude integration

```bash
herdr integration install claude
```

This is what makes Herdr recognise a Claude session in a pane and track its `idle` / `working` /
`blocked` state — it installs `~/.claude/hooks/herdr-agent-state.ps1` and the `SessionStart`
hook that calls it. That file carries `HERDR_INTEGRATION_ID=claude` and is overwritten whenever
the integration updates, which is why the payload does not ship a copy: a copied one would be
silently replaced, or worse, silently stale.

## 4. Merge the settings — operator confirms, and never replace the file

`~/.claude/settings.json` also holds that machine's theme, permissions and auto-mode
configuration. **Read it, then add the keys from `settings-fragment.json`,
substituting the machine's real home directory for `<HOME>`.** Show the operator the diff before
writing.

Three keys go in:

| Key | Effect |
|---|---|
| `hooks.PreToolUse` matcher `Agent` | refuses in-process subagents that write or run long, and points at the spawner |
| `statusLine` | line 2 shows the Herdr workspace/tab/pane and the Claude session id |
| `subagentStatusLine` | one row per visible subagent |

Merge into the existing arrays rather than assigning over them — a machine that already has a
`PreToolUse` entry (a project guard, say) must keep it. If `herdr integration install claude`
has already added a `SessionStart` hook, leave it exactly as it is.

The fragment's `_comment` key is documentation; do not copy it into `settings.json`.

## 5. Verify — do not report success without this

Restart Claude Code first: hooks and `CLAUDE.md` are read at session start, so nothing above
takes effect in the session that installed it.

Then, in a new session inside a Herdr pane:

```bash
printf '{"tool_input":{"subagent_type":"general-purpose"}}' | bash ~/.claude/hooks/route-agent-to-herdr.sh; echo "exit=$?"
```

Expect the block message and `exit=2`. Then check the live path — call the `Agent` tool with
`subagent_type: general-purpose` and confirm it is refused, and with `subagent_type: Explore`
and confirm it runs. A hook that is present but unwired fails exactly this test, and it is the
failure this whole setup is most likely to hit.

Finally, spawn one agent and let it answer for itself:

```bash
bash ~/.claude/scripts/herdr-spawn.sh probe --task setup-check \
  --orchestrator <this session's name from ListAgents> \
  --prompt "Reply to <that same name> with SendMessage, reporting your CC_TEAM_* env vars."
```

A reply that carries `CC_TEAM_ORCHESTRATOR` proves the whole chain: pane created, agent named,
env injected, and messaging live in both directions. Then `herdr tab close <tab_id>`.

## What this deliberately does not carry

The `autoMode` block in `settings.json` is per-machine and per-organisation — it is written by
`/auto-mode-setup` against the environment it finds. Do not copy one machine's autoMode onto
another; run `/auto-mode-setup` there instead.
