#!/bin/bash
# ============================================================================
# clawd-line - a Claude Code statusline with an animated crab mascot
# ============================================================================
# Line 1: Model | Effort | Thinking | Cost
# Line 2: Working directory (branch)
# Line 3: Context usage bar (40 blocks, yellow shading)
# Line 4: 5-hour rate limit bar (40 blocks, peach shading)
# Line 5: 7-day rate limit bar (40 blocks, red shading)
#
# Clawd, the mascot in the top-right corner, reacts to what Claude is
# actually doing: eyes dart around while thinking, legs shuffle while a
# tool is running, and it idles/blinks/stretches when nothing is happening.
# See install.sh / README.md for setup.
# ============================================================================

# Ensure a bundled jq (copied next to this script by install.sh) is found,
# even when Claude Code launches the statusline with a minimal PATH — common
# on Windows / GUI launches where a winget-installed jq is not on PATH yet.
export PATH="$(dirname "$0"):$PATH"

input=$(cat)

# Parse JSON input
MODEL=$(echo "$input" | jq -r '.model.display_name // "Unknown"')
CURRENT_DIR=$(echo "$input" | jq -r '.workspace.current_dir // "."')
CONTEXT_SIZE=$(echo "$input" | jq -r '.context_window.context_window_size // 200000')
CURRENT_USAGE=$(echo "$input" | jq -r '.context_window.current_usage // null')
TOTAL_COST=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')

# Rate limits (official API - available for Pro/Max subscribers)
FIVE_HOUR_PCT=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
FIVE_HOUR_RESET=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
SEVEN_DAY_PCT=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
SEVEN_DAY_RESET=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')

TRANSCRIPT_PATH=$(echo "$input" | jq -r '.transcript_path // empty')

# ============================================================================
# Colors
# ============================================================================
RESET="\033[0m"
BOLD="\033[1m"

cat_teal() { echo -e "\033[38;2;148;226;213m"; }
cat_peach() { echo -e "\033[38;2;250;179;135m"; }
cat_subtext() { echo -e "\033[38;2;166;173;200m"; }
cat_yellow() { echo -e "\033[38;2;249;226;175m"; }
cat_overlay() { echo -e "\033[38;2;108;112;134m"; }
mocha_maroon() { echo -e "\033[38;2;243;139;139m"; }
clawd_orange() { echo -e "\033[38;2;204;120;92m"; }

# ============================================================================
# Gradient Functions
# ============================================================================
# Single-hue "shading" ramp: light tint (0%) → deep/saturated tone (100%) of
# the same color family, rather than transitioning across different hues.
shade_gradient() {
    local pct=$1 lr=$2 lg=$3 lb=$4 dr=$5 dg=$6 db=$7
    [[ $pct -gt 100 ]] && pct=100
    [[ $pct -lt 0 ]] && pct=0
    local r=$((lr + (dr - lr) * pct / 100))
    local g=$((lg + (dg - lg) * pct / 100))
    local b=$((lb + (db - lb) * pct / 100))
    echo "$r;$g;$b"
}

# Context: yellow shading, Mocha Yellow (#f9e2af) → Latte Yellow (#df8e1d)
get_context_gradient_color() {
    shade_gradient "$1" 249 226 175 223 142 29
}

# 5H Limit: orange shading, Mocha Peach (#fab387) → Latte Peach (#fe640b)
get_usage_gradient_color() {
    shade_gradient "$1" 250 179 135 254 100 11
}

# 7D Limit: red shading, light red → deep red (equal G/B channels so it
# reads as red rather than pink/magenta)
get_usage_7d_gradient_color() {
    shade_gradient "$1" 243 139 139 192 30 30
}

generate_bar() {
    local pct=$1
    local width=$2
    local type=$3
    local bar=""
    local filled=$(( (pct * width + 50) / 100 ))
    [[ $filled -gt $width ]] && filled=$width

    local end_color
    case "$type" in
        context) end_color=$(get_context_gradient_color "$pct") ;;
        7d) end_color=$(get_usage_7d_gradient_color "$pct") ;;
        *) end_color=$(get_usage_gradient_color "$pct") ;;
    esac

    for ((i=0; i<filled; i++)); do
        local block_pct=$((i * 100 / width))
        local color
        case "$type" in
            context) color=$(get_context_gradient_color "$block_pct") ;;
            7d) color=$(get_usage_7d_gradient_color "$block_pct") ;;
            *) color=$(get_usage_gradient_color "$block_pct") ;;
        esac
        bar+="\033[38;2;${color}m█"
    done

    for ((i=0; i<width-filled; i++)); do
        bar+="\033[38;2;${end_color}m░"
    done

    echo -e "$bar$RESET"
}

