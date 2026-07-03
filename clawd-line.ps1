#!/usr/bin/env pwsh
# ============================================================================
# clawd-line - native PowerShell port (Windows, no bash/jq/git required)
# https://github.com/virvick/clawd-line
# ============================================================================
# Same 5-line layout and Clawd mascot as clawd-line.sh - see that file's
# header for the full description. This port re-implements every piece
# natively: JSON parsing (ConvertFrom-Json), git branch (reads .git/HEAD
# directly, no `git` binary needed), and the mascot/gradient bar rendering
# logic line-for-line equivalent to the bash version.
# ============================================================================

$ErrorActionPreference = 'Stop'
$ESC = [char]27

# ----------------------------------------------------------------------
# Read + parse stdin JSON
# ----------------------------------------------------------------------
$rawInput = [Console]::In.ReadToEnd()
try { $Json = $rawInput | ConvertFrom-Json -Depth 20 } catch { $Json = $null }

function Get-Prop {
    param($Obj, [string]$Path, $Default)
    $cur = $Obj
    foreach ($seg in ($Path -split '\.')) {
        if ($null -eq $cur) { return $Default }
        $cur = $cur.$seg
    }
    if ($null -eq $cur) { return $Default }
    return $cur
}

$Model          = Get-Prop $Json 'model.display_name' 'Unknown'
$CurrentDir     = Get-Prop $Json 'workspace.current_dir' '.'
$ContextSize    = [int](Get-Prop $Json 'context_window.context_window_size' 200000)
$CurrentUsage   = Get-Prop $Json 'context_window.current_usage' $null
$TotalCost      = [double](Get-Prop $Json 'cost.total_cost_usd' 0)

$FiveHourPct    = Get-Prop $Json 'rate_limits.five_hour.used_percentage' $null
$FiveHourReset  = Get-Prop $Json 'rate_limits.five_hour.resets_at' $null
$SevenDayPct    = Get-Prop $Json 'rate_limits.seven_day.used_percentage' $null
$SevenDayReset  = Get-Prop $Json 'rate_limits.seven_day.resets_at' $null

$TranscriptPath = Get-Prop $Json 'transcript_path' $null
$Effort         = Get-Prop $Json 'effort.level' $null
$ThinkingOn     = Get-Prop $Json 'thinking.enabled' $null

# ----------------------------------------------------------------------
# Colors
# ----------------------------------------------------------------------
function Reset        { "$ESC[0m" }
function Bold         { "$ESC[1m" }
function CatTeal       { "$ESC[38;2;148;226;213m" }
function CatPeach      { "$ESC[38;2;250;179;135m" }
function CatSubtext    { "$ESC[38;2;166;173;200m" }
function CatYellow     { "$ESC[38;2;249;226;175m" }
function CatOverlay    { "$ESC[38;2;108;112;134m" }
function MochaMaroon   { "$ESC[38;2;243;139;139m" }
function ClawdOrange   { "$ESC[38;2;204;120;92m" }

# ----------------------------------------------------------------------
# Gradient functions - single-hue "shading" ramp: light tint (0%) -> deep
# tone (100%) of the same color family. [int] casts truncate toward zero
# to match bash's integer-division semantics exactly.
# ----------------------------------------------------------------------
function Shade-Gradient([int]$Pct, [int]$Lr, [int]$Lg, [int]$Lb, [int]$Dr, [int]$Dg, [int]$Db) {
    if ($Pct -gt 100) { $Pct = 100 }
    if ($Pct -lt 0) { $Pct = 0 }
    $r = $Lr + [int](( ($Dr - $Lr) * $Pct ) / 100.0)
    $g = $Lg + [int](( ($Dg - $Lg) * $Pct ) / 100.0)
    $b = $Lb + [int](( ($Db - $Lb) * $Pct ) / 100.0)
    return "$r;$g;$b"
}
function Get-ContextGradientColor([int]$Pct) { Shade-Gradient $Pct 249 226 175 223 142 29 }
function Get-UsageGradientColor([int]$Pct)   { Shade-Gradient $Pct 250 179 135 254 100 11 }
function Get-Usage7dGradientColor([int]$Pct) { Shade-Gradient $Pct 243 139 139 192 30 30 }

