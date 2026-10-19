#!/usr/bin/env bash
###############################################################################
# transcribe.sh — Separate a song into audio stems (no sheet music).
#
# Usage:
#   transcribe.sh <input> <name> [options]
#
# Arguments:
#   <input>   Local audio file (mp3/wav/flac/ogg/m4a) or YouTube URL
#   <name>    Song name used for output filenames
#
# Options:
#   --fast             Two-stem separation (vocals + accompaniment)
#   --keep-work        Keep the intermediate work directory
#   --key-shift N      Shift pitch by N semitones (ffmpeg rubberband)
#   --tempo X          Change tempo by factor X (0.5–2.0, ffmpeg atempo)
###############################################################################
set -euo pipefail

PROJECT_ROOT="${TRANSCRIBE_ROOT:-$HOME/transcribe}"
DEMUCS_VENV="$HOME/venvs/demucs"
MIN_FREE_MB=1536

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
die()   { err "$@"; exit 1; }

usage() {
    sed -n '3,16p' "$0" | sed 's/^# \{0,1\}//'
}

free_mb() {
    df --output=avail -BM "$HOME" 2>/dev/null | tail -1 | tr -dc '0-9'
}

check_disk() {
    local mb
    mb=$(free_mb)
    [[ -n "$mb" ]] || die "Could not determine free disk space with df."
    if (( mb < MIN_FREE_MB )); then
        die "Only $((mb / 1024)) GB free — need at least 1.5 GB."
    fi
    info "Free disk: $((mb / 1024)) GB"
}

is_audio_file() {
    local f="$1" codec
    [[ -f "$f" && -s "$f" ]] || return 1
    codec=$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_type \
        -of csv=p=0 "$f" 2>/dev/null) || return 1
    [[ "$codec" == *audio* ]]
}

audio_duration() {
    local f="$1" duration
    duration=$(ffprobe -v error -show_entries format=duration \
        -of default=noprint_wrappers=1:nokey=1 "$f" 2>/dev/null) || return 1
    awk -v d="$duration" 'BEGIN { exit !(d + 0 > 0) }' || return 1
    printf '%s' "$duration"
}

durations_close() {
    local actual="$1" expected="$2" pct="${3:-1}"
    awk -v a="$actual" -v e="$expected" -v pct="$pct" 'BEGIN {
        tol = e * pct / 100
        if (tol < 0.5) tol = 0.5
        d = a - e
        if (d < 0) d = -d
        exit !(d <= tol)
    }'
}

filter_available() {
    ffmpeg -hide_banner -filters 2>/dev/null | awk -v f="$1" '$2 == f { found = 1 } END { exit !found }'
}

validate_number_range() {
    local label="$1" value="$2" lo="$3" hi="$4"
    if ! awk -v v="$value" -v lo="$lo" -v hi="$hi" 'BEGIN {
        exit !(v ~ /^[+-]?([0-9]+([.][0-9]*)?|[.][0-9]+)$/ && v + 0 >= lo && v + 0 <= hi)
    }'; then
        die "$label must be a number between $lo and $hi (got: '$value')"
    fi
}

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
INPUT=""
NAME=""
FAST=false
KEEP_WORK=false
KEY_SHIFT=0
TEMPO=""
YT_DLP=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --fast)       FAST=true; shift ;;
        --keep-work)  KEEP_WORK=true; shift ;;
        --key-shift)
            [[ $# -ge 2 ]] || die "Option --key-shift requires a value"
            KEY_SHIFT="$2"; shift 2 ;;
        --tempo)
            [[ $# -ge 2 ]] || die "Option --tempo requires a value"
            TEMPO="$2"; shift 2 ;;
        -h|--help)    usage; exit 0 ;;
        --)           shift; break ;;
        -*)           die "Unknown option: $1 (use --help)" ;;
        *)
            if [[ -z "$INPUT" ]]; then
                INPUT="$1"
            elif [[ -z "$NAME" ]]; then
                NAME="$1"
            else
                die "Unexpected argument: $1"
            fi
            shift ;;
    esac
done

