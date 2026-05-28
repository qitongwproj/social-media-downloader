#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="$ROOT_DIR/.venv"
PYTHON_BIN="${PYTHON_BIN:-python3}"

usage() {
  cat <<EOF
Usage:
  ./collect-xhs-user-urls.sh [options] <xiaohongshu-user-profile-url>

Examples:
  ./collect-xhs-user-urls.sh "https://www.xiaohongshu.com/user/profile/..."
  ./collect-xhs-user-urls.sh --headed "https://www.xiaohongshu.com/user/profile/..."
  ./collect-xhs-user-urls.sh --all-notes -o urls.txt "https://www.xiaohongshu.com/user/profile/..."

Options:
  -o, --output <file>       Output file. Default: urls.txt
      --profile-dir <dir>   Persistent browser profile. Default: .browser-profiles/xhs
      --all-notes           Collect all note URLs, not only video notes.
      --headed              Show browser for login/verification.
      --login-wait <sec>    Wait after opening page before collecting. Useful with --headed.
      --append              Append and de-duplicate with existing output.
      --max-scrolls <n>     Maximum scroll rounds. Default: 80
      --scroll-wait <sec>   Wait after each scroll. Default: 1.2
  -h, --help                Show this help.
EOF
}

ensure_playwright() {
  if [[ ! -x "$VENV_DIR/bin/python" ]]; then
    echo "Creating local Python environment: $VENV_DIR"
    "$PYTHON_BIN" -m venv "$VENV_DIR"
  fi

  if ! "$VENV_DIR/bin/python" -c "import playwright" >/dev/null 2>&1; then
    "$VENV_DIR/bin/python" -m pip install --upgrade pip playwright
  fi
}

if [[ $# -eq 0 ]]; then
  usage >&2
  exit 1
fi

for arg in "$@"; do
  case "$arg" in
    -h|--help)
      usage
      exit 0
      ;;
  esac
done

ensure_playwright

exec "$VENV_DIR/bin/python" "$ROOT_DIR/scripts/collect_xhs_user_urls.py" "$@"