# ============================================================================
# Line 1: Model | Effort | Thinking | Cost
# ============================================================================

# Model (bold)
MODEL_DISPLAY="${BOLD}$(cat_teal)${MODEL}${RESET}"

# Reasoning effort + extended thinking (effort.level: low|medium|high|xhigh|max; absent if model lacks effort param)
EFFORT=$(echo "$input" | jq -r '.effort.level // empty')
THINKING=$(echo "$input" | jq -r '.thinking.enabled // empty')
[ -n "$EFFORT" ] && MODEL_DISPLAY="${MODEL_DISPLAY} $(cat_subtext)│ effort:${EFFORT}${RESET}"
[ "$THINKING" = "true" ] && MODEL_DISPLAY="${MODEL_DISPLAY} $(cat_subtext)│ thinking${RESET}"

# Cost (same color as directory)
COST_DISPLAY=""
if [[ "$TOTAL_COST" != "0" && -n "$TOTAL_COST" ]]; then
    COST_FMT=$(printf "%.2f" "$TOTAL_COST")
    COST_DISPLAY="$(cat_subtext)\$${COST_FMT}${RESET}"
else
    COST_DISPLAY="$(cat_overlay)\$0.00${RESET}"
fi

# Build Line 1: Model | Effort | Thinking | Cost
LINE1="${MODEL_DISPLAY} $(cat_subtext)│${RESET} ${COST_DISPLAY}"

# ============================================================================
# Line 2: Directory + Branch
# ============================================================================

# Directory (full path, no ~)
DIR_DISPLAY="$(cat_subtext)${CURRENT_DIR}${RESET}"

# Git branch
BRANCH_DISPLAY=""
cd "$CURRENT_DIR" 2>/dev/null
if git rev-parse --git-dir > /dev/null 2>&1; then
    BRANCH=$(git branch --show-current 2>/dev/null)
    [[ -n "$BRANCH" ]] && BRANCH_DISPLAY=" $(cat_subtext)│ (${BRANCH})${RESET}"
fi

LINE2="${DIR_DISPLAY}${BRANCH_DISPLAY}"

# ============================================================================
# Line 3: Context (40 blocks)
# ============================================================================

CONTEXT_PERCENT=0
CURRENT_TOKENS=0
if [[ "$CURRENT_USAGE" != "null" && -n "$CURRENT_USAGE" ]]; then
    INPUT_TOKENS=$(echo "$CURRENT_USAGE" | jq -r '.input_tokens // 0')
    CACHE_CREATE=$(echo "$CURRENT_USAGE" | jq -r '.cache_creation_input_tokens // 0')
    CACHE_READ=$(echo "$CURRENT_USAGE" | jq -r '.cache_read_input_tokens // 0')
    CURRENT_TOKENS=$((INPUT_TOKENS + CACHE_CREATE + CACHE_READ))
    [[ "$CONTEXT_SIZE" -gt 0 ]] && CONTEXT_PERCENT=$((CURRENT_TOKENS * 100 / CONTEXT_SIZE))
fi

# Format tokens as k
TOKENS_K=$((CURRENT_TOKENS / 1000))
CONTEXT_K=$((CONTEXT_SIZE / 1000))

CTX_BAR=$(generate_bar "$CONTEXT_PERCENT" 40 "context")
CTX_END_COLOR=$(get_context_gradient_color "$CONTEXT_PERCENT")
LINE3="$(cat_yellow)Context${RESET}  ${CTX_BAR} ${BOLD}\033[38;2;${CTX_END_COLOR}m${CONTEXT_PERCENT}% used${RESET} $(cat_yellow)(${TOKENS_K}k/${CONTEXT_K}k)${RESET}"

# ============================================================================
# Lines 4-5: Usage 5H and 7D (40 blocks)
# ============================================================================

