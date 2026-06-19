#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "$ROOT_DIR/config.sh"
VENV_DIR="$ROOT_DIR/.venv-asr"
PYTHON_BIN="${PYTHON_BIN:-python3}"
TORCH_INDEX_URL="${TORCH_INDEX_URL:-https://download.pytorch.org/whl/cu124}"

usage() {
  cat <<EOF
Usage:
  ./transcribe-video.sh [options] <media-file>

Examples:
  ./transcribe-video.sh "downloads/XiaoHongShu/example.mp4"
  ./transcribe-video.sh --language Chinese "downloads/XiaoHongShu/example.mp4"
  ./transcribe-video.sh --device cpu "downloads/XiaoHongShu/example.mp4"

Options:
      --model-dir <dir>       Local model directory. Default: $DEFAULT_MODEL_DIR
      --audio-dir <dir>       Extracted WAV output directory when --keep-audio is used. Default: audio
      --output-dir <dir>      Transcript output directory. Default: transcripts
      --language <language>   Optional hint: Chinese, English, etc.
      --device <auto|cuda|cpu>
      --max-new-tokens <n>    Default: 4096
      --max-chunk-sec <sec>   Audio chunk size. Default: 60
      --force-audio           Re-extract WAV even if it already exists.
      --keep-audio            Keep extracted WAV under --audio-dir. Default: delete temporary audio.
      --setup-only            Create ASR env and install dependencies, then exit.
  -h, --help                  Show this help.
EOF
}

ensure_asr_env() {
  if [[ ! -x "$VENV_DIR/bin/python" ]]; then
    echo "Creating ASR Python environment: $VENV_DIR"
    "$PYTHON_BIN" -m venv "$VENV_DIR"
  fi

  if [[ ! -f "$VENV_DIR/.qwen-asr-installed" ]]; then
    echo "Installing ASR dependencies. This can take a while."
    "$VENV_DIR/bin/python" -m pip install --upgrade pip
    "$VENV_DIR/bin/python" -m pip install --upgrade torch --index-url "$TORCH_INDEX_URL"
    "$VENV_DIR/bin/python" -m pip install --upgrade imageio-ffmpeg
    "$VENV_DIR/bin/python" -m pip install -e "$ROOT_DIR/third_party/Qwen3-ASR"
    touch "$VENV_DIR/.qwen-asr-installed"
  fi
}

SETUP_ONLY=0
USER_MODEL_DIR=""
ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --setup-only)
      SETUP_ONLY=1
      shift
      ;;
    --model-dir)
      USER_MODEL_DIR="${2:-}"
      ARGS+=("$1" "$USER_MODEL_DIR")
      shift 2
      ;;
    *)
      ARGS+=("$1")
      shift
      ;;
  esac
done

ensure_asr_env

if [[ "$SETUP_ONLY" -eq 1 ]]; then
  echo "ASR environment is ready: $VENV_DIR"
  exit 0
fi

if [[ "${#ARGS[@]}" -eq 0 ]]; then
  echo "Missing media file." >&2
  usage >&2
  exit 1
fi

# Fall back to the unified default from config.sh when the user did not override.
if [[ -z "$USER_MODEL_DIR" ]]; then
  ARGS+=(--model-dir "$DEFAULT_MODEL_DIR")
fi

exec "$VENV_DIR/bin/python" "$ROOT_DIR/scripts/transcribe_video.py" "${ARGS[@]}"