function Generate-Bar([int]$Pct, [int]$Width, [string]$Type) {
    $filled = [int]( (($Pct * $Width) + 50) / 100.0 )
    if ($filled -gt $Width) { $filled = $Width }

    $endColor = switch ($Type) {
        'context' { Get-ContextGradientColor $Pct }
        '7d'      { Get-Usage7dGradientColor $Pct }
        default   { Get-UsageGradientColor $Pct }
    }

    $sb = [System.Text.StringBuilder]::new()
    for ($i = 0; $i -lt $filled; $i++) {
        $blockPct = [int](($i * 100) / $Width)
        $color = switch ($Type) {
            'context' { Get-ContextGradientColor $blockPct }
            '7d'      { Get-Usage7dGradientColor $blockPct }
            default   { Get-UsageGradientColor $blockPct }
        }
        [void]$sb.Append("$ESC[38;2;${color}m$([char]0x2588)")
    }
    for ($i = 0; $i -lt ($Width - $filled); $i++) {
        [void]$sb.Append("$ESC[38;2;${endColor}m$([char]0x2591)")
    }
    [void]$sb.Append((Reset))
    return $sb.ToString()
}

# ----------------------------------------------------------------------
# Line 1: Model | Effort | Thinking | Cost
# ----------------------------------------------------------------------
$ModelDisplay = "$(Bold)$(CatTeal)$Model$(Reset)"
if ($Effort) { $ModelDisplay = "$ModelDisplay $(CatSubtext)| effort:$Effort$(Reset)" }
if ($ThinkingOn -eq $true) { $ModelDisplay = "$ModelDisplay $(CatSubtext)| thinking$(Reset)" }

if ($TotalCost -ne 0) {
    $costFmt = $TotalCost.ToString('F2', [System.Globalization.CultureInfo]::InvariantCulture)
    $CostDisplay = "$(CatSubtext)`$$costFmt$(Reset)"
} else {
    $CostDisplay = "$(CatOverlay)`$0.00$(Reset)"
}
$Line1 = "$ModelDisplay $(CatSubtext)|$(Reset) $CostDisplay"

# ----------------------------------------------------------------------
# Line 2: Directory + Branch (git branch read directly from .git/HEAD -
# no `git` binary required; searches parent dirs like real git does)
# ----------------------------------------------------------------------
function Get-GitBranch([string]$StartDir) {
    try {
        if (-not (Test-Path -LiteralPath $StartDir -PathType Container)) { return '' }
        $dir = (Resolve-Path -LiteralPath $StartDir -ErrorAction Stop).Path
        while ($true) {
            $gitPath = Join-Path $dir '.git'
            if (Test-Path -LiteralPath $gitPath) { break }
            $parent = Split-Path $dir -Parent
            if ([string]::IsNullOrEmpty($parent) -or $parent -eq $dir) { return '' }
            $dir = $parent
        }
        if (Test-Path -LiteralPath $gitPath -PathType Leaf) {
            # worktree: .git is a file containing "gitdir: <path>"
            $content = (Get-Content -LiteralPath $gitPath -Raw)
            if ($content -match 'gitdir:\s*(.+)') {
                $gitDir = $matches[1].Trim()
                if (-not [System.IO.Path]::IsPathRooted($gitDir)) { $gitDir = Join-Path $dir $gitDir }
            } else {
                return ''
            }
        } else {
            $gitDir = $gitPath
        }
        $headFile = Join-Path $gitDir 'HEAD'
        if (-not (Test-Path -LiteralPath $headFile)) { return '' }
        $headContent = (Get-Content -LiteralPath $headFile -Raw).Trim()
        if ($headContent -match '^ref:\s*refs/heads/(.+)$') { return $matches[1] }
        return ''  # detached HEAD - matches `git branch --show-current` returning empty
    } catch {
        return ''
    }
}

$DirDisplay = "$(CatSubtext)$CurrentDir$(Reset)"
$BranchDisplay = ''
$Branch = Get-GitBranch $CurrentDir
if ($Branch) { $BranchDisplay = " $(CatSubtext)| ($Branch)$(Reset)" }
$Line2 = "$DirDisplay$BranchDisplay"

# ----------------------------------------------------------------------
# Line 3: Context (40 blocks)
# ----------------------------------------------------------------------
$ContextPercent = 0
$CurrentTokens = 0
if ($CurrentUsage) {
    $inputTokens = [int](Get-Prop $CurrentUsage 'input_tokens' 0)
    $cacheCreate = [int](Get-Prop $CurrentUsage 'cache_creation_input_tokens' 0)
    $cacheRead   = [int](Get-Prop $CurrentUsage 'cache_read_input_tokens' 0)
    $CurrentTokens = $inputTokens + $cacheCreate + $cacheRead
    if ($ContextSize -gt 0) { $ContextPercent = [int](($CurrentTokens * 100) / $ContextSize) }
}
$TokensK = [int]($CurrentTokens / 1000)
$ContextK = [int]($ContextSize / 1000)