# Format 5H reset as "in 2h15m"
format_time_remaining() {
    local reset_epoch="$1"
    [[ -z "$reset_epoch" || "$reset_epoch" == "null" ]] && return
    local now_epoch=$(date +%s)
    local remaining=$((reset_epoch - now_epoch))
    [[ $remaining -lt 0 ]] && remaining=0
    local hours=$((remaining / 3600))
    local minutes=$(((remaining % 3600) / 60))
    echo "in ${hours}h${minutes}m"
}

# Cross-platform date formatting (BSD/macOS vs GNU/Linux)
_date_fmt() {
    local epoch="$1" fmt="$2"
    local out=""
    out=$(date -j -f "%s" "$epoch" "+$fmt" 2>/dev/null) && [[ -n "$out" ]] && { echo "$out"; return; }
    out=$(date -r "$epoch" "+$fmt" 2>/dev/null) && [[ -n "$out" ]] && { echo "$out"; return; }
    date -d "@$epoch" "+$fmt" 2>/dev/null
}

# Format 7D reset as "Jan 21 at 2pm"
format_reset_datetime() {
    local reset_epoch="$1"
    [[ -z "$reset_epoch" || "$reset_epoch" == "null" ]] && return
    local hour=$(_date_fmt "$reset_epoch" "%H")
    [[ -z "$hour" ]] && return
    local hour_num=$((10#$hour))
    local hour_12=$((hour_num % 12))
    [[ $hour_12 -eq 0 ]] && hour_12=12
    local ampm="am"
    [[ $hour_num -ge 12 ]] && ampm="pm"
    local month_day=$(_date_fmt "$reset_epoch" "%b %d")
    [[ -z "$month_day" ]] && return
    echo "${month_day} at ${hour_12}${ampm}"
}

# Format 5H reset as clock time "13:00"
format_clock_time() {
    local reset_epoch="$1"
    [[ -z "$reset_epoch" || "$reset_epoch" == "null" ]] && return
    _date_fmt "$reset_epoch" "%H:%M"
}

# Format 7D reset as remaining "in 2d 14h"
format_days_hours_remaining() {
    local reset_epoch="$1"
    [[ -z "$reset_epoch" || "$reset_epoch" == "null" ]] && return
    local now_epoch=$(date +%s)
    local remaining=$((reset_epoch - now_epoch))
    [[ $remaining -lt 0 ]] && remaining=0
    local days=$((remaining / 86400))
    local hours=$(((remaining % 86400) / 3600))
    echo "in ${days}d ${hours}h"
}

# Usage from rate_limits
if [[ -n "$FIVE_HOUR_PCT" ]]; then
    FIVE_HOUR=$(printf "%.0f" "$FIVE_HOUR_PCT")
    SEVEN_DAY=$(printf "%.0f" "${SEVEN_DAY_PCT:-0}")

    FIVE_RESET_FMT=$(format_time_remaining "$FIVE_HOUR_RESET")
    FIVE_CLOCK_FMT=$(format_clock_time "$FIVE_HOUR_RESET")
    SEVEN_RESET_FMT=$(format_reset_datetime "$SEVEN_DAY_RESET")
    SEVEN_REMAINING_FMT=$(format_days_hours_remaining "$SEVEN_DAY_RESET")

    FIVE_BAR=$(generate_bar "$FIVE_HOUR" 40 "5h")
    SEVEN_BAR=$(generate_bar "$SEVEN_DAY" 40 "7d")

    FIVE_END_COLOR=$(get_usage_gradient_color "$FIVE_HOUR")
    SEVEN_END_COLOR=$(get_usage_7d_gradient_color "$SEVEN_DAY")

    LINE4="$(cat_peach)5H Limit${RESET} ${FIVE_BAR} ${BOLD}\033[38;2;${FIVE_END_COLOR}m${FIVE_HOUR}%${RESET} $(cat_peach)(Resets ${FIVE_RESET_FMT} at ${FIVE_CLOCK_FMT})${RESET}"
    LINE5="$(mocha_maroon)7D Limit${RESET} ${SEVEN_BAR} ${BOLD}\033[38;2;${SEVEN_END_COLOR}m${SEVEN_DAY}%${RESET} $(mocha_maroon)(Resets ${SEVEN_REMAINING_FMT} on ${SEVEN_RESET_FMT})${RESET}"
else
    FIVE_BAR=$(generate_bar 0 40 "5h")
    SEVEN_BAR=$(generate_bar 0 40 "7d")
    FIVE_END_COLOR=$(get_usage_gradient_color 0)
    SEVEN_END_COLOR=$(get_usage_7d_gradient_color 0)
    LINE4="$(cat_peach)5H Limit${RESET} ${FIVE_BAR} ${BOLD}\033[38;2;${FIVE_END_COLOR}m0%${RESET} $(cat_overlay)(loading..)${RESET}"
    LINE5="$(mocha_maroon)7D Limit${RESET} ${SEVEN_BAR} ${BOLD}\033[38;2;${SEVEN_END_COLOR}m0%${RESET} $(cat_overlay)(loading..)${RESET}"
fi

# ============================================================================
# Clawd mascot art: blocky pixel-crab (notched top corners, two square eyes,
# flush side claw tabs, two inward leg tabs). Rendered with half-block chars
# (▀▄█) to pack 10 pixel-rows into the 5 statusline rows. Three states,
# picked by peeking at the transcript's last event (see the python block
# below): THINKING (eyes dart up/left/right while a text/thinking block is
# being generated), EXECUTING (legs shuffle fast while a tool_use/tool_result
# is in flight), IDLE (slow blink plus an occasional leg/claw fidget so it
# isn't a frozen statue between turns).
# ============================================================================
MASCOT_WIDTH=18

# Builds an N-wide bit string with '1' at the given columns/ranges (e.g.
# "2-15" or "6"). Building from ranges instead of hand-typed literals avoids
# silent off-by-one typos (bit an earlier notch-row bug had).
bits_range() {
    local width="$1"; shift
    local s="" i
    for (( i=0; i<width; i++ )); do s+="0"; done
    for tok in "$@"; do
        local a b
        if [[ "$tok" == *-* ]]; then a="${tok%-*}"; b="${tok#*-}"; else a="$tok"; b="$tok"; fi
        for (( i=a; i<=b; i++ )); do s="${s:0:i}1${s:i+1}"; done
    done
    printf '%s' "$s"
}

# Body spans cols 2-15 (14 wide) within an 18-wide frame, leaving 2-col
# margins on each side for the claw row to flush against. Eyes are a single
# narrow column each, pushed outward from center (cols 5 and 12).
MASCOT_BODY=$(bits_range 18 2-15)          # flat top/plain body, no corner notch
MASCOT_CLAWS=$(bits_range 18 0-17)         # claw row, flush tabs at outer columns
MASCOT_CLAWS_TUCK=$(bits_range 18 1-16)    # claws pulled in one col each side (relaxed fidget)
MASCOT_EYES_OPEN=$(bits_range 18 2-4 6-11 13-15)   # body minus 2 narrow eye columns
MASCOT_EYES_SHUT=$(bits_range 18 2-15)             # eyes closed = solid body
MASCOT_EYES_LEFT=$(bits_range 18 2-3 5-10 12-15)   # eyes shifted one col left (thinking, look L)
MASCOT_EYES_RIGHT=$(bits_range 18 2-5 7-12 14-15)  # eyes shifted one col right (thinking, look R)
MASCOT_LEGS_A=$(bits_range 18 4 6 11 13)   # 4 distinct legs, centered
MASCOT_LEGS_B=$(bits_range 18 3 5 12 14)   # scurry - legs shifted outward

render_pixel_pair() {
    local top="$1" bot="$2" out="" i t b c
    for (( i=0; i<${#top}; i++ )); do
        t="${top:i:1}"; b="${bot:i:1}"
        if [[ "$t" == "1" && "$b" == "1" ]]; then c="█"
        elif [[ "$t" == "1" ]]; then c="▀"
        elif [[ "$b" == "1" ]]; then c="▄"
        else c=" "
        fi
        out+="$c"
    done
    printf '%s' "$out"
}

# mode: IDLE | THINKING | EXECUTING (chosen in the python block below by
# reading is_busy plus the transcript's last event type). frame: a small
# per-mode index/label picking which fidget pose to draw this tick.
# eyes_top/eyes_bot are usually the same pattern (rendered as a solid two
# pixel-row-tall gap), but sleepy idle sets them differently: top = shut
# (eyelid down), bottom = open (gap) -> render_pixel_pair sees top=1/bot=0
# right at the eye columns and draws "▀", i.e. only the lower half of that
# cell is empty - a half-height eye slit instead of a full-height one.
get_mascot_row() {
    local mode="$1" frame="$2" idx="$3"
    local eyes_top="$MASCOT_EYES_OPEN" eyes_bot="$MASCOT_EYES_OPEN"
    local legs="$MASCOT_LEGS_A" claws="$MASCOT_CLAWS"
    # Which pixel-rows the eyes occupy: 1 = normal slot (idx1's own 2 pixel
    # rows); half = shifted up by exactly 1 pixel row, straddling idx0's
    # bottom pixel row and idx1's top pixel row (still 2 pixel rows tall,
    # not shrunk - just half a character cell higher than normal).
    local eyes_row=1
    case "$mode" in
        IDLE)
            case "$frame" in
                blink)      eyes_top="$MASCOT_EYES_SHUT"; eyes_bot="$MASCOT_EYES_SHUT" ;;
                look_left)  eyes_top="$MASCOT_EYES_LEFT"; eyes_bot="$MASCOT_EYES_LEFT" ;;
                look_right) eyes_top="$MASCOT_EYES_RIGHT"; eyes_bot="$MASCOT_EYES_RIGHT" ;;
                stretch)    legs="$MASCOT_LEGS_B" ;;                              # arms+legs reach outward
                sleepy)     eyes_top="$MASCOT_EYES_SHUT"; eyes_bot="$MASCOT_EYES_OPEN" ;;  # heavy half-lidded
                curl)       claws="$MASCOT_CLAWS_TUCK" ;;                         # curled up, relaxed
            esac
            ;;
        THINKING)
            # Cycles: eyes shift up by half a character cell (full-size,
            # unshrunk - just straddling the row boundary), glance left,
            # glance right, back to center, then drop back down to the
            # normal eye row - then repeats.
            case "$frame" in
                0) eyes_row=half; claws="$MASCOT_CLAWS_TUCK" ;;                                     # shift up, centered
                1) eyes_row=half; eyes_top="$MASCOT_EYES_LEFT"; eyes_bot="$MASCOT_EYES_LEFT"
                   claws="$MASCOT_CLAWS_TUCK" ;;                                                    # up, look left
                2) eyes_row=half; eyes_top="$MASCOT_EYES_RIGHT"; eyes_bot="$MASCOT_EYES_RIGHT"
                   claws="$MASCOT_CLAWS_TUCK" ;;                                                    # up, look right
                3) eyes_row=half; claws="$MASCOT_CLAWS_TUCK" ;;                                     # up, back to center
                4) eyes_row=1 ;;                                                                    # come back down
            esac
            ;;
        EXECUTING)
            claws="$MASCOT_CLAWS_TUCK"                                     # claws dug in the whole time, so
            if [[ "$frame" == "1" ]]; then                                 # it reads as "executing" even on
                legs="$MASCOT_LEGS_B"                                      # the poll where legs happen to
            else                                                           # match idle's rest pose. All 4
                legs="$MASCOT_LEGS_A"                                      # legs stay down, just shuffling
            fi                                                             # in/out every single tick
            ;;
    esac
    case "$idx" in
        0)
            case "$eyes_row" in
                half) render_pixel_pair "$MASCOT_BODY" "$eyes_bot" ;;   # eye's top pixel-row peeks into here
                *)    render_pixel_pair "$MASCOT_BODY" "$MASCOT_BODY" ;;
            esac
            ;;
        1)
            case "$eyes_row" in
                1)    render_pixel_pair "$eyes_top" "$eyes_bot" ;;      # normal slot, full eyes
                half) render_pixel_pair "$eyes_top" "$MASCOT_BODY" ;;   # eye's bottom pixel-row continues here
                *)    render_pixel_pair "$MASCOT_BODY" "$MASCOT_BODY" ;;
            esac
            ;;
        2) render_pixel_pair "$claws" "$claws" ;;               # claws
        3) render_pixel_pair "$MASCOT_BODY" "$MASCOT_BODY" ;;   # body resumes
        4) render_pixel_pair "$legs" "$legs" ;;                 # 4 legs
    esac
}

