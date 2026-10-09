#!/bin/bash
# Run shellcheck (warning level and up) on Ubuntu inside Docker, for machines without shellcheck installed.
#   bash tests/shellcheck-in-docker.sh [REPO_DIR]
set -euo pipefail
repo=$(cd "${1:-$(dirname "$0")/..}" && pwd)
docker run --rm -v "$repo:/src:ro" ubuntu:24.04 bash -c '
  apt-get update -qq >/dev/null; DEBIAN_FRONTEND=noninteractive apt-get install -y -qq shellcheck >/dev/null
  cd /src && shellcheck -f gcc -S warning bin/*.sh claude/hooks/*.sh install.sh'
