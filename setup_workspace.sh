#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

if ! command -v vcs >/dev/null 2>&1; then
  echo "vcstool is not installed." >&2
  echo "Install it with:" >&2
  echo "  sudo apt-get update && sudo apt-get install -y python3-vcstool" >&2
  exit 1
fi

echo "Importing repositories from residual_ws.repos"
vcs import . < residual_ws.repos

echo "Building Docker images"
bash build_all_images.sh
