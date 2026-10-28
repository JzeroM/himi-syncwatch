# Android libmpv HDR note

The Android MPV surface path (`himi_mpv_android`) uses `gpu-next` + the Android EGL/GLES context (the stock libmpv build has
libplacebo Vulkan disabled).
Stock `libmpv-android-video-build` does not advertise the source color space to
libplacebo and does not set `ANativeWindow` data space, so HDR content is
tone-mapped to SDR even on an HDR panel.

The patch `scripts/mpv/patches/android-hdr-colorspace.patch` is applied automatically by `scripts/mpv/build_android.sh`; the build fails if it cannot be applied.

The patch adds `preferred_csp` for the Android Vulkan/GLES contexts and sets
`ANativeWindow_setBuffersDataSpace(BT2020_PQ / BT2020_HLG)` before present.
HDR static metadata (`AHardwareBuffer`/`VK_EXT_hdr_metadata`) is still a
follow-up if the target display requires it.

The app-side surface host and MPV options are already wired. After rebuilding,
point `MEDIA_KIT_ANDROID_LIBMPV_DIR` at the directory containing
`full-arm64-v8a.jar`, `full-armeabi-v7a.jar` and `full-x86_64.jar` before
running the Gradle build. `build_android.sh` checks the unstripped `libmpv.so` for
`vo_android_preferred_csp` before packaging.
