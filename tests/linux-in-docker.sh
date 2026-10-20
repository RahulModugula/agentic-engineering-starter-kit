#!/bin/bash
# Run this repo's full verification on Ubuntu inside Docker (read-only mount; works on a copy). Usage:
#   bash tests/linux-in-docker.sh [REPO_DIR]
# Needs Docker. Proves the hooks and tools work on Linux (GNU tools, no BSD date/sed), not just macOS.
set -euo pipefail
repo=$(cd "${1:-$(dirname "$0")/..}" && pwd)
docker run --rm --init -v "$repo:/src:ro" ubuntu:24.04 bash -c '
  set -eo pipefail   # each step pipes into tail: without pipefail a red step still exits 0
  apt-get update -qq >/dev/null
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq git jq zsh python3 perl file make shellcheck nodejs >/dev/null
  cp -a /src /k && cd /k
  git config --global user.email ci@example.com
  git config --global user.name ci
  git config --global init.defaultBranch main
  git config --global --add safe.directory /k
  echo "== make check (Linux)"; make check 2>&1 | tail -18
  echo "== make lint (Linux)";  make lint 2>&1 | tail -4
  echo "== make mutate (Linux)"; make mutate 2>&1 | tail -12'
