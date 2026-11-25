#!/usr/bin/env bash
# 698 N49：liquid_glass_widgets 水滴镜片 shader 物理修正 patch（幂等）。
#
# 背景：包内 interactive_indicator.frag 的色散是「横向色差近似」且形变
# 衰减过柔，与酷安参考（透镜物理）不符。本脚本打三处 patch：
#   1. 形变分布：edgeInfluence 平方衰减 → 一次方（边缘物理扭曲明显）
#   2. 折射倍率：uSize.y × 0.35 → × 0.5（条体过透镜放大弯折，非缩小）
#   3. 色散模型：对称平移近似 → 柯西波长折射率（真实棱镜：蓝光 n 大
#      弯折强、红光 n 小弯折弱，透镜边缘「内蓝外红」彩虹环）
#
# pub get 会重置 pub cache → 本脚本须在每次 pub get 之后执行
#（CI release.yml 各构建 job / scripts/build_ohos_local.sh 已集成）。
# 幂等：已 patch（含标记）则跳过。
set -euo pipefail

FRAG="$(find "${PUB_CACHE:-$HOME/.pub-cache}/hosted/pub.dev" \
  -path '*liquid_glass_widgets*/shaders/interactive_indicator.frag' \
  | sort | tail -1)"

if [[ -z "$FRAG" || ! -f "$FRAG" ]]; then
  echo "patch_glass_shader: 未找到 interactive_indicator.frag（跳过）"
  exit 0
fi

if grep -q 'PATCH himi N49' "$FRAG"; then
  echo "patch_glass_shader: 已 patch，跳过"
  exit 0
fi

python3 - "$FRAG" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p).read()

# ① 形变分布：平方衰减 → 一次方（sharper 边缘形变）。
old = """  edgeInfluence = edgeInfluence * edgeInfluence;"""
assert old in s, 'edge falloff anchor'
new = """  // [PATCH himi N49] 一次方衰减：边缘形变明显（图标经过边缘物理扭曲）。
  // edgeInfluence = edgeInfluence * edgeInfluence;"""
s = s.replace(old, new, 1)

# ② 折射倍率 ×0.35 → ×0.5（放大弯折）。
old = "vec2 edgeOffsetLogical = surfaceNormal * edgeInfluence * bendStrength * uSize.y * 0.35;"
assert old in s, 'bend scale anchor'
new = "vec2 edgeOffsetLogical = surfaceNormal * edgeInfluence * bendStrength * uSize.y * 0.5; // [PATCH himi N49] 放大弯折"
s = s.replace(old, new, 1)

# ③ 真实棱镜色散（柯西近似）：替换对称平移近似段。
old = """  // TWEAK: (0.12) - subtle chromatic shift for "Apple style" refraction
  vec2 distort = surfaceNormal * edgeInfluence * uChromaticAberration;
  vec2 chromaticShift = distort * 0.12; """
assert old in s, 'chromatic anchor'
new = """  // [PATCH himi N49] 真实棱镜色散（柯西波长折射率近似）：
  // 蓝光 n 大弯折强、红光 n 小弯折弱——色散量跟随折射梯度（弯折越强
  // 分离越明显），凸透镜边缘「内蓝外红」彩虹环。
  float dispersion = uChromaticAberration * 0.35;
  vec2 offR = edgeOffsetLogical * (1.0 - dispersion);
  vec2 offG = edgeOffsetLogical;
  vec2 offB = edgeOffsetLogical * (1.0 + dispersion);"""
s = s.replace(old, new, 1)

# ④ 采样段：三通道按各自折射偏移采样（替换 chromaticShift 平移采样）。
old = """  vec3 bg;
  if (uHasBackground > 0.5) {
    // Physical texture size (actual pixel dimensions after DPR capture).
    // uBackgroundSize is in LOGICAL pixels; the texture has uDpr× more texels.
    vec2 physBgSize = uBackgroundSize * uDpr;
    vec2 invPhysBgSize = 1.0 / physBgSize;

    if (uChromaticAberration < 0.001) {
      // No chromatic aberration — single bilinear fetch.
      bg = textureBilinear(localRefracted / uBackgroundSize, physBgSize, invPhysBgSize).rgb;
    } else {
      // Chromatic aberration: separate RGB channels with bilinear filtering.
      vec3 colR = textureBilinear((localRefracted + chromaticShift) / uBackgroundSize, physBgSize, invPhysBgSize).rgb;
      vec3 colG = textureBilinear(localRefracted / uBackgroundSize, physBgSize, invPhysBgSize).rgb;
      vec3 colB = textureBilinear((localRefracted - chromaticShift) / uBackgroundSize, physBgSize, invPhysBgSize).rgb;
      bg = vec3(colR.r, colG.g, colB.b);
    }
  } else {"""
assert old in s, 'sampling anchor'
new = """  vec3 bg;
  if (uHasBackground > 0.5) {
    // Physical texture size (actual pixel dimensions after DPR capture).
    // uBackgroundSize is in LOGICAL pixels; the texture has uDpr× more texels.
    vec2 physBgSize = uBackgroundSize * uDpr;
    vec2 invPhysBgSize = 1.0 / physBgSize;

    if (uChromaticAberration < 0.001) {
      // No chromatic aberration — single bilinear fetch.
      bg = textureBilinear(localRefracted / uBackgroundSize, physBgSize, invPhysBgSize).rgb;
    } else {
      // [PATCH himi N49] 真实色散采样：各波长通道按自身折射偏移采样。
      #ifdef LGR_GLES_FLIP_SAMPLE_Y
        vec2 refR = posInBg + vec2(offR.x, -offR.y);
        vec2 refG = posInBg + vec2(offG.x, -offG.y);
        vec2 refB = posInBg + vec2(offB.x, -offB.y);
      #else
        vec2 refR = posInBg - offR;
        vec2 refG = posInBg - offG;
        vec2 refB = posInBg - offB;
      #endif
      vec3 colR = textureBilinear(refR / uBackgroundSize, physBgSize, invPhysBgSize).rgb;
      vec3 colG = textureBilinear(refG / uBackgroundSize, physBgSize, invPhysBgSize).rgb;
      vec3 colB = textureBilinear(refB / uBackgroundSize, physBgSize, invPhysBgSize).rgb;
      bg = vec3(colR.r, colG.g, colB.b);
    }
  } else {"""
s = s.replace(old, new, 1)

open(p, 'w').write(s)
print('patched:', p)
PYEOF

echo "patch_glass_shader: done"
