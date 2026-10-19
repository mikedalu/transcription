#!/usr/bin/env bash
###############################################################################
# cleanup.sh — List and clean up stem outputs, work folders, and caches
#
# Usage:
#   cleanup.sh                  List output folders with sizes
#   cleanup.sh --work           Delete all work directories
#   cleanup.sh --caches         Purge uv/pip caches
#   cleanup.sh --all            Delete work dirs + purge caches
#   cleanup.sh --delete <name>  Delete a specific output folder
###############################################################################
set -euo pipefail

PROJECT_ROOT="${TRANSCRIBE_ROOT:-$HOME/transcribe}"
WORK_ROOT="$PROJECT_ROOT/work"
OUT_ROOT="$PROJECT_ROOT/output"

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

free_mb() {
    df --output=avail -BM "$HOME" 2>/dev/null | tail -1 | tr -dc '0-9'
}

has_entries() {
    [[ -n "$(find "$1" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]
}

validate_name() {
    local name="$1"
    [[ -n "$name" ]] || die "Song name must not be empty"
    if [[ "$name" == */* || "$name" == "." || "$name" == ".." || "$name" == .* \
          || "$name" == *$'\n'* || "$name" == *$'\r'* ]]; then
        die "Invalid song name '$name'."
    fi
}

list_folders() {
    echo -e "\n${BOLD}Output folders:${NC}"
    if [[ -d "$OUT_ROOT" ]] && has_entries "$OUT_ROOT"; then
        du -sh -- "$OUT_ROOT"/*/ 2>/dev/null || true
    else
        echo "  (none)"
    fi

    echo -e "\n${BOLD}Work folders (intermediate files):${NC}"
    if [[ -d "$WORK_ROOT" ]] && has_entries "$WORK_ROOT"; then
        du -sh -- "$WORK_ROOT"/*/ 2>/dev/null || true
    else
        echo "  (none)"
    fi

    if [[ -d "$OUT_ROOT" ]] && has_entries "$OUT_ROOT"; then
        echo -e "\n${BOLD}Total output size:${NC} $(du -sh "$OUT_ROOT" | cut -f1)"
    fi
}

clean_work() {
    info "Deleting all work directories…"
    if [[ -d "$WORK_ROOT" ]] && has_entries "$WORK_ROOT"; then
        find "$WORK_ROOT" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
        ok "Work directories cleaned"
    else
        ok "No work directory to clean"
    fi
}

clean_caches() {
    info "Purging caches…"

    if command -v uv >/dev/null 2>&1; then
        if uv cache clean >/dev/null 2>&1; then
            ok "uv cache cleaned"
        else
            warn "uv cache clean failed"
        fi
    fi

    if [[ -x "$HOME/venvs/demucs/bin/pip" ]]; then
        "$HOME/venvs/demucs/bin/pip" cache purge >/dev/null 2>&1 || true
    fi
}

delete_output() {
    local name="$1"
    validate_name "$name"

    local target="$OUT_ROOT/$name"
    local work_target="$WORK_ROOT/$name"

    if [[ -d "$target" ]]; then
        info "Deleting output: $target"
        rm -rf -- "$target"
        ok "Output deleted: $name"
    else
        warn "Output folder not found: $target"
    fi

    if [[ -d "$work_target" ]]; then
        info "Also deleting work dir: $work_target"
        rm -rf -- "$work_target"
        ok "Work dir deleted: $name"
    fi
}

case "${1:-}" in
    "")
        list_folders
        ;;
    --work)
        clean_work
        ;;
    --caches)
        clean_caches
        ;;
    --all)
        clean_work
        clean_caches
        ;;
    --delete)
        [[ -n "${2:-}" ]] || die "Usage: cleanup.sh --delete <name>"
        delete_output "$2"
        ;;
    --help|-h)
        sed -n '6,12p' "$0" | sed 's/^# \{0,1\}//'
        ;;
    *)
        die "Unknown option: $1 (use --help)"
        ;;
esac

echo ""
FREE_MB=$(free_mb)
info "Free disk space: $(( ${FREE_MB:-0} / 1024 )) GB"
