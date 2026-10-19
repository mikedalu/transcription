#!/usr/bin/env bash
###############################################################################
# install.sh — Audio stem separation setup (CPU only, no sheet music)
#
# Creates:
#   ~/venvs/demucs  – CPU-only torch, torchaudio, Demucs, soundfile
#
# Requirements:
#   - Ubuntu with Python 3.11 available (uv can download it)
#   - ffmpeg with rubberband, amix, alimiter, and atempo
#   - yt-dlp already installed
###############################################################################
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
die()   { err "$@"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
DEMUCS_VENV="$HOME/venvs/demucs"
DEMUCS_PY="$DEMUCS_VENV/bin/python"
MIN_FREE_MB=1536

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
    info "Free disk space: $((mb / 1024)) GB"
}

###############################################################################
# 1. Pre-flight
###############################################################################
info "===== Phase 1: Pre-flight checks ====="
check_disk

command -v ffmpeg  >/dev/null 2>&1 || die "ffmpeg not found. Install with: sudo apt install ffmpeg"
command -v ffprobe >/dev/null 2>&1 || die "ffprobe not found (it normally ships with ffmpeg)"
ok "ffmpeg found: $(ffmpeg -version 2>&1 | head -1)"

for filter in amix alimiter atempo rubberband; do
    if ! ffmpeg -hide_banner -filters 2>/dev/null | awk -v f="$filter" '$2 == f { found = 1 } END { exit !found }'; then
        die "ffmpeg is missing the '$filter' filter."
    fi
done
ok "ffmpeg audio filters found (amix, alimiter, atempo, rubberband)"

if ! dpkg -s libsndfile1 >/dev/null 2>&1; then
    info "Installing libsndfile1…"
    sudo apt-get install -y libsndfile1 || die "Could not install libsndfile1"
fi
ok "libsndfile1 installed"

YT_DLP=$(command -v yt-dlp 2>/dev/null || true)
[[ -n "$YT_DLP" ]] || die "yt-dlp not found. It should already be installed."
ok "yt-dlp found: $YT_DLP ($(yt-dlp --version))"

###############################################################################
# 2. uv
###############################################################################
info "===== Phase 2: uv package manager ====="

if ! command -v uv >/dev/null 2>&1; then
    command -v curl >/dev/null 2>&1 || die "curl not found — needed to install uv"
    info "Installing uv…"
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
fi
command -v uv >/dev/null 2>&1 || die "uv installation failed"
ok "uv installed: $(uv --version)"

###############################################################################
# 3. Demucs venv
###############################################################################
info "===== Phase 3: demucs venv ====="
check_disk

DEMUCS_VENV_OK=false
if [[ -d "$DEMUCS_VENV" && -x "$DEMUCS_PY" ]] && \
    "$DEMUCS_PY" -c 'import sys; raise SystemExit(0 if sys.version_info[:2] == (3, 11) else 1)'; then
    DEMUCS_VENV_OK=true
fi
if [[ "$DEMUCS_VENV_OK" == "true" ]]; then
    warn "demucs venv already exists at $DEMUCS_VENV — reusing it"
else
    if [[ -d "$DEMUCS_VENV" ]]; then
        warn "Recreating demucs venv (missing Python 3.11 or broken environment)"
        rm -rf "$DEMUCS_VENV"
    fi
    uv venv --python 3.11 "$DEMUCS_VENV"
fi

info "Installing CPU-only torch/torchaudio (< 2.9)…"
uv pip install --python "$DEMUCS_PY" \
    --index-url https://download.pytorch.org/whl/cpu \
    --extra-index-url https://pypi.org/simple \
    "torch==2.8.0+cpu" "torchaudio==2.8.0+cpu"

info "Installing demucs and soundfile…"
uv pip install --python "$DEMUCS_PY" \
    --extra-index-url https://download.pytorch.org/whl/cpu \
    demucs soundfile "torch==2.8.0+cpu" "torchaudio==2.8.0+cpu"

uv cache clean >/dev/null 2>&1 || true
if [[ -x "$DEMUCS_VENV/bin/pip" ]]; then
    "$DEMUCS_VENV/bin/pip" cache purge >/dev/null 2>&1 || true
fi

TORCH_VER=$("$DEMUCS_PY" -c 'import torch; print(torch.__version__)')
TORCH_AUDIO_VER=$("$DEMUCS_PY" -c 'import torchaudio; print(torchaudio.__version__)')
[[ "$TORCH_VER" == *+cpu ]] || die "Expected CPU-only torch, but got $TORCH_VER"
[[ "$TORCH_AUDIO_VER" == *+cpu ]] || die "Expected CPU-only torchaudio, but got $TORCH_AUDIO_VER"
ok "demucs venv ready (torch $TORCH_VER, torchaudio $TORCH_AUDIO_VER)"

"$DEMUCS_PY" -c "import demucs, torch, torchaudio, soundfile; print('demucs imports OK')"
ok "demucs imports verified"
info "demucs venv size: $(du -sh "$DEMUCS_VENV" | cut -f1)"

###############################################################################
# 4. Project dirs
###############################################################################
mkdir -p "$HOME/transcribe/work" "$HOME/transcribe/output"

###############################################################################
# 5. Summary
###############################################################################
echo ""
info "===== Installation Summary ====="
ok "ffmpeg:      $(command -v ffmpeg)"
ok "yt-dlp:      $YT_DLP"
ok "uv:          $(command -v uv)"
ok "scripts:     $SCRIPT_DIR"
ok "demucs:      $DEMUCS_VENV"
echo ""
info "demucs venv size: $(du -sh "$DEMUCS_VENV" | cut -f1)"
info "Free disk space: $(( $(free_mb) / 1024 )) GB"
echo ""
ok "Setup complete. Run transcribe.sh to separate a song into stems."
