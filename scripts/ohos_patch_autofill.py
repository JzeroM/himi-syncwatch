#!/usr/bin/env python3
"""Patch Flutter-OH 3.35 autofill helper for SDKs lacking API 26 autofill types.

DevEco command-line-tools 26.0.0.461 ships an API 26 SDK whose
@ohos.app.ability.autoFillManager.d.ts does not export ViewData,
FillRequest, AutoFillCallback, etc. Flutter-OH 3.35's embedding references
those types, so ArkTS compilation fails before HAP packaging.

Autofill is optional for HAP playback. This patch makes the helper compile
without the missing SDK declarations: rendering/requesting autofill becomes
a no-op, while the rest of the embedding is unchanged.
"""

from pathlib import Path
import sys


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} <OhosAutoFillHelper.ets>", file=sys.stderr)
        return 2

    path = Path(sys.argv[1])
    if not path.is_file():
        print(f"file not found: {path}", file=sys.stderr)
        return 1

    source = path.read_text(encoding="utf-8")
    if "autoFillManager.ViewData" not in source:
        print(f"already patched: {path}")
        return 0

    patched = source
    patched = patched.replace("autoFillManager.AutoFillType", "number")
    patched = patched.replace("autoFillManager.AutoFillTriggerType", "number")
    patched = patched.replace("autoFillManager.ViewData", "OhosViewData")
    patched = patched.replace("autoFillManager.FillFailureResult", "FillFailureResult")
    patched = patched.replace("autoFillManager.AutoFillCallback", "AutoFillCallback")
    patched = patched.replace("autoFillManager.SaveRequest", "SaveRequest")
    patched = patched.replace(" as autoFillManager.FillRequest", "")
    patched = patched.replace(
        "autoFillManager.requestAutoFill(uiContext, fillRequest, callback);",
        "onFailure(-1);",
    )
    patched = patched.replace(
        "autoFillManager.requestAutoSave(uiContext, saveRequest, napiCallback);",
        "autoFillManager.requestAutoSave(uiContext, napiCallback);",
    )

    marker = "const TAG = 'OhosAutoFillHelper';"
    definitions = """interface FillFailureResult {
  errCode: number;
}

interface AutoFillCallback {
  onSuccess(viewData: OhosViewData): void;
  onFailure(result: FillFailureResult): void;
}

interface SaveRequest {
  viewData: OhosViewData;
}

"""
    if marker not in patched:
        print(f"unexpected helper layout: {path}", file=sys.stderr)
        return 1
    patched = patched.replace(marker, definitions + marker, 1)

    if patched == source:
        print(f"no changes applied: {path}", file=sys.stderr)
        return 1

    path.write_text(patched, encoding="utf-8")
    print(f"patched: {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
