#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-local}"

case "$MODE" in
  local)
    exec "$ROOT/scripts/build_ohos_local.sh"
    ;;
  *)
    echo "用法: $0 local" >&2
    echo "HarmonyOS 对外分发走 AppGallery 官方测试，不再生成 GitHub 侧载包" >&2
    exit 2
    ;;
esac
