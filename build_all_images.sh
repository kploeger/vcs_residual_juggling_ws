#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

CORE_DOCKERFILE_DIR="$ROOT_DIR/catkin_ws/src/wam_core/wam_utils/docker"
JUGGLING_DOCKERFILE_DIR="$ROOT_DIR/catkin_ws/src/juggling_wam/juggling_wam_utils/docker"
RESIDUAL_DOCKERFILE_DIR="$ROOT_DIR/python_packages/juggling_residual_learning/docker"
KAI_DOCKERFILE_DIR="$ROOT_DIR/ros_dockerfile"

need_dir() {
  local dir="$1"
  if [[ ! -d "$dir" ]]; then
    echo "Missing required directory: $dir" >&2
    exit 1
  fi
}

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is not installed or not in PATH" >&2
  exit 1
fi

need_dir "$CORE_DOCKERFILE_DIR"
need_dir "$JUGGLING_DOCKERFILE_DIR"
need_dir "$RESIDUAL_DOCKERFILE_DIR"
need_dir "$KAI_DOCKERFILE_DIR"

echo "[1/4] Building wam:core"
docker build --ssh default -t wam:core "$CORE_DOCKERFILE_DIR"

echo "[2/4] Building wam:juggling"
docker build --ssh default -t wam:juggling "$JUGGLING_DOCKERFILE_DIR"

echo "[3/4] Building wam:residual"
docker build --ssh default -t wam:residual "$RESIDUAL_DOCKERFILE_DIR"

echo "[4/4] Building wam:kai (BASE_IMAGE=wam:residual)"
docker build --ssh default --build-arg BASE_IMAGE=wam:residual -t wam:kai "$KAI_DOCKERFILE_DIR"

echo "All images built successfully: wam:core, wam:juggling, wam:residual, wam:kai"