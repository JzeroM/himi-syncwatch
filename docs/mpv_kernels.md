# MPV 内核构建与接入

三端 libmpv 由 GitHub Actions 自编译，版本固定在 `scripts/mpv/versions.env`。

## 工作流

`.github/workflows/mpv-kernels.yml` 可手动触发，也被 `release.yml` 复用：

| Job | 产物 |
|---|---|
| `ohos` | `libmpv.so`（aarch64，`ohosvk` + OHCodec Vulkan + DoVi） |
| `android` | `full-<abi>.jar`（arm64-v8a / armeabi-v7a / x86_64） |
| `windows-toolchain` | 缓存的 MinGW 工具链 |
| `windows-mpv` | `libmpv-2.dll` + `libmpv.dll.a` |

缓存只保留 Windows 工具链；OpenHarmony SDK 与 Android SDK/NDK 每次下载，避免超过每仓库 10 GB 缓存上限。artifact 保留 3 天。

## 本地构建

OHOS 需要 `rustup`、`aarch64-unknown-linux-ohos` target 与 `cargo-c`（脚本会自动安装）。

```bash
bash scripts/mpv/build_ohos.sh
bash scripts/mpv/build_android.sh arm64-v8a
bash scripts/mpv/build_windows.sh all
bash scripts/mpv/verify_kernels.sh
```

## 鸿蒙打包

```bash
bash scripts/mpv/package_ohos_har.sh \
  plugins/himi_mpv_ohos/ohos/hars/mpv.har \
  build/mpv/out/ohos/libmpv.so \
  plugins/himi_mpv_ohos/ohos/hars/mpv.har \
  1.0.1
```

只替换 har 内的 `libmpv.so`，保留 `libmpv_wrapper.so`、`libaki_jsbind.so`、`libc++_shared.so`。

## Android 接入

`media_kit_libs_android_video` 优先读取 `MEDIA_KIT_ANDROID_LIBMPV_DIR`。目录内需有：

```text
full-arm64-v8a.jar
full-armeabi-v7a.jar
full-x86_64.jar
```

未设置时回退到 media-kit v1.1.8 官方 jar。

MediaCodec DoVi 补丁位于 `scripts/mpv/patches/android-mediacodec-dovi.patch`，按 PTS 将 RPU side data 挂到解码输出帧；失败时由 mpv 自动回退软解。可用 `NIPAPLAY_ANDROID_HWDEC=no` 强制软解，或用 `NIPAPLAY_ANDROID_HWDEC=mediacodec-copy` 回退 8bit copy。

## Windows 接入

`media_kit_video` 与 `media_kit_libs_windows_video` 优先读取 `MEDIA_KIT_LIBMPV_DIR`。目录内需有：

```text
libmpv-2.dll
libmpv.dll.a
include/mpv/*.h
```

未设置时回退到原有 media-kit / shinchiro 下载流程。Windows HDR10/DoVi 使用 FFmpeg libplacebo 滤镜输出 SDR（Windows 走 auto-copy 软件帧，无需 hwdownload）；Windows 构建关闭 libcurl 与 VapourSynth，HTTP/HLS 网络走 FFmpeg；可用 `NIPAPLAY_DISABLE_WINDOWS_LIBPLACEBO_HDR=1` 关闭。

## 已知限制

- DoVi P7 仅解基础层，不做 FEL。
- 鸿蒙 Flutter Texture 输出的颜色空间为 SDR；真 HDR 直出需要后续 XComponent 通路。
- 最终颜色与性能必须真机验收，CI 只验证构建、架构、符号和依赖。
