# media-kit vendor notice

This directory contains packages copied from NipaPlay-Reload's media-kit fork:

- Source: https://github.com/AimesSoft/NipaPlay-Reload
- media-kit upstream fork: https://github.com/AimesSoft/media-kit
- media-kit fork commit: 7a2135661ff37a717f11d6012fefa56cae27ef36

Retained packages:

- `media_kit` / `media_kit_video` — himi_mpv（MPV 引擎）的 libmpv 驱动 +
  纹理通道底层库（himi_mpv_android / himi_mpv_windows 直接使用其
  `Player` / `VideoController`）。**不是独立播放引擎**：media_kit 引擎层
  （`NipaMediaKitAdapter` / `MediaKitPlayerAdapter` / `PlayerEngine.mediaKit`）
  已随 694 引擎收敛（各平台仅 MDK / Erika / MPV）移除。
- `media-kit-upstream/libs/android/media_kit_libs_android_video` — 安卓
  libmpv.so / FFmpeg .so 打包（himi_mpv `System.loadLibrary("mpv")` 的供给者）。
- `media-kit-upstream/libs/windows/media_kit_libs_windows_video` — Windows
  `libmpv-2.dll` 打包（Qt 播放窗 / himi_mpv_windows 的供给者）。

移除说明：`media_kit_libs_video`（universal）与 `media_kit_libs_ios_video`
已移除——iOS 走 Erika，不消费 libmpv。

Copyright (c) 2025 MCDFsteve and NipaPlay contributors.
Licensed under the MIT License; see each package's LICENSE file.
