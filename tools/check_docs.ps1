# check_docs.ps1 -- documentation consistency gate for the open-box design docs.
#
# Checks every .md under docs/ (archive/ excluded unless -IncludeArchive):
#   1. encoding      : UTF-8 without BOM
#   2. line endings  : pure LF (zero CR bytes)
#   3. length budget : docs/systems/*.md must stay <= -MaxSystemDocLines
#   4. stale names   : identifiers that must not survive the v0.10 rename
#
# Exit code 0 = no FAIL. WARN items are reported but never fail the run.
#
# ---------------------------------------------------------------------------
# ASCII-only source on purpose. Windows PowerShell 5.1 decodes a BOM-less
# UTF-8 .ps1 file as ANSI, so any non-ASCII literal in this file would be
# mojibake by the time it is parsed. Chinese patterns are therefore written
# as \uXXXX regex escapes -- .NET regex expands those, PowerShell never sees
# the character.
# ---------------------------------------------------------------------------

[CmdletBinding()]
param(
    [string]$Root = '',
    [switch]$IncludeArchive,
    [int]$MaxSystemDocLines = 600
)

$ErrorActionPreference = 'Continue'

# Resolve the repo root inside the body, not in a param() default:
# Windows PowerShell 5.1 does not bind $PSScriptRoot early enough for that.
if ([string]::IsNullOrEmpty($Root)) {
    $scriptPath = $PSCommandPath
    if ([string]::IsNullOrEmpty($scriptPath)) { $scriptPath = $MyInvocation.MyCommand.Path }
    $Root = Split-Path -Parent (Split-Path -Parent $scriptPath)
}

# Patterns that must have ZERO occurrences in a shipped doc.
# Keep these unambiguous: a pattern that also matches legitimate prose will
# make the gate cry wolf and get ignored.
$failPatterns = [ordered]@{
    'stale Box field: Box.pool_state'          = '(?i)box\.pool_state'
    'stale C4 target: pool_state.socket_count' = 'pool_state\.socket_count'
    'stale signature: socket(module)'          = 'socket\(module\)'
    'stale signature: unsocket(slot)'          = 'unsocket\(slot\)'
    'stale signature: compute(state)'          = 'compute\(state\)'
}

# Patterns that are legitimate in a few places (changelogs, explicit
# "this shape was rejected" notes, or a parameter that legitimately keeps
# the name -- e.g. 07's evaluate_pool(pool_state, series)).
# Review the listed lines by hand.
$warnPatterns = [ordered]@{
    'bare pool_state (may be 07 param name)'   = '(?<!get_)(?<!item_)pool_state'
    'pool_state(series_id): stale call, OR a deliberate "this replaced the old call" note -- read the line' = 'pool_state\(series_id'
    'rejected shape: PoolState.socketed'       = 'PoolState\.socketed'
    'res://scenes/: stale path, OR a deliberate "this path was retired/migrated" note -- read the line' = 'res://scenes/'
    'v0.11 removed: pity (may be a "removed in v0.11" note -- read the line)' = 'pity'
    'v0.11 removed: \u4fdd\u5e95 (ALSO means "floor/guarantee" e.g. C6 -- read the line)' = '\u4fdd\u5e95'
    'roll(series_id, ...): series_id may legitimately ride along as LOG METADATA (not a pool selector) -- read the line' = 'roll\(series_id'
    'per-series wording: \u6bcf\u5957\u7cfb\u5e38\u91cf' = '\u6bcf\u5957\u7cfb.{0,2}\u5e38\u91cf'
}

function Get-MatchLineNumbers {
    param([string]$Text, [string]$Pattern)
    $result = @()
    foreach ($m in [regex]::Matches($Text, $Pattern)) {
        $prefix = $Text.Substring(0, $m.Index)
        $result += ([regex]::Matches($prefix, "`n")).Count + 1
    }
    return $result
}

$docsRoot = Join-Path $Root 'docs'
if (-not (Test-Path $docsRoot)) {
    Write-Output "FAIL: docs/ not found under $Root"
    exit 2
}

$files = Get-ChildItem -Path $docsRoot -Recurse -Filter *.md | Where-Object {
    $IncludeArchive -or ($_.FullName -notmatch '\\archive\\')
} | Sort-Object FullName

$failCount = 0
$warnCount = 0
$failFiles = @()

Write-Output "=== open-box doc check ==="
Write-Output "root: $Root"
Write-Output ("files: {0}{1}" -f $files.Count, $(if ($IncludeArchive) { ' (archive included)' } else { ' (archive excluded)' }))
Write-Output ''

