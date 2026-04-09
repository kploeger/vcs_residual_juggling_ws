#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

if ! command -v vcs >/dev/null 2>&1; then
  echo "vcstool is not installed. Trying to install it..."

  if command -v apt-get >/dev/null 2>&1; then
    set +e
    sudo apt-get update
    sudo apt-get install -y vcstool
    rc=$?
    if [[ $rc -ne 0 ]]; then
      sudo apt-get install -y python3-vcstool
      rc=$?
    fi
    set -e

    if [[ $rc -ne 0 ]]; then
      echo "APT install failed, trying pip user install..."
      python3 -m pip install --user vcstool
    fi
  else
    python3 -m pip install --user vcstool
  fi

  # Typical user-level pip target.
  export PATH="$HOME/.local/bin:$PATH"

  if ! command -v vcs >/dev/null 2>&1; then
    echo "Failed to install vcstool automatically." >&2
    echo "Install manually with one of:" >&2
    echo "  sudo apt-get install -y vcstool" >&2
    echo "  python3 -m pip install --user vcstool" >&2
    exit 1
  fi
fi

echo "Importing repositories from residual_ws.repos"
vcs import . < residual_ws.repos

echo "Initializing submodules"
vcs custom catkin_ws/src python_packages --git --args submodule update --init --recursive

echo "Building Docker images"
bash build_all_images.sh
