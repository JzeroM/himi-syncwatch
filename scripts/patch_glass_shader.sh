#!/usr/bin/env bash
# 698 N50：liquid_glass_widgets 水滴 shader 定制守卫（vendored 版）。
#
# 【重要】包是 **vendored**（pubspec: path: third_party/liquid_glass_widgets），
# shader 的全部 himi 定制（N39 凸透镜剖面 / N42 轮廓色散环 / ×4.0 色散 /
# 双纹理复合）都直接提交在 third_party 内（git 持久，pub get 不会重置）。
# 本脚本只做**在位校验**——防止 third_party 被整目录覆盖更新时静默丢失
# 定制（丢失则构建前报错，提示恢复 vendored patch）。
set -euo pipefail

FRAG="third_party/liquid_glass_widgets/shaders/interactive_indicator.frag"

if [[ ! -f "$FRAG" ]]; then
  echo "glass_shader_guard: 缺少 $FRAG（vendored 包丢失？）" >&2
  exit 1
fi

MISSING=0
for mark in \
  'PATCH himi' \
  'uLensZoom' \
  'ringWeight' \
  'compositeFetch'; do
  if ! grep -q "$mark" "$FRAG"; then
    echo "glass_shader_guard: 缺失定制标记 '$mark'——vendored patch 被覆盖！" >&2
    MISSING=1
  fi
done

if [[ "$MISSING" -ne 0 ]]; then
  exit 1
fi

echo "glass_shader_guard: vendored 定制全部在位"