strip_ansi() {
    # Strips both realized ESC-byte codes and literal, not-yet-rendered
    # "\033[...]m" text (RESET/BOLD are plain string concatenations here,
    # not routed through echo -e until the final print, so both forms
    # can appear in the same line).
    printf '%s' "$1" | sed -E 's/\\033\[[0-9;]*m//g' | sed -E $'s/\x1b\\[[0-9;]*m//g'
}

# Claude Code pipes script output rather than connecting it to the terminal,
# so tput cols can't see the real size; it injects COLUMNS/LINES instead
# (Claude Code v2.1.153+).
TERM_COLS="${COLUMNS:-80}"
[[ "$TERM_COLS" =~ ^[0-9]+$ ]] || TERM_COLS=80
[[ "$TERM_COLS" -lt 1 ]] && TERM_COLS=80

# Mascot state, plus real display-width per line, computed together in one
# python3 call. Emoji and other wide glyphs render as 2 terminal columns but
# bash's ${#str} counts them as 1, which previously threw off padding by a
# different amount on each line (they carry different emoji counts) and
# broke vertical alignment of the mascot across the 5 rows.
VIS1=$(strip_ansi "$LINE1")
VIS2=$(strip_ansi "$LINE2")
VIS3=$(strip_ansi "$LINE3")
VIS4=$(strip_ansi "$LINE4")
VIS5=$(strip_ansi "$LINE5")

