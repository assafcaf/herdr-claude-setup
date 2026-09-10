#!/usr/bin/env bash
# Put this machine's ~/.claude into the shape the Herdr agent-spawning setup expects.
#
# What it does:      copies the files in ./claude/ into ~/.claude/, backing up anything it
#                    would overwrite, and drops herdr's config.toml if that machine has none.
# What it will not do: install Herdr (no verified install source — see the skill), and never
#                    rewrite ~/.claude/settings.json. That file is a merge, and an installer
#                    that overwrites it silently discards whatever else the machine had in it.
#                    Unmerged keys are printed at the end instead.
#
#   bash install.sh [--dry-run] [--force] [--claude-dir <path>]
#
#     --dry-run          print every action, change nothing
#     --force            overwrite without keeping a .bak (default keeps one, once)
#     --claude-dir <p>   install into <p> instead of ~/.claude; for testing the copy path
#                        against a scratch directory without touching the real one
#
# Re-running is safe: identical files are skipped, so a second run is a no-op.

set -u

SELF="setup-herdr"
SRC="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DEST="${HOME}/.claude"
dry=no
force=no
changed=0
skipped=0

mode=user
wire=ask
project_dir=""

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)    dry=yes; shift ;;
    --force)      force=yes; shift ;;
    --claude-dir) DEST="${2-}"; shift 2 ;;
    --user)       mode=user; shift ;;
    --project)
      mode=project
      case "${2-}" in ''|--*) project_dir="$PWD"; shift ;; *) project_dir="$2"; shift 2 ;; esac
      ;;
    --wire)       wire="${2-}"; shift 2 ;;
    -h|--help)    sed -n '2,32p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) printf '%s: unknown option %s\n' "$SELF" "$1" >&2; exit 2 ;;
  esac
done

case "$wire" in ask|local|shared|none) ;; *)
  printf '%s: --wire must be local, shared or none (got %s)\n' "$SELF" "$wire" >&2; exit 2 ;;
esac

if [ "$mode" = project ]; then
  [ -d "$project_dir" ] || { printf '%s: no such directory: %s\n' "$SELF" "$project_dir" >&2; exit 2; }
  DEST="$project_dir/.claude"
fi

say()  { printf '%s\n' "$*"; }
act()  { if [ "$dry" = yes ]; then printf '  would %s\n' "$*"; else printf '  %s\n' "$*"; fi; }
warn() { printf '%s: %s\n' "$SELF" "$*" >&2; }

[ -d "$SRC/claude" ] || { warn "payload missing: $SRC/claude"; exit 1; }

# --- Herdr itself -----------------------------------------------------------------------
# Checked, never installed. Nothing below depends on Herdr running, but all of it is inert
# without it: the hook stands down when HERDR_ENV != 1 and the spawner refuses to run.
if command -v herdr >/dev/null 2>&1; then
  say "herdr: $(herdr --version 2>/dev/null || echo 'present, version unknown')"
else
  warn "herdr is NOT on PATH. Install it first — see claude/skills/setup-herdr/SKILL.md; this script does"
  warn "not install it, because no install source has been verified for this repo."
  warn "Continuing: the Claude Code files below are safe to place now and stay inert."
fi

# --- Files ------------------------------------------------------------------------------
install_file() {
  local rel="$1" src="$SRC/claude/$1" dst="$DEST/$1"
  [ -f "$src" ] || { warn "missing from payload: $rel"; return 1; }

  if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
    skipped=$((skipped + 1))
    return 0
  fi

  if [ -f "$dst" ] && [ "$force" = no ]; then
    if [ ! -f "$dst.bak" ]; then
      act "back up $rel -> $rel.bak"
      [ "$dry" = yes ] || cp "$dst" "$dst.bak" || return 1
    else
      act "keep existing $rel.bak (not overwriting a previous backup)"
    fi
  fi

  act "install $rel"
  if [ "$dry" = no ]; then
    mkdir -p "$(dirname "$dst")" || return 1
    cp "$src" "$dst" || return 1
    case "$rel" in *.sh) chmod +x "$dst" ;; esac
  fi
  changed=$((changed + 1))
}

say ""
say "mode: $mode"
say "Claude Code files -> $DEST"

# The four that make spawning work. Both modes get these; the hook locates its own spawner
# and skill at runtime, so nothing here needs a path rewritten per mode.
install_file "scripts/herdr-spawn.sh"
install_file "hooks/route-agent-to-herdr.sh"
install_file "hooks/json-field.sh"
install_file "skills/herdr-spawn/SKILL.md"