while [[ $# -gt 0 ]]; do
    if [[ -z "$INPUT" ]]; then
        INPUT="$1"
    elif [[ -z "$NAME" ]]; then
        NAME="$1"
    else
        die "Unexpected argument: $1"
    fi
    shift
done

[[ -n "$INPUT" ]] || die "Usage: transcribe.sh <input> <name> [options] (use --help)"
[[ -n "$NAME" ]]  || die "Usage: transcribe.sh <input> <name> [options] (use --help)"

if [[ "$NAME" == */* || "$NAME" == "." || "$NAME" == ".." || "$NAME" == .* \
      || "$NAME" == *$'\n'* || "$NAME" == *$'\r'* ]]; then
    die "Invalid song name '$NAME'."
fi
if [[ "$INPUT" == *$'\n'* || "$INPUT" == *$'\r'* ]]; then
    die "Invalid input path: contains a newline."
fi

if [[ ! "$KEY_SHIFT" =~ ^[+-]?[0-9]+$ ]]; then
    die "--key-shift must be an integer number of semitones (got: '$KEY_SHIFT')"
fi
KEY_SHIFT=$(awk -v s="$KEY_SHIFT" 'BEGIN { printf "%d", s + 0 }')
if (( KEY_SHIFT < -48 || KEY_SHIFT > 48 )); then
    die "--key-shift must be between -48 and 48 semitones (got: $KEY_SHIFT)"
fi

if [[ -n "$TEMPO" ]]; then
    validate_number_range "--tempo" "$TEMPO" 0.5 2.0
    TEMPO=$(awk -v t="$TEMPO" 'BEGIN { printf "%.6g", t + 0 }')
fi

# ---------------------------------------------------------------------------
# Pre-flight
# ---------------------------------------------------------------------------
info "===== Pre-flight checks ====="

if [[ "$INPUT" =~ ^[Hh][Tt][Tt][Pp][Ss]?:// ]]; then
    INPUT_ID="url:$INPUT"
else
    [[ -f "$INPUT" ]] || die "Input not found: $INPUT"
    INPUT_ID="file:$(readlink -f -- "$INPUT"):$(stat -c '%s:%Y' -- "$INPUT")"
fi

check_disk

DEMUCS_PY="$DEMUCS_VENV/bin/python"
[[ -x "$DEMUCS_PY" ]] || die "Demucs venv not found at $DEMUCS_VENV. Run install.sh first."
command -v ffmpeg  >/dev/null 2>&1 || die "ffmpeg not found"
command -v ffprobe >/dev/null 2>&1 || die "ffprobe not found (it normally ships with ffmpeg)"

for filter in amix alimiter atempo; do
    filter_available "$filter" || die "ffmpeg is missing the '$filter' filter."
done
if (( KEY_SHIFT != 0 )); then
    filter_available rubberband || \
        die "ffmpeg is missing the 'rubberband' filter (needed for --key-shift)."
fi

if [[ -x "$DEMUCS_VENV/bin/yt-dlp" ]]; then
    YT_DLP="$DEMUCS_VENV/bin/yt-dlp"
else
    YT_DLP="$(command -v yt-dlp 2>/dev/null || true)"
fi
if [[ "$INPUT" =~ ^[Hh][Tt][Tt][Pp][Ss]?:// ]]; then
    [[ -n "$YT_DLP" ]] || die "yt-dlp not found — cannot download YouTube audio."
fi

# ---------------------------------------------------------------------------
# Directories and run parameters
# ---------------------------------------------------------------------------
WORK_DIR="$PROJECT_ROOT/work/$NAME"
OUT_DIR="$PROJECT_ROOT/output/$NAME"
PARAMS_FILE="$OUT_DIR/.transcribe-params"
mkdir -p "$WORK_DIR" "$OUT_DIR"

has_outputs() {
    [[ -n "$(find "$OUT_DIR" -maxdepth 1 -type f ! -name '.transcribe-params*' -print -quit 2>/dev/null)" ]]
}

declare -A CUR_PARAMS=(
    [input]="$INPUT_ID"
    [fast]="$FAST"
    [key_shift]="$KEY_SHIFT"
    [tempo]="${TEMPO:-none}"
)
PARAM_KEYS=(input fast key_shift tempo)

write_params() {
    local key tmp="$PARAMS_FILE.tmp"
    : > "$tmp"
    for key in "${PARAM_KEYS[@]}"; do
        printf '%s=%s\n' "$key" "${CUR_PARAMS[$key]}" >> "$tmp"
    done
    mv -f "$tmp" "$PARAMS_FILE"
}

if [[ -f "$PARAMS_FILE" ]]; then
    declare -A PREV_PARAMS=()
    while IFS='=' read -r key value; do
        [[ -n "$key" ]] && PREV_PARAMS["$key"]="$value"
    done < "$PARAMS_FILE"

    MISMATCH=""
    for key in "${PARAM_KEYS[@]}"; do
        if [[ "${PREV_PARAMS[$key]:-}" != "${CUR_PARAMS[$key]}" ]]; then
            MISMATCH="$key"
            break
        fi
    done

    if [[ -n "$MISMATCH" ]]; then
        if has_outputs; then
            err "Output folder $OUT_DIR was created with different settings:"
            err "  $MISMATCH: was '${PREV_PARAMS[$MISMATCH]:-}', now '${CUR_PARAMS[$MISMATCH]}'"
            die "Use a different <name>, or delete $OUT_DIR and run again."
        fi
        warn "Settings changed since the failed run — discarding stale work files."
        rm -rf "$WORK_DIR"
        mkdir -p "$WORK_DIR"
    fi
elif has_outputs; then
    err "Output folder $OUT_DIR has results without settings metadata."
    die "Use a different <name>, or delete $OUT_DIR and run again."
fi
write_params

info "Work dir:   $WORK_DIR"
info "Output dir: $OUT_DIR"
START_TIME=$(date +%s)

# ---------------------------------------------------------------------------
# Step 1: Obtain audio
# ---------------------------------------------------------------------------
info "===== Step 1: Obtain audio ====="

if [[ "$INPUT" =~ ^[Hh][Tt][Tt][Pp][Ss]?:// ]]; then
    SOURCE_EXT="mp3"
else
    case "${INPUT,,}" in
        *.mp3)  SOURCE_EXT="mp3" ;;
        *.wav)  SOURCE_EXT="wav" ;;
        *.flac) SOURCE_EXT="flac" ;;
        *.ogg)  SOURCE_EXT="ogg" ;;
        *.m4a)  SOURCE_EXT="m4a" ;;
        *)      die "Unsupported file format: $INPUT (mp3, wav, flac, ogg, m4a)" ;;
    esac
fi
SOURCE_AUDIO="$WORK_DIR/source.$SOURCE_EXT"

if [[ -e "$SOURCE_AUDIO" ]] && ! is_audio_file "$SOURCE_AUDIO"; then
    warn "Removing incomplete source file: $SOURCE_AUDIO"
    rm -f "$SOURCE_AUDIO"
fi

if [[ -f "$SOURCE_AUDIO" ]]; then
    ok "Source audio already exists — skipping download/copy"
elif [[ "$INPUT" =~ ^[Hh][Tt][Tt][Pp][Ss]?:// ]]; then
    download_audio() {
        "$YT_DLP" --no-playlist -x --audio-format mp3 --audio-quality 0 \
            -o "$WORK_DIR/source.%(ext)s" "$INPUT"
    }

    update_yt_dlp() {
        warn "yt-dlp failed — attempting to update it…"
        local pipx_list="" uv_bin=""
        if command -v pipx >/dev/null 2>&1; then
            pipx_list=$(pipx list 2>/dev/null || true)
        fi
        if [[ "$pipx_list" == *yt-dlp* ]]; then
            pipx upgrade yt-dlp || true
        else
            if command -v uv >/dev/null 2>&1; then
                uv_bin=$(command -v uv)
            elif [[ -x "$HOME/.local/bin/uv" ]]; then
                uv_bin="$HOME/.local/bin/uv"
            fi
            if [[ -n "$uv_bin" ]]; then
                "$uv_bin" pip install --python "$DEMUCS_PY" -U yt-dlp || true
                [[ -x "$DEMUCS_VENV/bin/yt-dlp" ]] && YT_DLP="$DEMUCS_VENV/bin/yt-dlp"
            else
                "$YT_DLP" -U || true
            fi
        fi
    }

    info "Downloading audio from YouTube…"
    if ! download_audio; then
        update_yt_dlp
        download_audio || die "yt-dlp failed. Update it with: uv pip install -U yt-dlp --python $DEMUCS_PY"
    fi

    if ! is_audio_file "$SOURCE_AUDIO"; then
        rm -f "$SOURCE_AUDIO"
        DOWNLOADED=$(find "$WORK_DIR" -maxdepth 1 -type f -name 'source.*' \
            ! -name '*.part' ! -name '*.ytdl' ! -name 'source.mp3' -print -quit 2>/dev/null || true)
        [[ -n "$DOWNLOADED" ]] || die "yt-dlp did not produce a usable audio file"
        info "Converting downloaded audio to mp3…"
        ffmpeg -nostdin -hide_banner -loglevel error -y -i "$DOWNLOADED" \
            -codec:a libmp3lame -b:a 320k "$SOURCE_AUDIO" || die "Could not convert downloaded audio"
        rm -f "$DOWNLOADED"
    fi
    ok "Downloaded: $SOURCE_AUDIO"
elif [[ -f "$INPUT" ]]; then
    if [[ "$(readlink -f -- "$INPUT")" == "$(readlink -f -- "$SOURCE_AUDIO")" ]]; then
        ok "Source audio is the input file — no copy needed"
    else
        cp -- "$INPUT" "$SOURCE_AUDIO"
        ok "Source audio ready (original quality preserved): $SOURCE_AUDIO"
    fi
else
    die "Input not found: $INPUT"
fi

is_audio_file "$SOURCE_AUDIO" || die "Source audio is missing or unreadable: $SOURCE_AUDIO"
DURATION=$(audio_duration "$SOURCE_AUDIO") || die "Could not determine audio duration"
DURATION_INT=$(awk -v d="$DURATION" 'BEGIN { printf "%d", d }')
info "Audio duration: ${DURATION_INT}s"

# ---------------------------------------------------------------------------
# Step 2: Stem separation with Demucs
# ---------------------------------------------------------------------------
info "===== Step 2: Stem separation (Demucs) ====="
check_disk

STEM_DIR="$WORK_DIR/htdemucs/source"
STEM_NAMES=(vocals)
if [[ "$FAST" == "true" ]]; then
    STEM_NAMES+=(no_vocals)
else
    STEM_NAMES+=(drums bass other)
fi

stems_ready() {
    local stem dur
    for stem in "${STEM_NAMES[@]}"; do
        is_audio_file "$STEM_DIR/$stem.wav" || return 1
        dur=$(audio_duration "$STEM_DIR/$stem.wav") || return 1
        durations_close "$dur" "$DURATION" 2 || return 1
    done
    return 0
}

if stems_ready; then
    ok "Stems already exist — skipping Demucs"
else
    rm -rf "$WORK_DIR/htdemucs"
    DEMUCS_ARGS=(-n htdemucs -d cpu -j 4)
    if (( DURATION_INT > 360 )); then
        info "Track > 6 min — using --segment 7 to limit RAM"
        DEMUCS_ARGS+=(--segment 7)
    fi
    if [[ "$FAST" == "true" ]]; then
        info "Fast mode: two-stem separation (vocals + accompaniment)"
        DEMUCS_ARGS+=(--two-stems vocals)
    fi
    DEMUCS_ARGS+=(-o "$WORK_DIR" "$SOURCE_AUDIO")

    info "Running Demucs on CPU (this may take a while)…"
    "$DEMUCS_PY" -m demucs "${DEMUCS_ARGS[@]}" || die "Demucs failed."

    if [[ ! -d "$STEM_DIR" ]]; then
        STEM_DIR=$(find "$WORK_DIR/htdemucs" -mindepth 1 -maxdepth 1 -type d -print -quit 2>/dev/null || true)
        [[ -n "$STEM_DIR" ]] || die "Demucs produced no stem directory."
    fi
    ok "Demucs complete"
fi

if [[ "$FAST" == "true" ]]; then
    VOCALS="$STEM_DIR/vocals.wav"
    NO_VOCALS="$STEM_DIR/no_vocals.wav"
    [[ -s "$VOCALS" ]]    || die "Vocals stem not found: $VOCALS"
    [[ -s "$NO_VOCALS" ]] || die "Accompaniment stem not found: $NO_VOCALS"
else
    VOCALS="$STEM_DIR/vocals.wav"
    DRUMS="$STEM_DIR/drums.wav"
    BASS="$STEM_DIR/bass.wav"
    OTHER="$STEM_DIR/other.wav"
    for f in "$VOCALS" "$DRUMS" "$BASS" "$OTHER"; do
        [[ -s "$f" ]] || die "Stem not found: $f"
    done
fi
ok "Stems located"

# ---------------------------------------------------------------------------
# Step 3: MP3 stems and mixes
# ---------------------------------------------------------------------------
info "===== Step 3: Audio outputs ====="

FX_FILTERS=""
if (( KEY_SHIFT != 0 )); then
    PITCH_SCALE=$(awk -v s="$KEY_SHIFT" 'BEGIN { printf "%.10f", 2 ^ (s / 12.0) }')
    FX_FILTERS+="rubberband=pitch=$PITCH_SCALE"
fi
if [[ -n "$TEMPO" ]]; then
    FX_FILTERS+="${FX_FILTERS:+,}atempo=$TEMPO"
fi

EXPECTED_DURATION=$(awk -v d="$DURATION" -v t="${TEMPO:-1}" 'BEGIN { printf "%.6f", d / (t + 0) }')

audio_output_ready() {
    local f="$1" actual
    is_audio_file "$f" || return 1
    actual=$(audio_duration "$f") || return 1
    durations_close "$actual" "$EXPECTED_DURATION" 1
}

render_stem() {
    local input="$1" output="$2"
    local -a cmd=(ffmpeg -nostdin -hide_banner -loglevel error -y -i "$input")
    if [[ -n "$FX_FILTERS" ]]; then
        cmd+=(-af "$FX_FILTERS")
    fi
    cmd+=(-codec:a libmp3lame -b:a 320k "$output")
    if ! "${cmd[@]}"; then
        rm -f "$output"
        die "ffmpeg failed to render $output"
    fi
    audio_output_ready "$output" || die "Invalid output: $output"
}

render_mix() {
    local output="$1"
    shift
    local -a inputs=("$@")
    local -a cmd=(ffmpeg -nostdin -hide_banner -loglevel error -y)
    local f chain=""

    for f in "${inputs[@]}"; do
        cmd+=(-i "$f")
    done

    if (( ${#inputs[@]} > 1 )); then
        chain="amix=inputs=${#inputs[@]}:normalize=0:dropout_transition=0"
    fi
    if [[ -n "$FX_FILTERS" ]]; then
        chain+="${chain:+,}$FX_FILTERS"
    fi
    chain+="${chain:+,}alimiter=limit=0.95"

    cmd+=(-filter_complex "${chain}[out]" -map "[out]" \
          -codec:a libmp3lame -b:a 320k "$output")
    if ! "${cmd[@]}"; then
        rm -f "$output"
        die "ffmpeg failed to render $output"
    fi
    audio_output_ready "$output" || die "Invalid output: $output"
}

render_one() {
    local kind="$1" output="$2"
    shift 2
    if audio_output_ready "$output"; then
        ok "$(basename "$output") exists — skipping"
        return 0
    fi
    rm -f "$output"
    info "Creating $(basename "$output")…"
    if [[ "$kind" == "stem" ]]; then
        render_stem "$1" "$output"
    else
        render_mix "$output" "$@"
    fi
    ok "Created: $output"
}

VOCALS_OUT="$OUT_DIR/${NAME}-vocals.mp3"
render_one stem "$VOCALS_OUT" "$VOCALS"

if [[ "$FAST" == "true" ]]; then
    render_one mix "$OUT_DIR/${NAME}-instrumental.mp3" "$NO_VOCALS"
else
    render_one stem "$OUT_DIR/${NAME}-drums.mp3" "$DRUMS"
    render_one stem "$OUT_DIR/${NAME}-bass.mp3" "$BASS"
    render_one stem "$OUT_DIR/${NAME}-other.mp3" "$OTHER"
    render_one mix  "$OUT_DIR/${NAME}-instrumental.mp3" "$DRUMS" "$BASS" "$OTHER"
    render_one mix  "$OUT_DIR/${NAME}-no-bass.mp3" "$DRUMS" "$OTHER"
    render_one mix  "$OUT_DIR/${NAME}-no-drums.mp3" "$BASS" "$OTHER"
fi

# ---------------------------------------------------------------------------
# Step 4: Cleanup work directory (only after success)
# ---------------------------------------------------------------------------
if [[ "$KEEP_WORK" == "false" ]]; then
    info "Cleaning up work directory…"
    rm -rf "$WORK_DIR"
    ok "Work directory deleted: $WORK_DIR"
else
    info "Keeping work directory (--keep-work): $WORK_DIR"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
END_TIME=$(date +%s)
ELAPSED=$(( END_TIME - START_TIME ))

echo ""
info "===== ${BOLD}Summary${NC} ====="
echo -e "${CYAN}Song:${NC}     $NAME"
echo -e "${CYAN}Time:${NC}     $((ELAPSED / 60))m $((ELAPSED % 60))s"
echo ""
echo -e "${BOLD}Output files:${NC}"
if has_outputs; then
    while IFS=$'\t' read -r size path; do
        printf '  %8s  %s\n' "$(numfmt --to=iec-i --suffix=B "$size")" "$(basename "$path")"
    done < <(find "$OUT_DIR" -maxdepth 1 -type f ! -name '.transcribe-params*' -printf '%s\t%p\n' | sort -rn)
else
    echo "  (none)"
fi

echo ""
FREE_MB=$(free_mb)
info "Free disk space: $(( ${FREE_MB:-0} / 1024 )) GB"
echo ""
ok "Done! Outputs in: $OUT_DIR"
