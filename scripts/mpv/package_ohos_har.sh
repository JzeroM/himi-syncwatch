#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

INPUT_HAR="${1:-$REPO_ROOT/plugins/himi_mpv_ohos/ohos/hars/mpv.har}"
LIBMPV="${2:-$MPV_OUT_ROOT/ohos/libmpv.so}"
OUTPUT="${3:-$REPO_ROOT/plugins/himi_mpv_ohos/ohos/hars/mpv.har}"
VERSION="${4:-$OHOS_HAR_VERSION}"

require_file "$INPUT_HAR"
require_file "$LIBMPV"
require_cmd tar
require_cmd python3

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/package"
tar -xzf "$INPUT_HAR" -C "$TMP"
[ -f "$TMP/package/libs/arm64-v8a/libmpv.so" ] || die "har 结构异常"
[ -f "$TMP/package/libs/arm64-v8a/libmpv_wrapper.so" ] || die "har 缺少 libmpv_wrapper.so"

cp -f "$LIBMPV" "$TMP/package/libs/arm64-v8a/libmpv.so"

python3 - "$TMP/package/oh-package.json5" "$VERSION" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
data = json.loads(path.read_text())
data['version'] = sys.argv[2]
path.write_text(json.dumps(data, ensure_ascii=False, separators=(',', ':')))
PY

mkdir -p "$(dirname "$OUTPUT")"
tar --sort=name --mtime='UTC 2020-01-01' --owner=0 --group=0 \
  --numeric-owner -C "$TMP" -czf "$OUTPUT" package

python3 - "$OUTPUT" "$VERSION" <<'PY'
import sys
import tarfile
path, version = sys.argv[1:3]
with tarfile.open(path, 'r:gz') as tf:
    names = tf.getnames()
    assert 'package/libs/arm64-v8a/libmpv.so' in names
    assert 'package/libs/arm64-v8a/libmpv_wrapper.so' in names
    assert 'package/oh-package.json5' in names
    text = tf.extractfile('package/oh-package.json5').read().decode()
    assert f'"version":"{version}"' in text, text
PY

sha256sum "$OUTPUT"
log "HarmonyOS har 更新完成: $OUTPUT ($VERSION)"
