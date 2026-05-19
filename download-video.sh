#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="$ROOT_DIR/.venv"
DOWNLOAD_DIR="$ROOT_DIR/downloads"
PYTHON_BIN="${PYTHON_BIN:-python3}"
YTDLP="$VENV_DIR/bin/yt-dlp"

usage() {
  cat <<EOF
Usage:
  ./download-video.sh [options] <video-url>

Examples:
  ./download-video.sh "https://www.xiaohongshu.com/discovery/item/..."
  ./download-video.sh --cookies-from-browser chrome "https://www.xiaohongshu.com/discovery/item/..."
  ./download-video.sh --audio-only "https://www.youtube.com/watch?v=..."

Options:
  -o, --output-dir <dir>          Download directory. Default: ./downloads
  -f, --format <format>           yt-dlp format selector. Default: bestvideo*+bestaudio/best
      --cookies <file>            Use cookies file.
      --cookies-from-browser <b>  Use browser cookies, for example: chrome, chromium, firefox.
      --audio-only                Extract audio only.
      --info                      Print media info without downloading.
      --update                    Update local yt-dlp before running.
  -h, --help                      Show this help.
EOF
}

ensure_ytdlp() {
  if [[ ! -x "$YTDLP" ]]; then
    echo "Creating local Python environment: $VENV_DIR"
    "$PYTHON_BIN" -m venv "$VENV_DIR"
    "$VENV_DIR/bin/python" -m pip install --upgrade pip yt-dlp
  fi
}

OUTPUT_DIR="$DOWNLOAD_DIR"
FORMAT=""
FORMAT_SET=0
DOWNLOAD_MODE=1
UPDATE=0
EXTRA_ARGS=()
URL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    -o|--output-dir)
      OUTPUT_DIR="${2:-}"
      shift 2
      ;;
    -f|--format)
      FORMAT="${2:-}"
      FORMAT_SET=1
      shift 2
      ;;
    --cookies)
      EXTRA_ARGS+=(--cookies "${2:-}")
      shift 2
      ;;
    --cookies-from-browser)
      EXTRA_ARGS+=(--cookies-from-browser "${2:-}")
      shift 2
      ;;
    --audio-only)
      EXTRA_ARGS+=(-x --audio-format mp3)
      FORMAT="bestaudio/best"
      FORMAT_SET=1
      shift
      ;;
    --info)
      DOWNLOAD_MODE=0
      shift
      ;;
    --update)
      UPDATE=1
      shift
      ;;
    http://*|https://*)
      URL="$1"
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$URL" ]]; then
  echo "Missing video URL." >&2
  usage >&2
  exit 1
fi

ensure_ytdlp

if [[ "$UPDATE" -eq 1 ]]; then
  "$VENV_DIR/bin/python" -m pip install --upgrade yt-dlp
fi

mkdir -p "$OUTPUT_DIR"

if [[ "$FORMAT_SET" -eq 0 ]]; then
  if command -v ffmpeg >/dev/null 2>&1; then
    FORMAT="bestvideo*+bestaudio/best"
  else
    FORMAT="best[ext=mp4]/best"
  fi
fi

COMMON_ARGS=(
  --no-playlist
  --trim-filenames 180
  --user-agent "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"
)

if [[ "$DOWNLOAD_MODE" -eq 0 ]]; then
  exec "$YTDLP" "${COMMON_ARGS[@]}" "${EXTRA_ARGS[@]}" --dump-json "$URL"
fi

exec "$YTDLP" \
  "${COMMON_ARGS[@]}" \
  "${EXTRA_ARGS[@]}" \
  -f "$FORMAT" \
  -P "$OUTPUT_DIR" \
  -o "%(extractor)s/%(title).120B.%(ext)s" \
  "$URL"