$CtxBar = Generate-Bar $ContextPercent 40 'context'
$CtxEndColor = Get-ContextGradientColor $ContextPercent
$Line3 = "$(CatYellow)Context$(Reset)  $CtxBar $(Bold)$ESC[38;2;${CtxEndColor}m$ContextPercent% used$(Reset) $(CatYellow)(${TokensK}k/${ContextK}k)$(Reset)"

# ----------------------------------------------------------------------
# Lines 4-5: Usage 5H and 7D (40 blocks)
# ----------------------------------------------------------------------
function Format-TimeRemaining($ResetEpoch) {
    if (-not $ResetEpoch) { return '' }
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $remaining = [int64]$ResetEpoch - $now
    if ($remaining -lt 0) { $remaining = 0 }
    $hours = [int]($remaining / 3600)
    $minutes = [int](($remaining % 3600) / 60)
    return "in ${hours}h${minutes}m"
}
function Format-ClockTime($ResetEpoch) {
    if (-not $ResetEpoch) { return '' }
    $dt = [DateTimeOffset]::FromUnixTimeSeconds([int64]$ResetEpoch).ToLocalTime()
    return $dt.ToString('HH:mm', [System.Globalization.CultureInfo]::InvariantCulture)
}
function Format-ResetDatetime($ResetEpoch) {
    if (-not $ResetEpoch) { return '' }
    $dt = [DateTimeOffset]::FromUnixTimeSeconds([int64]$ResetEpoch).ToLocalTime()
    $hour12 = $dt.Hour % 12
    if ($hour12 -eq 0) { $hour12 = 12 }
    $ampm = if ($dt.Hour -ge 12) { 'pm' } else { 'am' }
    $monthDay = $dt.ToString('MMM dd', [System.Globalization.CultureInfo]::InvariantCulture)
    return "$monthDay at ${hour12}${ampm}"
}
function Format-DaysHoursRemaining($ResetEpoch) {
    if (-not $ResetEpoch) { return '' }
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $remaining = [int64]$ResetEpoch - $now
    if ($remaining -lt 0) { $remaining = 0 }
    $days = [int]($remaining / 86400)
    $hours = [int](($remaining % 86400) / 3600)
    return "in ${days}d ${hours}h"
}

if ($null -ne $FiveHourPct) {
    $FiveHour = [int][math]::Round([double]$FiveHourPct)
    $SevenDay = if ($null -ne $SevenDayPct) { [int][math]::Round([double]$SevenDayPct) } else { 0 }

    $FiveResetFmt = Format-TimeRemaining $FiveHourReset
    $FiveClockFmt = Format-ClockTime $FiveHourReset
    $SevenResetFmt = Format-ResetDatetime $SevenDayReset
    $SevenRemainingFmt = Format-DaysHoursRemaining $SevenDayReset

    $FiveBar = Generate-Bar $FiveHour 40 '5h'
    $SevenBar = Generate-Bar $SevenDay 40 '7d'
    $FiveEndColor = Get-UsageGradientColor $FiveHour
    $SevenEndColor = Get-Usage7dGradientColor $SevenDay

    $Line4 = "$(CatPeach)5H Limit$(Reset) $FiveBar $(Bold)$ESC[38;2;${FiveEndColor}m$FiveHour%$(Reset) $(CatPeach)(Resets $FiveResetFmt at $FiveClockFmt)$(Reset)"
    $Line5 = "$(MochaMaroon)7D Limit$(Reset) $SevenBar $(Bold)$ESC[38;2;${SevenEndColor}m$SevenDay%$(Reset) $(MochaMaroon)(Resets $SevenRemainingFmt on $SevenResetFmt)$(Reset)"
} else {
    $FiveBar = Generate-Bar 0 40 '5h'
    $SevenBar = Generate-Bar 0 40 '7d'
    $FiveEndColor = Get-UsageGradientColor 0
    $SevenEndColor = Get-Usage7dGradientColor 0
    $Line4 = "$(CatPeach)5H Limit$(Reset) $FiveBar $(Bold)$ESC[38;2;${FiveEndColor}m0%$(Reset) $(CatOverlay)(loading..)$(Reset)"
    $Line5 = "$(MochaMaroon)7D Limit$(Reset) $SevenBar $(Bold)$ESC[38;2;${SevenEndColor}m0%$(Reset) $(CatOverlay)(loading..)$(Reset)"
}