MASCOT_RESULT=$(python3 - "$TRANSCRIPT_PATH" "$VIS1" "$VIS2" "$VIS3" "$VIS4" "$VIS5" <<'PYEOF'
import sys, time, os, json, unicodedata, tempfile
from datetime import datetime

def display_width(s):
    w = 0
    for ch in s:
        if unicodedata.combining(ch):
            continue
        cp = ord(ch)
        ea = unicodedata.east_asian_width(ch)
        if ea in ("W", "F"):
            w += 2
        elif 0x1F300 <= cp <= 0x1FAFF or 0x2600 <= cp <= 0x27BF or 0x2B00 <= cp <= 0x2BFF:
            w += 2
        else:
            w += 1
    return w

transcript_path = sys.argv[1]
lines = sys.argv[2:7]
now = time.time()

# There's no official "is_generating" field in the statusline payload, so the
# transcript JSONL (transcript_path) is the only ground truth for what's
# actually happening. Rather than guessing "still active" from how recently
# an entry was written (which broke down for genuinely long thinking spans -
# it looked idle - and lagged a step behind once thinking finished), walk
# back to the last *meaningful* event and read what it actually is:
#   - a user message or tool_result with no assistant reply yet -> Claude
#     must currently be generating the next thing (however long that takes)
#   - an assistant tool_use with no tool_result yet -> a tool is running
#   - an assistant thinking/text block with nothing after it yet -> Claude
#     is still generating (more thinking, more text, or about to call a
#     tool) - there is no timeout here; it's over when one of the two
#     signals below says so
#   - a "system"/"turn_duration" event -> Claude Code's own definitive
#     marker that the whole turn just finished; genuinely idle
# Other line types (compact_boundary, away_summary, file-history-snapshot,
# last-prompt, ai-title, mode, attachment, ...) are housekeeping and skipped.
mode = "IDLE"
frame = 0
if transcript_path and os.path.exists(transcript_path):
    try:
        with open(transcript_path, "rb") as f:
            f.seek(0, os.SEEK_END)
            size = f.tell()
            chunk = 4096
            data = b""
            while size > 0 and data.count(b"\n") < 60:
                step = min(chunk, size)
                size -= step
                f.seek(size)
                data = f.read(step) + data
        raw_lines = [l for l in data.decode("utf-8", "ignore").split("\n") if l.strip()]
        last = None
        for raw in reversed(raw_lines):
            try:
                d = json.loads(raw)
            except Exception:
                continue
            dtype = d.get("type")
            if dtype in ("assistant", "user"):
                last = d
                break
            if dtype == "system" and d.get("subtype") == "turn_duration":
                last = d
                break
        if last is not None:
            ltype = last.get("type")
            if ltype == "system":
                mode = "IDLE"
            else:
                content = (last.get("message") or {}).get("content")
                block_types = [c.get("type") for c in content if isinstance(c, dict)] if isinstance(content, list) else []
                if ltype == "assistant" and "tool_use" in block_types:
                    mode = "EXECUTING"
                elif ltype == "user" and "tool_result" in block_types:
                    # Give a brief EXECUTING afterglow right after tool_result
                    # appears (fast tools finish under the ~1s refresh
                    # interval, so the raw "tool_use in flight" window is
                    # rarely, if ever, sampled), then fall through to
                    # THINKING once Claude has actually started composing
                    # again.
                    age = None
                    ts = last.get("timestamp")
                    if ts:
                        try:
                            age = now - datetime.fromisoformat(ts.replace("Z", "+00:00")).timestamp()
                        except Exception:
                            age = None
                    mode = "EXECUTING" if (age is not None and age < 1.5) else "THINKING"
                else:
                    mode = "THINKING"
    except Exception:
        pass

if mode == "IDLE":
    # Idle fidgets are slow (a new pose every couple seconds), so sampling
    # wall-clock time works fine here - the refresh cadence is much faster
    # than the cycle, unlike THINKING/EXECUTING below. A little "personality"
    # loop: rest, blink, glance left, rest, glance right, rest, stretch,
    # rest, get sleepy (held a couple ticks), rest, curl up, rest, repeat.
    t = int(now) % 14
    idle_poses = {1: "blink", 3: "look_left", 5: "look_right", 7: "stretch",
                  9: "sleepy", 10: "sleepy", 12: "curl"}
    frame = idle_poses.get(t, "rest")
else:
    # THINKING/EXECUTING need to visibly change on every render. Deriving the
    # frame from wall-clock time (e.g. int(now * 6) % 2) aliases badly: the
    # statusline is re-invoked roughly once a second, and stepping time by
    # ~1s moves an even multiple of the toggle's own period, so the sampled
    # parity barely ever changes - the animation looked frozen for long
    # stretches. Instead, persist a small per-session counter on disk and
    # advance it by one on every single invocation, so it's guaranteed to
    # change every render regardless of how often that happens to be.
    import hashlib
    key = hashlib.md5((transcript_path or "no-transcript").encode()).hexdigest()[:12]
    state_file = os.path.join(tempfile.gettempdir(), f".mascot_frame_{key}")
    prev_mode, prev_count = None, 0
    try:
        with open(state_file) as sf:
            parts = sf.read().split()
            if len(parts) == 2:
                prev_mode, prev_count = parts[0], int(parts[1])
    except Exception:
        pass
    count = (prev_count + 1) if prev_mode == mode else 0
    frame = count % 5 if mode == "THINKING" else count % 2
    try:
        with open(state_file, "w") as sf:
            sf.write(f"{mode} {count}")
    except Exception:
        pass

widths = [str(display_width(l)) for l in lines]
print(mode, frame, *widths)
PYEOF
)
read -r MASCOT_MODE MASCOT_FRAME VIS1_W VIS2_W VIS3_W VIS4_W VIS5_W <<< "$MASCOT_RESULT"

# All rows anchor to the same column so the crab stacks into one shape
# instead of drifting per-line. Extra margin (beyond MASCOT_WIDTH) accounts
# for fullscreen TUI mode drawing its own border/chrome at the right edge,
# which eats into usable width beyond what $COLUMNS reports.
ANCHOR_COL=$(( TERM_COLS - MASCOT_WIDTH - 10 ))

append_mascot() {
    local line="$1" row_idx="$2" vis_width="$3"
    local mrow pad spaces
    pad=$(( ANCHOR_COL - vis_width ))
    if [[ $pad -lt 1 ]]; then
        echo -e "$line"
        return
    fi
    mrow=$(get_mascot_row "$MASCOT_MODE" "$MASCOT_FRAME" "$row_idx")
    printf -v spaces '%*s' "$pad" ''
    echo -e "${line}${spaces}$(clawd_orange)${mrow}${RESET}"
}

# ============================================================================
# Output
# ============================================================================
append_mascot "$LINE1" 0 "$VIS1_W"
append_mascot "$LINE2" 1 "$VIS2_W"
append_mascot "$LINE3" 2 "$VIS3_W"
append_mascot "$LINE4" 3 "$VIS4_W"
append_mascot "$LINE5" 4 "$VIS5_W"
