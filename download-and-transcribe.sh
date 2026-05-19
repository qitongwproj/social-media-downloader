#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MARKER="$(mktemp)"
INFO_FILE="$(mktemp)"
trap 'rm -f "$MARKER" "$INFO_FILE"' EXIT

usage() {
  cat <<EOF
Usage:
  ./download-and-transcribe.sh [download/transcribe options] <video-url>

Examples:
  ./download-and-transcribe.sh "https://www.xiaohongshu.com/discovery/item/..."
  ./download-and-transcribe.sh --language Chinese "https://www.xiaohongshu.com/discovery/item/..."
  ./download-and-transcribe.sh --download-dir ./downloads --transcript-dir ./transcripts "https://..."

Download options passed to ./download-video.sh:
  -o, --download-dir <dir>
      --cookies <file>
      --cookies-from-browser <browser>
      --update

Transcribe options passed to ./transcribe-video.sh:
      --model-dir <dir>
      --audio-dir <dir>
      --transcript-dir <dir>
      --language <language>
      --device <auto|cuda|cpu>
      --max-new-tokens <n>
      --force-audio
      --keep-audio
EOF
}

DOWNLOAD_ARGS=()
TRANSCRIBE_ARGS=()
DOWNLOAD_SEARCH_DIR="$ROOT_DIR/downloads"
URL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    -o|--download-dir)
      DOWNLOAD_SEARCH_DIR="${2:-}"
      DOWNLOAD_ARGS+=("-o" "$DOWNLOAD_SEARCH_DIR")
      shift 2
      ;;
    --cookies|--cookies-from-browser)
      DOWNLOAD_ARGS+=("$1" "${2:-}")
      shift 2
      ;;
    --update)
      DOWNLOAD_ARGS+=("$1")
      shift
      ;;
    --transcript-dir)
      TRANSCRIBE_ARGS+=("--output-dir" "${2:-}")
      shift 2
      ;;
    --model-dir|--audio-dir|--language|--device|--max-new-tokens)
      TRANSCRIBE_ARGS+=("$1" "${2:-}")
      shift 2
      ;;
    --force-audio|--keep-audio)
      TRANSCRIBE_ARGS+=("$1")
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

touch "$MARKER"
"$ROOT_DIR/download-video.sh" --info "${DOWNLOAD_ARGS[@]}" "$URL" > "$INFO_FILE"
EXPECTED_RELATIVE="$("$ROOT_DIR/.venv/bin/python" - "$INFO_FILE" <<'PY'
import json
import sys
from pathlib import Path

data = json.load(open(sys.argv[1], encoding="utf-8"))
extractor = data.get("extractor") or "media"
title = data.get("title") or data.get("id") or "media"
ext = data.get("ext") or "mp4"
unsafe = '<>:"/\\|?*\0'
title = "".join("_" if ch in unsafe else ch for ch in title)
title = " ".join(title.split()).strip(" .") or "media"
print(str(Path(extractor) / f"{title}.{ext}"))
PY
)"
"$ROOT_DIR/download-video.sh" "${DOWNLOAD_ARGS[@]}" "$URL"

MEDIA_FILE="$(
  find "$DOWNLOAD_SEARCH_DIR" -type f -newer "$MARKER" \
    \( -iname '*.mp4' -o -iname '*.mkv' -o -iname '*.webm' -o -iname '*.mov' -o -iname '*.m4a' -o -iname '*.mp3' \) \
    -printf '%T@ %p\n' | sort -nr | head -1 | cut -d' ' -f2-
)"

if [[ -z "$MEDIA_FILE" && -n "$EXPECTED_RELATIVE" && -f "$DOWNLOAD_SEARCH_DIR/$EXPECTED_RELATIVE" ]]; then
  MEDIA_FILE="$DOWNLOAD_SEARCH_DIR/$EXPECTED_RELATIVE"
fi

if [[ -z "$MEDIA_FILE" ]]; then
  echo "Could not find a newly downloaded media file under $DOWNLOAD_SEARCH_DIR." >&2
  exit 1
fi

echo "Downloaded media: $MEDIA_FILE"
exec "$ROOT_DIR/transcribe-video.sh" "${TRANSCRIBE_ARGS[@]}" "$MEDIA_FILE"