# ============================================================================
# Clawd mascot art - see clawd-line.sh for the full design writeup. Same
# bit-string sprite patterns and half-block packing, ported 1:1.
# ============================================================================
$MASCOT_WIDTH = 18

function Bits-Range([int]$Width, [string[]]$Tokens) {
    $bits = New-Object char[] $Width
    for ($i = 0; $i -lt $Width; $i++) { $bits[$i] = '0' }
    foreach ($tok in $Tokens) {
        if ($tok -match '^(\d+)-(\d+)$') { $a = [int]$matches[1]; $b = [int]$matches[2] }
        else { $a = [int]$tok; $b = $a }
        for ($i = $a; $i -le $b; $i++) { $bits[$i] = '1' }
    }
    return -join $bits
}

$MASCOT_BODY       = Bits-Range 18 @('2-15')
$MASCOT_CLAWS      = Bits-Range 18 @('0-17')
$MASCOT_CLAWS_TUCK = Bits-Range 18 @('1-16')
$MASCOT_EYES_OPEN  = Bits-Range 18 @('2-4', '6-11', '13-15')
$MASCOT_EYES_SHUT  = Bits-Range 18 @('2-15')
$MASCOT_EYES_LEFT  = Bits-Range 18 @('2-3', '5-10', '12-15')
$MASCOT_EYES_RIGHT = Bits-Range 18 @('2-5', '7-12', '14-15')
$MASCOT_LEGS_A     = Bits-Range 18 @('4', '6', '11', '13')
$MASCOT_LEGS_B     = Bits-Range 18 @('3', '5', '12', '14')

function Render-PixelPair([string]$Top, [string]$Bot) {
    $sb = [System.Text.StringBuilder]::new()
    for ($i = 0; $i -lt $Top.Length; $i++) {
        $t = $Top[$i]; $b = $Bot[$i]
        if ($t -eq '1' -and $b -eq '1') { [void]$sb.Append([char]0x2588) }
        elseif ($t -eq '1') { [void]$sb.Append([char]0x2580) }
        elseif ($b -eq '1') { [void]$sb.Append([char]0x2584) }
        else { [void]$sb.Append(' ') }
    }
    return $sb.ToString()
}

function Get-MascotRow([string]$Mode, [string]$Frame, [int]$Idx) {
    $eyesTop = $MASCOT_EYES_OPEN
    $eyesBot = $MASCOT_EYES_OPEN
    $legs = $MASCOT_LEGS_A
    $claws = $MASCOT_CLAWS
    $eyesRow = '1'

    switch ($Mode) {
        'IDLE' {
            switch ($Frame) {
                'blink'      { $eyesTop = $MASCOT_EYES_SHUT; $eyesBot = $MASCOT_EYES_SHUT }
                'look_left'  { $eyesTop = $MASCOT_EYES_LEFT; $eyesBot = $MASCOT_EYES_LEFT }
                'look_right' { $eyesTop = $MASCOT_EYES_RIGHT; $eyesBot = $MASCOT_EYES_RIGHT }
                'stretch'    { $legs = $MASCOT_LEGS_B }
                'sleepy'     { $eyesTop = $MASCOT_EYES_SHUT; $eyesBot = $MASCOT_EYES_OPEN }
                'curl'       { $claws = $MASCOT_CLAWS_TUCK }
            }
        }
        'THINKING' {
            switch ($Frame) {
                '0' { $eyesRow = 'half'; $claws = $MASCOT_CLAWS_TUCK }
                '1' { $eyesRow = 'half'; $eyesTop = $MASCOT_EYES_LEFT; $eyesBot = $MASCOT_EYES_LEFT; $claws = $MASCOT_CLAWS_TUCK }
                '2' { $eyesRow = 'half'; $eyesTop = $MASCOT_EYES_RIGHT; $eyesBot = $MASCOT_EYES_RIGHT; $claws = $MASCOT_CLAWS_TUCK }
                '3' { $eyesRow = 'half'; $claws = $MASCOT_CLAWS_TUCK }
                '4' { $eyesRow = '1' }
            }
        }
        'EXECUTING' {
            $claws = $MASCOT_CLAWS_TUCK
            if ($Frame -eq '1') { $legs = $MASCOT_LEGS_B } else { $legs = $MASCOT_LEGS_A }
        }
    }

    switch ($Idx) {
        0 {
            if ($eyesRow -eq 'half') { return Render-PixelPair $MASCOT_BODY $eyesBot }
            else { return Render-PixelPair $MASCOT_BODY $MASCOT_BODY }
        }
        1 {
            if ($eyesRow -eq '1') { return Render-PixelPair $eyesTop $eyesBot }
            elseif ($eyesRow -eq 'half') { return Render-PixelPair $eyesTop $MASCOT_BODY }
            else { return Render-PixelPair $MASCOT_BODY $MASCOT_BODY }
        }
        2 { return Render-PixelPair $claws $claws }
        3 { return Render-PixelPair $MASCOT_BODY $MASCOT_BODY }
        4 { return Render-PixelPair $legs $legs }
    }
}

