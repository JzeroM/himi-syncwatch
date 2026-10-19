import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:win32/win32.dart';

import 'windows_dib.dart';

Future<bool> copyPngToClipboard(Uint8List pngBytes) async {
  if (!Platform.isWindows) return false;
  try {
    final dib = buildDibFromPng(pngBytes);
    if (dib == null) return false;

    var opened = false;
    for (var attempt = 0; attempt < 8; attempt++) {
      if (OpenClipboard(0) != 0) {
        opened = true;
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    if (!opened) return false;

    try {
      if (EmptyClipboard() == 0) return false;
      final handle = GlobalAlloc(GLOBAL_ALLOC_FLAGS.GMEM_MOVEABLE, dib.length);
      if (handle == nullptr) return false;
      final locked = GlobalLock(handle);
      if (locked == nullptr) {
        GlobalFree(handle);
        return false;
      }
      locked.cast<Uint8>().asTypedList(dib.length).setAll(0, dib);
      GlobalUnlock(handle);
      if (SetClipboardData(CLIPBOARD_FORMAT.CF_DIB, handle.address) == 0) {
        GlobalFree(handle);
        return false;
      }
      return true;
    } finally {
      CloseClipboard();
    }
  } catch (_) {
    return false;
  }
}
