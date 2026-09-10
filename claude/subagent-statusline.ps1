# Claude Code subagent status line -- renders one row per visible subagent in the
# agent panel below the prompt. https://code.claude.com/docs/en/statusline
#
# stdin : { columns: <int>, tasks: [ { id, name, type, status, description,
#           label, startTime, model, effort, contextWindowSize, tokenCount, cwd } ] }
# stdout: one JSON line per row -- {"id":"<task id>","content":"<row body>"}
#         omit a task to keep its default row; empty content hides it.

$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$raw = [Console]::In.ReadToEnd()
try {
    $d = if ([string]::IsNullOrWhiteSpace($raw)) { $null } else { $raw | ConvertFrom-Json }
} catch { $d = $null }
if (-not $d -or -not $d.tasks) { exit 0 }

$E = [char]27
$R = "$E[0m"
$cols = if ($d.columns -as [int]) { [int]$d.columns } else { 120 }

function Tok([object]$n) {
    if ($null -eq $n) { return '' }
    $v = [double]$n
    if ($v -ge 1000000) { return ('{0:0.0}M' -f ($v / 1000000)) }
    if ($v -ge 1000)    { return ('{0:0.0}k' -f ($v / 1000)) }
    return [string][int]$v
}

foreach ($t in $d.tasks) {
    switch -Regex ("$($t.status)") {
        '^(running|working|in_progress|active)$' { $glyph = [char]0x25CF; $sc = '36' }
        '^(done|completed|success)$'             { $glyph = [char]0x2713; $sc = '32' }
        '^(error|failed|cancelled|canceled)$'    { $glyph = [char]0x2717; $sc = '31' }
        default                                  { $glyph = [char]0x25CB; $sc = '90' }
    }

    # identity: agent type, then the invocation's own label/name when it differs
    $who = if ($t.type) { "$($t.type)" } else { "$($t.name)" }
    $seg = @("$E[${sc}m$glyph$R", "$E[97m$who$R")

    $lbl = if ($t.label) { "$($t.label)" } else { "$($t.description)" }
    if ($lbl -and $lbl -ne $who) { $seg += "$E[90m$lbl$R" }

    $meta = @()
    if ($t.model)  { $meta += "$($t.model)" }
    if ($t.effort) { $meta += "$($t.effort)" }
    if ($t.tokenCount) {
        $tk = Tok $t.tokenCount
        if ($t.contextWindowSize) {
            $pc = [int][math]::Round(100 * ([double]$t.tokenCount / [double]$t.contextWindowSize))
            $tk += " ($pc%)"
        }
        $meta += $tk
    }
    if ($t.startTime) {
        try {
            $st = [double]$t.startTime
            $ms = if ($st -gt 1e12) { [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() - $st } else { ($DateTimeOffset = $null); ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - $st) * 1000 }
            if ($ms -gt 0) {
                $s = [int]($ms / 1000)
                $meta += if ($s -ge 60) { '{0}m{1:00}s' -f [int]($s / 60), ($s % 60) } else { "${s}s" }
            }
        } catch { }
    }
    if ($meta.Count) { $seg += "$E[94m" + ($meta -join "$E[90m " + [char]0x00B7 + " $E[94m") + $R }

    $content = $seg -join '  '

    # trim to the usable width, counting printable characters only
    $plain = [regex]::Replace($content, "$E\[[0-9;]*m", '')
    if ($plain.Length -gt $cols -and $cols -gt 3) {
        $keep = $cols - 1
        $out = ''; $n = 0; $i = 0
        while ($i -lt $content.Length -and $n -lt $keep) {
            if ($content[$i] -eq $E) {
                $j = $content.IndexOf('m', $i)
                if ($j -lt 0) { break }
                $out += $content.Substring($i, $j - $i + 1); $i = $j + 1
            } else {
                $out += $content[$i]; $i++; $n++
            }
        }
        $content = $out + [char]0x2026 + $R
    }

    [Console]::Out.WriteLine(([pscustomobject]@{ id = "$($t.id)"; content = $content } | ConvertTo-Json -Compress))
}
