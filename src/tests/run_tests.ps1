# Runs the item-system acceptance tests (02-item.md section 10).
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File src/tests/run_tests.ps1
#
# Exit code 0 = all green. Set $env:GODOT_BIN to point at a Godot 4.5 console build.
#
# NOTE: this file is deliberately ASCII-only.
# Windows PowerShell 5.1 reads a UTF-8 file *without* BOM as ANSI, which turns any
# non-ASCII character in a .ps1 into mojibake and breaks the parser. Keeping this
# script ASCII-only sidesteps that entirely. (Chinese notes live in the .gd files,
# which Godot reads as UTF-8 correctly. This script also reads the Godot log with
# -Encoding UTF8 for the same reason.)

# NOTE: must stay 'Continue', not 'Stop'.
# Windows PowerShell 5.1 turns anything a native command writes to stderr into a
# *terminating* error when ErrorActionPreference is 'Stop'. Godot always writes its
# startup warning (root certificate store) to stderr, so 'Stop' would abort the run
# before the tests even execute and mask the real exit code.
$ErrorActionPreference = 'Continue'

$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)   # src/tests -> project root

$godot = $env:GODOT_BIN
if (-not $godot) {
    $godot = 'C:\Users\zuiyu\Documents\dev\godot\4.5\Godot_v4.5.1-stable_win64_console.exe'
}
if (-not (Test-Path $godot)) {
    Write-Error "Godot executable not found. Set GODOT_BIN to a Godot 4.5 console build."
}

$runtime = Join-Path $root '_runtime'
New-Item -ItemType Directory -Force -Path (Join-Path $runtime 'appdata') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $runtime 'temp')    | Out-Null
$env:APPDATA      = Join-Path $runtime 'appdata'
$env:LOCALAPPDATA = Join-Path $runtime 'appdata'
$env:TEMP         = Join-Path $runtime 'temp'
$env:TMP          = Join-Path $runtime 'temp'

# Test scenes to run. Add one line per system as they land.
$scenes = @(
    'res://src/items/tests/test_item_system.tscn',
    'res://src/gacha/pool/tests/test_item_pool.tscn',
    'res://src/gacha/pool/tests/test_pool_service.tscn',
    'res://src/gacha/tests/test_gacha_service.tscn',
    'res://src/gacha/tests/test_box_uses.tscn'
)
$timeoutMs = 120000

$log  = Join-Path $runtime 'test_output.txt'
$errl = Join-Path $runtime 'test_stderr.txt'
$worst = 0
$totalPass = 0
$totalFail = 0

foreach ($scene in $scenes) {
    Write-Host "--- $scene"
    $p = Start-Process -FilePath $godot `
        -ArgumentList @('--headless', '--path', $root, $scene) `
        -RedirectStandardOutput $log -RedirectStandardError $errl `
        -PassThru -NoNewWindow

    # A scene that fails to load never reaches get_tree().quit(), so Godot would
    # hang forever. Always bound the wait.
    if (-not $p.WaitForExit($timeoutMs)) {
        Write-Host "TIMEOUT after $($timeoutMs) ms -- killing" -ForegroundColor Red
        try { $p.Kill() } catch {}
        $worst = 1
        Get-Content $errl -Encoding UTF8 -ErrorAction SilentlyContinue |
            Where-Object { $_ -notmatch 'root certificate store' } | Select-Object -First 15
        continue
    }

    # $p.ExitCode is deliberately NOT used anywhere below: with -RedirectStandardOutput,
    # PowerShell 5.1's Start-Process -PassThru leaves it EMPTY (not 0), and an empty
    # value compares as -ne 0 -- trusting it would flag every green run as failed.
    # The test's own summary line is the single source of truth instead.

    # Engine noise expected under the sandbox (the TLS warning appears because
    # APPDATA was redirected) and PowerShell's own error formatting.
    Get-Content $log -Encoding UTF8 -ErrorAction SilentlyContinue | Where-Object {
        $_ -notmatch 'root certificate store' -and
        $_ -notmatch 'get_system_ca_certificates' -and
        $_ -notmatch '^\s*at line:' -and
        $_ -notmatch '^\s*at:' -and
        $_ -notmatch '\.ps1:\d+ char:' -and
        $_ -notmatch '^\s*\+' -and
        $_ -notmatch 'CategoryInfo' -and
        $_ -notmatch 'FullyQualifiedErrorId'
    }

    $text = Get-Content $log -Encoding UTF8 -Raw -ErrorAction SilentlyContinue
    $m = [regex]::Match($text, [char]0x7ED3 + [char]0x679C + [char]0xFF1A + '(\d+)' + [char]0x0020 + [char]0x901A + [char]0x8FC7 + ' / (\d+)')
    if (-not $m.Success) {
        Write-Host 'NO SUMMARY LINE -- the scene probably failed to load (stderr below)' -ForegroundColor Red
        Get-Content $errl -Encoding UTF8 -ErrorAction SilentlyContinue |
            Where-Object { $_ -notmatch 'root certificate store' } | Select-Object -First 15
        $worst = 1
        continue
    }
    $totalPass += [int]$m.Groups[1].Value
    $totalFail += [int]$m.Groups[2].Value
}

Write-Host ''
if ($totalFail -gt 0 -or $worst -ne 0) { $worst = 1 } else { $worst = 0 }
Write-Host ("TOTAL: {0} passed / {1} failed" -f $totalPass, $totalFail)
if ($worst -eq 0) { Write-Host 'TESTS PASSED (exit 0)' }
else              { Write-Host 'TESTS FAILED (exit 1)' }
exit $worst
