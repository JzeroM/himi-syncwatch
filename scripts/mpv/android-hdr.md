# Android libmpv HDR note

The Android MPV surface path (`himi_mpv_android`) uses `gpu-next` + the Android EGL/GLES context (the stock libmpv build has
libplacebo Vulkan disabled).
Stock `libmpv-android-video-build` does not advertise the source color space to
libplacebo and does not set `ANativeWindow` data space, so HDR content is
tone-mapped to SDR even on an HDR panel.

Apply `scripts/mpv/patches/android-hdr-colorspace.patch` to the libmpv source and rebuild it.

The patch adds `preferred_csp` for the Android Vulkan/GLES contexts and sets
`ANativeWindow_setBuffersDataSpace(BT2020_PQ / BT2020_HLG)` before present.
HDR static metadata (`AHardwareBuffer`/`VK_EXT_hdr_metadata`) is still a
follow-up if the target display requires it.

The app-side surface host and MPV options are already wired; only the libmpv
build needs this capability. After rebuilding, point `MEDIA_KIT_ANDROID_LIBMPV_DIR`
at the directory containing `full-arm64-v8a.jar`, `full-armeabi-v7a.jar` and
`full-x86_64.jar` before running the Gradle build.