# Herdr's own skill is generated, never vendored: `herdr --skill` prints the copy that matches
# the installed binary, so it cannot go stale and this repo does not redistribute it.
herdr_skill="$DEST/skills/herdr/SKILL.md"
if ! command -v herdr >/dev/null 2>&1; then
  say "  skipping skills/herdr/SKILL.md (herdr not on PATH; re-run once it is)"
elif [ -f "$herdr_skill" ] && herdr --skill 2>/dev/null | cmp -s - "$herdr_skill"; then
  skipped=$((skipped + 1))
else
  act "generate skills/herdr/SKILL.md (herdr --skill)"
  if [ "$dry" = no ]; then
    mkdir -p "$(dirname "$herdr_skill")"
    herdr --skill > "$herdr_skill" || warn "herdr --skill failed; skills/herdr/SKILL.md not written"
  fi
  changed=$((changed + 1))
fi

# User-level only. A project already has its own CLAUDE.md and its own status lines are not a
# per-project concern; overwriting either would be the installer taking something that is not
# its own.
if [ "$mode" = user ]; then
  install_file "skills/setup-herdr/SKILL.md"
  install_file "CLAUDE.md"

  # The status lines are PowerShell, so they are Windows-only. Everything else is portable.
  case "${OS:-}${OSTYPE:-}" in
    *Windows*|*msys*|*cygwin*)
      install_file "statusline.ps1"
      install_file "subagent-statusline.ps1"
      ;;
    *)
      say "  skipping statusline.ps1 / subagent-statusline.ps1 (PowerShell, Windows only)"
      ;;
  esac
else
  say "  skipping CLAUDE.md, status lines and setup-herdr (user-level only)"
fi

# --- Herdr's own config -----------------------------------------------------------------
# Only `onboarding = false`, which suppresses the first-run walkthrough. Written only when
# the machine has no config.toml at all — herdr owns this file and may keep more in it. Skipped
# entirely in project mode: installing into one project is no reason to touch machine config.
herdr_cfg=""
if [ "$mode" = user ]; then
  case "${OS:-}${OSTYPE:-}" in
    *Windows*|*msys*|*cygwin*) [ -n "${APPDATA:-}" ] && herdr_cfg="$APPDATA/herdr/config.toml" ;;
    *) herdr_cfg="${XDG_CONFIG_HOME:-$HOME/.config}/herdr/config.toml" ;;
  esac
fi

say ""
if [ "$mode" = project ]; then
  say "herdr config: skipped (project mode does not touch machine config)"
elif [ -z "$herdr_cfg" ]; then
  say "herdr config: skipped (could not determine the config directory on this platform)"
elif [ -f "$herdr_cfg" ]; then
  say "herdr config: already exists, left alone -> $herdr_cfg"
else
  act "write $herdr_cfg"
  if [ "$dry" = no ]; then
    mkdir -p "$(dirname "$herdr_cfg")" && cp "$SRC/herdr/config.toml" "$herdr_cfg"
  fi
fi