function Strip-Ansi([string]$S) {
    return [regex]::Replace($S, "$ESC\[[0-9;]*m", '')
}

# Real display width - emoji/wide glyphs render as 2 terminal columns but
# .Length counts UTF-16 code units, which previously threw off mascot
# alignment on lines containing such characters.
function Get-DisplayWidth([string]$S) {
    $width = 0
    $i = 0
    while ($i -lt $S.Length) {
        $ch = $S[$i]
        $len = 1
        $cp = [int]$ch
        if ([char]::IsHighSurrogate($ch) -and ($i + 1) -lt $S.Length -and [char]::IsLowSurrogate($S[$i + 1])) {
            $cp = [char]::ConvertToUtf32($ch, $S[$i + 1])
            $len = 2
        }
        $cat = [System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($S, $i)
        if ($cat -eq [System.Globalization.UnicodeCategory]::NonSpacingMark -or
            $cat -eq [System.Globalization.UnicodeCategory]::EnclosingMark) {
            $i += $len
            continue
        }
        $isWide = $false
        if ($cp -ge 0x1F300 -and $cp -le 0x1FAFF) { $isWide = $true }
        elseif ($cp -ge 0x2600 -and $cp -le 0x27BF) { $isWide = $true }
        elseif ($cp -ge 0x2B00 -and $cp -le 0x2BFF) { $isWide = $true }
        elseif (($cp -ge 0x1100 -and $cp -le 0x115F) -or
                ($cp -ge 0x2E80 -and $cp -le 0xA4CF) -or
                ($cp -ge 0xAC00 -and $cp -le 0xD7A3) -or
                ($cp -ge 0xF900 -and $cp -le 0xFAFF) -or
                ($cp -ge 0xFF00 -and $cp -le 0xFF60) -or
                ($cp -ge 0xFFE0 -and $cp -le 0xFFE6)) { $isWide = $true }
        $width += if ($isWide) { 2 } else { 1 }
        $i += $len
    }
    return $width
}

# Reads the transcript, determines MODE + FRAME (persisted per-mode counter
# in a temp state file, keyed by transcript path, same scheme as the bash
# version's python block).
function Get-MascotState([string]$TranscriptPath) {
    $mode = 'IDLE'
    $frame = 0

    if ($TranscriptPath -and (Test-Path -LiteralPath $TranscriptPath)) {
        try {
            $allLines = Get-Content -LiteralPath $TranscriptPath -ErrorAction Stop | Where-Object { $_.Trim() -ne '' }
            $tail = @($allLines | Select-Object -Last 60)
            [array]::Reverse($tail)
            $last = $null
            foreach ($line in $tail) {
                try { $d = $line | ConvertFrom-Json -Depth 20 -ErrorAction Stop } catch { continue }
                $dtype = $d.type
                if ($dtype -eq 'assistant' -or $dtype -eq 'user') { $last = $d; break }
                if ($dtype -eq 'system' -and $d.subtype -eq 'turn_duration') { $last = $d; break }
            }
            if ($null -ne $last) {
                $ltype = $last.type
                if ($ltype -eq 'system') {
                    $mode = 'IDLE'
                } else {
                    $blockTypes = @()
                    $content = Get-Prop $last 'message.content' $null
                    if ($content) { $blockTypes = @($content | ForEach-Object { $_.type }) }
                    if ($ltype -eq 'assistant' -and ($blockTypes -contains 'tool_use')) {
                        $mode = 'EXECUTING'
                    } elseif ($ltype -eq 'user' -and ($blockTypes -contains 'tool_result')) {
                        $age = $null
                        $ts = Get-Prop $last 'timestamp' $null
                        if ($ts) {
                            try {
                                $tsEpoch = [DateTimeOffset]::Parse($ts, [System.Globalization.CultureInfo]::InvariantCulture).ToUnixTimeSeconds()
                                $age = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - $tsEpoch
                            } catch {}
                        }
                        $mode = if ($null -ne $age -and $age -lt 1.5) { 'EXECUTING' } else { 'THINKING' }
                    } else {
                        $mode = 'THINKING'
                    }
                }
            }
        } catch {}
    }

    if ($mode -eq 'IDLE') {
        $t = [int]([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() % 14)
        $idlePoses = @{ 1 = 'blink'; 3 = 'look_left'; 5 = 'look_right'; 7 = 'stretch'; 9 = 'sleepy'; 10 = 'sleepy'; 12 = 'curl' }
        $frame = if ($idlePoses.ContainsKey($t)) { $idlePoses[$t] } else { 'rest' }
    } else {
        $keySource = if ($TranscriptPath) { $TranscriptPath } else { 'no-transcript' }
        $md5 = [System.Security.Cryptography.MD5]::Create()
        $hashBytes = $md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($keySource))
        $hex = ([System.BitConverter]::ToString($hashBytes) -replace '-', '').ToLower().Substring(0, 12)
        $stateFile = Join-Path ([System.IO.Path]::GetTempPath()) ".mascot_frame_$hex"
        $prevMode = $null; $prevCount = 0
        if (Test-Path -LiteralPath $stateFile) {
            $parts = (Get-Content -LiteralPath $stateFile -Raw).Trim() -split '\s+'
            if ($parts.Count -eq 2) { $prevMode = $parts[0]; $prevCount = [int]$parts[1] }
        }
        $count = if ($prevMode -eq $mode) { $prevCount + 1 } else { 0 }
        $frame = if ($mode -eq 'THINKING') { [string]($count % 5) } else { [string]($count % 2) }
        try { Set-Content -LiteralPath $stateFile -Value "$mode $count" -NoNewline } catch {}
    }

    return [pscustomobject]@{ Mode = $mode; Frame = $frame }
}

# Claude Code sets $env:COLUMNS on Windows the same way it does on
# macOS/Linux; fall back to the console width, then 80.
$TermCols = 80
if ($env:COLUMNS -and $env:COLUMNS -match '^\d+$') {
    $TermCols = [int]$env:COLUMNS
} else {
    try { if ($Host.UI.RawUI.WindowSize.Width -gt 0) { $TermCols = $Host.UI.RawUI.WindowSize.Width } } catch {}
}
if ($TermCols -lt 1) { $TermCols = 80 }

$Vis1 = Strip-Ansi $Line1
$Vis2 = Strip-Ansi $Line2
$Vis3 = Strip-Ansi $Line3
$Vis4 = Strip-Ansi $Line4
$Vis5 = Strip-Ansi $Line5

$MascotState = Get-MascotState $TranscriptPath

# All rows anchor to the same column so the crab stacks into one shape
# instead of drifting per-line.
$AnchorCol = $TermCols - $MASCOT_WIDTH - 10

function Format-LineWithMascot([string]$Line, [int]$RowIdx, [int]$VisWidth) {
    $pad = $AnchorCol - $VisWidth
    if ($pad -lt 1) { return $Line }
    $mrow = Get-MascotRow $MascotState.Mode $MascotState.Frame $RowIdx
    $spaces = ' ' * $pad
    return "$Line$spaces$(ClawdOrange)$mrow$(Reset)"
}

# ----------------------------------------------------------------------
# Output
# ----------------------------------------------------------------------
Write-Output (Format-LineWithMascot $Line1 0 (Get-DisplayWidth $Vis1))
Write-Output (Format-LineWithMascot $Line2 1 (Get-DisplayWidth $Vis2))
Write-Output (Format-LineWithMascot $Line3 2 (Get-DisplayWidth $Vis3))
Write-Output (Format-LineWithMascot $Line4 3 (Get-DisplayWidth $Vis4))
Write-Output (Format-LineWithMascot $Line5 4 (Get-DisplayWidth $Vis5))
