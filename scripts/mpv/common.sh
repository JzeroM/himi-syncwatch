#!/usr/bin/env bash
set -euo pipefail

MPV_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$MPV_SCRIPT_DIR/../.." && pwd)"
# shellcheck source=versions.env
. "$MPV_SCRIPT_DIR/versions.env"

MPV_BUILD_ROOT="${MPV_BUILD_ROOT:-$REPO_ROOT/build/mpv}"
MPV_OUT_ROOT="${MPV_OUT_ROOT:-$MPV_BUILD_ROOT/out}"

log() { printf '==> %s\n' "$*" >&2; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "缺少命令: $1"
}

require_file() {
  [ -f "$1" ] || die "文件不存在: $1"
}

checkout_ref() {
  local repo=$1 ref=$2
  if git -C "$repo" cat-file -e "$ref^{commit}" 2>/dev/null; then
    git -C "$repo" reset --hard -q
    git -C "$repo" checkout -q --detach "$ref"
    return
  fi
  local ok=0
  for _ in 1 2 3; do
    if git -C "$repo" fetch --depth 1 origin "$ref"; then
      ok=1
      break
    fi
    sleep 5
  done
  [ "$ok" -eq 1 ] || die "git fetch 失败: $repo $ref"
  git -C "$repo" reset --hard -q
  git -C "$repo" checkout -q --detach FETCH_HEAD
}

clone_at() {
  local url=$1 dir=$2 ref=$3
  if [ ! -d "$dir/.git" ]; then
    rm -rf "$dir"
    local ok=0
    for _ in 1 2 3; do
      if git clone -q "$url" "$dir"; then
        ok=1
        break
      fi
      rm -rf "$dir"
      sleep 5
    done
    [ "$ok" -eq 1 ] || die "git clone 失败: $url"
  fi
  checkout_ref "$dir" "$ref"
}

grep_binary() {
  local file=$1 pattern=$2
  grep -aqE "$pattern" "$file"
}

sha256_of() {
  sha256sum "$1" | awk '{print $1}'
}
