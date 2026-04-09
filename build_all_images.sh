#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CORE_DOCKERFILE_DIR="$ROOT_DIR/catkin_ws/src/wam_core/wam_utils/docker"
JUGGLING_DOCKERFILE_DIR="$ROOT_DIR/catkin_ws/src/juggling_wam/juggling_wam_utils/docker"
RESIDUAL_PACKAGE_DIR="$ROOT_DIR/python_packages/juggling_residual_learning"
RESIDUAL_DOCKERFILE_PATH="$RESIDUAL_PACKAGE_DIR/docker/Dockerfile"
KAI_DOCKERFILE_DIR="$ROOT_DIR/ros_dockerfile"

need_dir() {
  local dir="$1"
  if [[ ! -d "$dir" ]]; then
    echo "Missing required directory: $dir" >&2
    echo "Did you run: vcs import . < residual_ws.repos" >&2
    exit 1
  fi
}

if ! command -v vcs >/dev/null 2>&1; then
  echo "vcstool is not installed. Install it first, then run: vcs import . < residual_ws.repos" >&2
  echo "Ubuntu: sudo apt-get update && sudo apt-get install -y vcstool" >&2
  echo "Fallback: python3 -m pip install --user vcstool" >&2
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is not installed or not in PATH" >&2
  exit 1
fi

need_dir "$CORE_DOCKERFILE_DIR"
need_dir "$JUGGLING_DOCKERFILE_DIR"
need_dir "$RESIDUAL_PACKAGE_DIR"
need_dir "$KAI_DOCKERFILE_DIR"

if [[ ! -f "$RESIDUAL_DOCKERFILE_PATH" ]]; then
  echo "Missing required file: $RESIDUAL_DOCKERFILE_PATH" >&2
  exit 1
fi

echo "[1/4] Building wam:core"
"$CORE_DOCKERFILE_DIR/build.sh" --no-cache

echo "[2/4] Building wam:juggling"
"$JUGGLING_DOCKERFILE_DIR/build.sh"

echo "[3/4] Building wam:residual"
"$RESIDUAL_PACKAGE_DIR/docker/build.sh"

echo "[4/4] Building wam:residual_kai (BASE_IMAGE=wam:residual)"
docker build --ssh default --build-arg BASE_IMAGE=wam:residual -t wam:residual_kai "$KAI_DOCKERFILE_DIR"

echo "All images built successfully: wam:core, wam:juggling, wam:residual, wam:residual_kai"