# --- Wiring the hook ---------------------------------------------------------------------
# Only in project mode. At user level the fragment goes into ~/.claude/settings.json, which
# also holds theme, permissions and auto-mode config; that one stays a reviewed manual merge.
#
# The merge itself is done by a real JSON parser (node, else python3) and never by text
# munging — settings.json is the file most likely to already hold something that matters. If
# neither is available the entry is printed for a human instead of guessed at.
wire_hook() {
  local target="$1" cmd="$2"

  if [ "$dry" = yes ]; then
    act "wire PreToolUse(Agent) into $target"
    return 0
  fi

  mkdir -p "$(dirname "$target")"
  [ -f "$target" ] || printf '{}\n' > "$target"

  if command -v node >/dev/null 2>&1; then
    node -e '
      const fs = require("fs"), [p, cmd] = process.argv.slice(1);
      let j = {};
      try { j = JSON.parse(fs.readFileSync(p, "utf8") || "{}"); } catch (e) {
        console.error("existing JSON is not parseable: " + e.message); process.exit(3);
      }
      j.hooks = j.hooks || {};
      const arr = Array.isArray(j.hooks.PreToolUse) ? j.hooks.PreToolUse : [];
      // Drop any previous install of this same hook, so re-running does not stack duplicates.
      const kept = arr.filter(e => !JSON.stringify(e).includes("route-agent-to-herdr"));
      kept.push({ matcher: "Agent", hooks: [{ type: "command", command: cmd,
                  timeout: 15, statusMessage: "Routing delegated work to Herdr" }] });
      j.hooks.PreToolUse = kept;
      fs.writeFileSync(p, JSON.stringify(j, null, 2) + "\n");
    ' "$target" "$cmd" || return 1
  elif command -v python3 >/dev/null 2>&1; then
    python3 - "$target" "$cmd" <<'PY' || return 1
import json, sys
p, cmd = sys.argv[1], sys.argv[2]
try:
    j = json.load(open(p)) or {}
except Exception as e:
    sys.exit("existing JSON is not parseable: %s" % e)
hooks = j.setdefault("hooks", {})
arr = hooks.get("PreToolUse") or []
kept = [e for e in arr if "route-agent-to-herdr" not in json.dumps(e)]
kept.append({"matcher": "Agent", "hooks": [{"type": "command", "command": cmd,
             "timeout": 15, "statusMessage": "Routing delegated work to Herdr"}]})
hooks["PreToolUse"] = kept
open(p, "w").write(json.dumps(j, indent=2) + "\n")
PY
  else
    warn "neither node nor python3 found — not editing $target by hand."
    warn "Add this to its hooks.PreToolUse array yourself:"
    warn '  {"matcher":"Agent","hooks":[{"type":"command","command":"'"$cmd"'","timeout":15}]}'
    return 1
  fi

  act "wired PreToolUse(Agent) -> $target"
}

wired=""
if [ "$mode" = project ]; then
  say ""
  if [ "$wire" = ask ]; then
    if [ -t 0 ]; then
      say "Where should the Agent redirect be wired?"
      say "  1) .claude/settings.local.json  — yours only, gitignored     [default]"
      say "  2) .claude/settings.json        — committed, shared with the project"
      say "  3) nowhere                      — install the files, wire it later"
      printf '  choice [1]: '
      read -r choice
      case "$choice" in 2) wire=shared ;; 3) wire=none ;; *) wire=local ;; esac
    else
      # Unattended (npx in a script, CI): choose the option that cannot surprise a teammate.
      wire=local
      say "not a terminal — defaulting to --wire local (settings.local.json)"
    fi
  fi

  hook_cmd="bash \"\${CLAUDE_PROJECT_DIR}/.claude/hooks/route-agent-to-herdr.sh\""
  case "$wire" in
    local)  wire_hook "$DEST/settings.local.json" "$hook_cmd" && wired="$DEST/settings.local.json" ;;
    shared) wire_hook "$DEST/settings.json"       "$hook_cmd" && wired="$DEST/settings.json" ;;
    none)   say "  not wiring the hook (--wire none)" ;;
  esac
fi

# --- What is left for a human ------------------------------------------------------------
say ""
say "Installed: $changed file(s); already current: $skipped"
say ""
if [ "$mode" = project ]; then
  [ -n "$wired" ] && say "Wired: $wired"
  say ""
  say "One step remains, and it is machine-level, not per-project:"
  say ""
  say "  herdr integration install claude"
  say "     Lets Herdr track this session's idle/working/blocked state. Verified idempotent:"
  say "     re-running it leaves settings.json and the hook byte-identical."
  say ""
  if [ "$wire" = shared ]; then
    say "You chose the committed settings.json, so everyone on this project gets the redirect."
    say "The hook no-ops outside Herdr, so it is harmless for teammates who do not run it —"
    say "but it is also useless to them, and their Agent calls will be refused."
    say ""
  fi
else
  say "Two steps remain, neither of which this script will do:"
  say ""
  say "  1. herdr integration install claude"
  say "     Installs ~/.claude/hooks/herdr-agent-state.ps1 and its SessionStart hook. That file"
  say "     is managed by herdr and is overwritten on every integration update, so it is not"
  say "     copied from this payload."
  say ""
  say "  2. Merge settings-fragment.json into ~/.claude/settings.json,"
  say "     replacing <HOME> with: $HOME"
  say "     It adds the PreToolUse(Agent) hook and the two status lines. Merge, do not replace:"
  say "     that file also holds this machine's theme, permissions and auto-mode settings."
  say ""
fi
say "Then restart Claude Code — hooks and CLAUDE.md are read at session start."
