# Anime4K / ArtCNN vendor notice

GLSL 用户着色器（mpv `glsl-shaders` 用），供 Anime4K 实时超分/锐化。

## 来源一：Anime4K（14 个文件，glsl/ 目录）

- Source: https://github.com/bloc97/Anime4K
- Path: glsl/Upscale, glsl/Upscale+Denoise, glsl/Restore
- Copyright (c) 2019 bloc97 — MIT License（见 LICENSE-anime4k）

| 文件 | 用途 |
|---|---|
| Anime4K_Upscale_CNN_x2_{S,M,L}.glsl | 2x 超分（轻/中/重） |
| Anime4K_Upscale_Denoise_CNN_x2_{S,M,L}.glsl | 2x 超分 + 降噪 |
| Anime4K_Restore_CNN_{S,M,L}.glsl | 线条修复 |
| Anime4K_Restore_CNN_Soft_{S,M,L}.glsl | 线条修复（柔和） |
| Anime4K_AutoDownscalePre_x2.glsl | 超分前自动预缩放 |
| Anime4K_Clamp_Highlights.glsl | 高光钳制（链尾保护） |

## 来源二：ArtCNN（2 个文件，glsl/ 目录）

- Source: https://github.com/Artoriuz/ArtCNN
- Path: GLSL/
- Copyright (c) 2024 João Chrisóstomo — MIT License（见 LICENSE-artcnn）

| 文件 | 用途 |
|---|---|
| ArtCNN_C4F32.glsl | 端到端 2x 超分（高质量，C4F32） |
| ArtCNN_C4F16.glsl | 端到端 2x 超分（轻量，C4F16） |

> 说明：链的组装/守卫/接入代码为本项目自写；此处仅 vendor 上游
> 着色器资产原样（不做修改，出问题可直接对照上游）。
