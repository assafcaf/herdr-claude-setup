# Claude Code status line.
#   Line 1: git branch (+dirty/ahead/behind), worktree, model/effort, context usage
#   Line 2: herdr workspace/tab/pane, agent + Claude session id, session name
#
# Input: session JSON on stdin -- https://code.claude.com/docs/en/statusline
# herdr coordinates come from the env herdr exports into the pane
# (HERDR_WORKSPACE_ID / HERDR_TAB_ID / HERDR_PANE_ID), so they cost no subprocess.

$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$raw = [Console]::In.ReadToEnd()
try {
    $d = if ([string]::IsNullOrWhiteSpace($raw)) { $null } else { $raw | ConvertFrom-Json }
} catch { $d = $null }

$E = [char]27
$R = "$E[0m"
function Col([string]$c, [string]$t) { if ([string]::IsNullOrEmpty($t)) { '' } else { "$E[${c}m$t$R" } }
$SEP = "$E[90m  $([char]0x2502)  $R"

# ------------------------------------------------------------------ line 1
$dir = $d.workspace.current_dir
if (-not $dir) { $dir = $d.cwd }
if (-not $dir) { $dir = (Get-Location).Path }

$branch = ''; $dirty = $false; $ab = ''
$gs = @(& git -C "$dir" status --porcelain=v1 --branch --untracked-files=normal 2>$null)
if ($gs.Count -gt 0 -and $gs[0].StartsWith('## ')) {
    $head = $gs[0].Substring(3)
    if ($head -match '\[(?<ab>[^\]]+)\]\s*$') {
        $t = $Matches['ab'] -replace 'ahead ', [char]0x2191 -replace 'behind ', [char]0x2193
        $ab = $t -replace ',\s*', ' '
        $head = $head -replace '\s*\[[^\]]+\]\s*$', ''
    }
    $branch = ($head -split '\.\.\.')[0].Trim()
    if ($branch -eq 'HEAD (no branch)') {
        $sha = & git -C "$dir" rev-parse --short HEAD 2>$null
        $branch = if ($sha) { "detached@$sha" } else { 'detached' }
    }
    $dirty = $gs.Count -gt 1
}

$l1 = @()
if ($branch) {
    $b = "$E[32m$([char]0x2387) $branch"
    if ($dirty) { $b += "$E[33m*" }
    if ($ab)    { $b += "$E[36m $ab" }
    $l1 += ($b + $R)
}

$wt = $d.worktree.name
if (-not $wt) { $wt = $d.workspace.git_worktree }
if ($wt) { $l1 += Col '35' "wt:$wt" }

if ($d.model.display_name) {
    $m = "$E[94m$($d.model.display_name)"
    if ($d.effort.level) { $m += "$E[90m/$E[94m$($d.effort.level)" }
    $l1 += ($m + $R)
}

$pct = $d.context_window.used_percentage
if ($null -ne $pct) {
    $p = [int][math]::Round([double]$pct)
    $c = if ($p -ge 80) { '31' } elseif ($p -ge 60) { '33' } else { '90' }
    $l1 += Col $c "ctx $p%"
}

# ------------------------------------------------------------------ line 2
$l2 = @()
if ($env:HERDR_PANE_ID) {
    # HERDR_PANE_ID is "w1:p1", HERDR_TAB_ID is "w1:t1" -- drop the repeated workspace.
    $tab  = ($env:HERDR_TAB_ID  -split ':')[-1]
    $pane = ($env:HERDR_PANE_ID -split ':')[-1]
    $ws   = if ($env:HERDR_WORKSPACE_ID) { $env:HERDR_WORKSPACE_ID } else { ($env:HERDR_PANE_ID -split ':')[0] }
    $l2 += Col '36' ("herdr " + ((@($ws, $tab, $pane) | Where-Object { $_ }) -join '/'))
}

$who = $d.agent.name
if (-not $who) { $who = 'claude' }
$id = "$E[95m$who"
if ($d.session_id) { $id += "$E[90m:$E[95m" + $d.session_id.Substring(0, [math]::Min(8, $d.session_id.Length)) }
$l2 += ($id + $R)

if ($d.session_name) { $l2 += Col '90' $d.session_name }

# ------------------------------------------------------------------ emit
$out = @()
if ($l1.Count) { $out += ($l1 -join $SEP) }
if ($l2.Count) { $out += ($l2 -join $SEP) }
[Console]::Out.Write(($out -join "`n"))
