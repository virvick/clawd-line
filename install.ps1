#!/usr/bin/env pwsh
# ============================================================================
# clawd-line installer (Windows / PowerShell)
# ============================================================================
# No bash, jq, or Git required - clawd-line.ps1 is a native PowerShell port.
# Copies clawd-line.ps1 into ~/.claude/ and points Claude Code's statusLine
# at it, merging into settings.json without touching any other key. Safe to
# re-run: it only ever replaces the "statusLine" property and takes a
# timestamped backup of settings.json first.
#
# Works both ways:
#   irm https://raw.githubusercontent.com/virvick/clawd-line/main/install.ps1 | iex
#   git clone https://github.com/virvick/clawd-line.git; cd clawd-line; ./install.ps1
# In piped mode there's no local sibling file to copy from, so it downloads
# clawd-line.ps1 from the same raw URL instead.
# ============================================================================

$ErrorActionPreference = 'Stop'

$RepoRawBase = 'https://raw.githubusercontent.com/virvick/clawd-line/main'
$ClaudeDir = Join-Path $HOME '.claude'
$Settings = Join-Path $ClaudeDir 'settings.json'
$TargetScript = Join-Path $ClaudeDir 'clawd-line.ps1'

Write-Host 'clawd-line installer'
Write-Host '====================='

New-Item -ItemType Directory -Force -Path $ClaudeDir | Out-Null

$localScript = if ($PSScriptRoot) { Join-Path $PSScriptRoot 'clawd-line.ps1' } else { $null }

if ($localScript -and (Test-Path -LiteralPath $localScript)) {
    Write-Host "Copying clawd-line.ps1 to $ClaudeDir\..."
    Copy-Item -LiteralPath $localScript -Destination $TargetScript -Force
} else {
    Write-Host "Downloading clawd-line.ps1 to $ClaudeDir\..."
    Invoke-WebRequest -Uri "$RepoRawBase/clawd-line.ps1" -OutFile $TargetScript
}

$scriptPathForward = $TargetScript -replace '\\', '/'
$statusLineCommand = "pwsh -NoProfile -File `"$scriptPathForward`""

if (Test-Path -LiteralPath $Settings) {
    $backup = "$Settings.bak.$(Get-Date -Format 'yyyyMMddHHmmss')"
    Copy-Item -LiteralPath $Settings -Destination $backup
    Write-Host "Existing settings.json backed up to $backup"
    $settingsObj = Get-Content -LiteralPath $Settings -Raw | ConvertFrom-Json -Depth 20
} else {
    $settingsObj = [pscustomobject]@{}
}

$statusLine = [pscustomobject]@{
    type            = 'command'
    command         = $statusLineCommand
    refreshInterval = 1
}

# Add (or replace, if already present) the statusLine property without
# disturbing anything else in settings.json.
if ($settingsObj.PSObject.Properties.Name -contains 'statusLine') {
    $settingsObj.statusLine = $statusLine
} else {
    $settingsObj | Add-Member -NotePropertyName 'statusLine' -NotePropertyValue $statusLine
}

$settingsObj | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $Settings -Encoding utf8

Write-Host "Done. statusLine now points at $TargetScript."
Write-Host 'Restart Claude Code (or open a new session) to see it.'
