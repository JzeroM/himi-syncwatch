import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

/// 环境变量服务 — 通过 FFI 调用 libc setenv()。
///
/// mdk 部分渲染选项（如 EGL_SDR_DEPTH）只接受环境变量，
/// 需在 mdk 库读取前设置。Flutter/Dart 无法直接设置环境变量，
/// 故通过 FFI 调用 POSIX setenv()。
class EnvService {
  EnvService._();
  static final EnvService instance = EnvService._();

  /// POSIX setenv(name, value, overwrite)
  static final _setenv = _resolveSetenv();

  static int Function(Pointer<Utf8>, Pointer<Utf8>, int)? _resolveSetenv() {
    try {
      if (Platform.isAndroid || Platform.isLinux) {
        final lib = DynamicLibrary.process();
        return lib
            .lookupFunction<
                Int32 Function(Pointer<Utf8>, Pointer<Utf8>, Int32),
                int Function(Pointer<Utf8>, Pointer<Utf8>, int)>('setenv');
      }
    } catch (_) {
      // 非 POSIX 平台或符号不存在
    }
    return null;
  }

  /// 设置环境变量。Android/Linux 有效，其他平台静默忽略。
  ///
  /// 返回是否成功设置。
  bool set(String key, String value) {
    final fn = _setenv;
    if (fn == null) return false;
    final keyPtr = key.toNativeUtf8();
    final valuePtr = value.toNativeUtf8();
    try {
      return fn(keyPtr, valuePtr, 1) == 0;
    } catch (_) {
      return false;
    } finally {
      malloc.free(keyPtr);
      malloc.free(valuePtr);
    }
  }

  /// 8-bit 渲染表面（EGL_SDR_DEPTH=8，1.1.193）：
  /// 强制 mdk 为 SDR 输出创建 8-bit EGL 表面（默认 10-bit RGB10A2）。
  /// Adreno 740 的 10-bit 表面跨上下文采样疑似损坏（类似 fvp#374）。
  bool applyRenderDepth8() => set('EGL_SDR_DEPTH', '8');
}
