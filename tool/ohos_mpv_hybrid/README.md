# Flutter-OH MPV hybrid platform view patch

These patches are required for HarmonyOS MPV native-surface output.

- `engine_arkts.patch`: ArkTS embedding changes (hybrid `RENDER_TYPE_DISPLAY`,
  `XComponent` translucency, SDK 26 autofill compile compatibility).
- `framework_platform_views.patch`: Flutter framework OHOS hybrid
  `resize`/`offset`/`dispose` channel wiring.

Apply to the pinned Flutter-OH checkout, rebuild the embedding HAR, and replace
`flutter_embedding_release.har` referenced by `ohos/entry/oh-package-lock.json5`.
