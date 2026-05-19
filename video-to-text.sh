#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<EOF
Usage:
  ./video-to-text.sh [options] <video-url>
  ./video-to-text.sh --batch urls.txt [options]

Examples:
  ./video-to-text.sh --language Chinese "https://www.xiaohongshu.com/discovery/item/..."
  ./video-to-text.sh --batch urls.txt --language Chinese
  ./video-to-text.sh --batch urls.txt --continue-on-error

Options:
      --batch <file>                 Read URLs from a text file, one URL per line.
      --continue-on-error            Continue batch processing when one URL fails.
      --download-dir <dir>           Download directory. Default: ./downloads
      --transcript-dir <dir>         Markdown output directory. Default: ./transcripts
      --audio-dir <dir>              Extracted WAV directory when --keep-audio is used.
      --cookies <file>               Use cookies file for downloading.
      --cookies-from-browser <b>     Use browser cookies: chrome, chromium, firefox.
      --language <language>          Optional ASR hint: Chinese, English, etc.
      --device <auto|cuda|cpu>       ASR device. Default: auto.
      --model-dir <dir>              Local model directory. Default: models/Qwen3-ASR-1.7B
      --max-new-tokens <n>           Default: 1024
      --force-audio                  Re-extract WAV even if it already exists.
      --keep-audio                   Keep extracted WAV. Default: delete temporary audio.
      --update                       Update yt-dlp before downloading.
  -h, --help                         Show this help.
EOF
}

BATCH_FILE=""
CONTINUE_ON_ERROR=0
URLS=()
PIPELINE_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --batch)
      BATCH_FILE="${2:-}"
      shift 2
      ;;
    --continue-on-error)
      CONTINUE_ON_ERROR=1
      shift
      ;;
    --download-dir|--transcript-dir|--audio-dir|--cookies|--cookies-from-browser|--language|--device|--model-dir|--max-new-tokens)
      PIPELINE_ARGS+=("$1" "${2:-}")
      shift 2
      ;;
    --force-audio|--keep-audio|--update)
      PIPELINE_ARGS+=("$1")
      shift
      ;;
    http://*|https://*)
      URLS+=("$1")
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -n "$BATCH_FILE" ]]; then
  if [[ ! -f "$BATCH_FILE" ]]; then
    echo "Batch file does not exist: $BATCH_FILE" >&2
    exit 1
  fi
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" || "$line" == \#* ]] && continue
    URLS+=("$line")
  done < "$BATCH_FILE"
fi

if [[ "${#URLS[@]}" -eq 0 ]]; then
  echo "Missing video URL. Pass a URL or use --batch urls.txt." >&2
  usage >&2
  exit 1
fi

failures=0
total="${#URLS[@]}"

for index in "${!URLS[@]}"; do
  url="${URLS[$index]}"
  echo
  echo "==> [$((index + 1))/$total] $url"
  if "$ROOT_DIR/download-and-transcribe.sh" "${PIPELINE_ARGS[@]}" "$url"; then
    echo "==> Done: $url"
  else
    failures=$((failures + 1))
    echo "==> Failed: $url" >&2
    if [[ "$CONTINUE_ON_ERROR" -ne 1 ]]; then
      exit 1
    fi
  fi
done

if [[ "$failures" -gt 0 ]]; then
  echo "Completed with $failures failure(s)." >&2
  exit 1
fi

echo
echo "All done. Markdown transcripts are in: transcripts/"