foreach ($f in $files) {
    $rel = $f.FullName.Substring($Root.Length).TrimStart('\', '/')
    $raw = Get-Content -Path $f.FullName -Raw -Encoding UTF8
    if ($null -eq $raw) { $raw = '' }

    $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $crCount = ([regex]::Matches($raw, "`r")).Count
    $lfCount = ([regex]::Matches($raw, "`n")).Count

    $problems = @()
    $warnings = @()

    if ($hasBom) { $problems += 'UTF-8 BOM present (must be BOM-less)' }
    if ($crCount -gt 0) { $problems += "found $crCount CR byte(s); must be pure LF" }

    $isSystemDoc = ($rel -match 'systems[\\/]') -and ($rel -notmatch 'README\.md$')
    if ($isSystemDoc -and $lfCount -gt $MaxSystemDocLines) {
        $problems += "length $lfCount lines exceeds budget $MaxSystemDocLines"
    }

    foreach ($name in $failPatterns.Keys) {
        $hits = Get-MatchLineNumbers -Text $raw -Pattern $failPatterns[$name]
        if ($hits.Count -gt 0) {
            $problems += ("{0} -> line(s) {1}" -f $name, ($hits -join ', '))
        }
    }

    foreach ($name in $warnPatterns.Keys) {
        $hits = Get-MatchLineNumbers -Text $raw -Pattern $warnPatterns[$name]
        if ($hits.Count -gt 0) {
            $warnings += ("{0} -> line(s) {1}" -f $name, ($hits -join ', '))
        }
    }

    $status = 'PASS'
    if ($warnings.Count -gt 0) { $status = 'WARN' }
    if ($problems.Count -gt 0) { $status = 'FAIL'; $failCount++; $failFiles += $rel }
    if ($status -eq 'WARN') { $warnCount++ }

    Write-Output ("[{0}] {1}  ({2} lines, cr={3}, bom={4})" -f $status, $rel, $lfCount, $crCount, $(if ($hasBom) { 'yes' } else { 'no' }))
    foreach ($p in $problems) { Write-Output ("        FAIL: {0}" -f $p) }
    foreach ($w in $warnings) { Write-Output ("        warn: {0}" -f $w) }
}

# ---------------------------------------------------------------------------
# Cross-reference integrity.
#
# A name-based gate cannot see a citation that resolves to nothing: a doc can
# say "see D14" while the core never defines D14. That is exactly how D14 went
# missing for several versions (cited by core R13, 07 and 10, covered by
# "D1-D14 unchanged", yet absent from the core decision table).
#
# Definitions are derived from core's own sections, so adding P8 / R15 / D18 to
# core needs no change here. Citation ids are matched without a leading zero,
# so per-document local ids such as P09-13 are not mistaken for pillars.
# ---------------------------------------------------------------------------
$corePath = Join-Path $docsRoot 'core-design.md'
if (Test-Path $corePath) {
    $coreRaw = Get-Content -Path $corePath -Raw -Encoding UTF8

    function Get-CoreSectionText {
        param([string]$Text, [string]$Heading)
        $start = [regex]::Match($Text, "(?m)^## " + $Heading + "\. ")
        if (-not $start.Success) { return '' }
        $rest = $Text.Substring($start.Index + $start.Length)
        $next = [regex]::Match($rest, "(?m)^## ")
        if ($next.Success) { return $rest.Substring(0, $next.Index) }
        return $rest
    }

    $defined = @{}
    $defined['P'] = @([regex]::Matches((Get-CoreSectionText $coreRaw '7'),  '(?m)^### (P\d+)')          | ForEach-Object { $_.Groups[1].Value })
    $defined['R'] = @([regex]::Matches((Get-CoreSectionText $coreRaw '12'), '\*\*(R\d+)\*\*')           | ForEach-Object { $_.Groups[1].Value })
    $defined['D'] = @([regex]::Matches((Get-CoreSectionText $coreRaw '15'), '\*\*(D\d+)\*\*')           | ForEach-Object { $_.Groups[1].Value })

    Write-Output ''
    Write-Output ("=== cross-reference map (defined in core) ===")
    foreach ($k in @('P','R','D')) {
        $ids = $defined[$k] | Sort-Object { [int]($_ -replace '^[PRD]','') }
        Write-Output ("  {0}: {1}" -f $k, ($ids -join ' '))
    }

    $xrefProblems = @()
    foreach ($f in $files) {
        $rel = $f.FullName.Substring($Root.Length).TrimStart('\', '/')
        $text = Get-Content -Path $f.FullName -Raw -Encoding UTF8
        if ($null -eq $text) { continue }
        foreach ($m in [regex]::Matches($text, '\b([PRD][1-9]\d*)\b')) {
            $id = $m.Groups[1].Value
            $fam = $id.Substring(0, 1)
            $num = [int]($id.Substring(1))
            $set = $defined[$fam]
            if ($set.Count -eq 0) { continue }
            $maxDefined = ($set | ForEach-Object { [int]($_ -replace '^[PRD]','') } | Measure-Object -Maximum).Maximum
            if ($set -contains $id) { continue }
            $line = ([regex]::Matches($text.Substring(0, $m.Index), "`n")).Count + 1
            if ($num -le $maxDefined) {
                $xrefProblems += ("{0}: {1} cited at line {2} but NOT defined in core" -f $rel, $id, $line)
            } else {
                $xrefProblems += ("{0}: {1} cited at line {2} is beyond the highest defined {3}" -f $rel, $id, $line, $fam)
            }
        }
    }

    # Section citations: "core section 12.3" must resolve to a heading in core.
    #
    # These docs also use the idiom "core section 14.2.7" to mean "section 14.2,
    # numbered item 7" (core 14.2 is a numbered list of iron rules). So a
    # citation may name a numbered ITEM rather than a heading: accept the
    # longest dot-prefix of the citation that IS a heading.
    $headings = @{}
    foreach ($m in [regex]::Matches($coreRaw, '(?m)^#{2,4}\s+(\d+(?:\.\d+)*)')) { $headings[$m.Groups[1].Value] = $true }
    foreach ($f in $files) {
        $rel = $f.FullName.Substring($Root.Length).TrimStart('\', '/')
        $text = Get-Content -Path $f.FullName -Raw -Encoding UTF8
        if ($null -eq $text) { continue }
        foreach ($m in [regex]::Matches($text, '\u6838\u5fc3(?:\u8bbe\u8ba1\u4e66)?\s*\u00a7\s*(\d+(?:\.\d+)*)')) {
            $sec = $m.Groups[1].Value
            $parts = $sec.Split('.')
            $resolved = $false
            for ($k = $parts.Count; $k -ge 1; $k--) {
                if ($headings.ContainsKey(($parts[0..($k - 1)] -join '.'))) { $resolved = $true; break }
            }
            if (-not $resolved) {
                $line = ([regex]::Matches($text.Substring(0, $m.Index), "`n")).Count + 1
                $xrefProblems += ("{0}: core section {1} cited at line {2} -- no matching heading in core" -f $rel, $sec, $line)
            }
        }
    }

    # System-doc file references must resolve to a file that exists.
    # Safety net for renaming/renumbering system docs: a stale "06-conversion.md"
    # left behind after a renumber is invisible to every other check here.
    # Files renamed in an EARLIER version may legitimately appear in history
    # notes ("02-material.md" was merged into "02-item.md" in v0.7, and the
    # changelog says so). Exempt only names that are known to be historical --
    # anything else that does not resolve is a real dangling reference.
    $historicalFileNames = @('02-material.md')
    foreach ($f in $files) {
        $rel = $f.FullName.Substring($Root.Length).TrimStart('\', '/')
        $text = Get-Content -Path $f.FullName -Raw -Encoding UTF8
        if ($null -eq $text) { continue }
        foreach ($m in [regex]::Matches($text, '([0-9]{2})-([a-z0-9\-]+)\.md')) {
            $target = $m.Groups[0].Value
            if ($target -eq 'core-design.md') { continue }
            if ($historicalFileNames -contains $target) { continue }
            if (-not (Test-Path (Join-Path $docsRoot ('systems\' + $target)))) {
                $line = ([regex]::Matches($text.Substring(0, $m.Index), "`n")).Count + 1
                $xrefProblems += ("{0}: references '{1}' at line {2} -- no such file in docs/systems/" -f $rel, $target, $line)
            }
        }
    }

    if ($xrefProblems.Count -eq 0) {
        Write-Output '  cross-references: all cited P/R/D ids resolve'
    } else {
        Write-Output '  cross-references:'
        foreach ($p in ($xrefProblems | Sort-Object -Unique)) {
            Write-Output ("        FAIL: {0}" -f $p)
        }
        # Counted once per RUN, not per problem: the summary compares against the
        # number of FILES, so counting every problem would make PASS go negative.
        $failCount++
        $failFiles += 'cross-reference'
    }
} else {
    Write-Output ''
    Write-Output '  WARN: core-design.md not found; cross-reference check skipped'
    $warnCount++
}

Write-Output ''
Write-Output ("=== summary: {0} FAIL, {1} WARN, {2} PASS ===" -f $failCount, $warnCount, ($files.Count - $failCount - $warnCount))
if ($failCount -gt 0) {
    Write-Output ("failing files: {0}" -f ($failFiles -join ', '))
    Write-Output 'DOC CHECK FAILED'
    exit 1
}
Write-Output 'DOC CHECK PASSED'
exit 0
