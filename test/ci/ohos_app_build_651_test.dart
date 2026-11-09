import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 651：鸿蒙同时产出 HAP + APP 包。
///
/// 【HAP vs APP】
/// - HAP：单模块安装包，用于设备调试安装（`hdc install xxx.hap`）
/// - APP：完整应用包（含各模块 hap + pack.info），用于 AppGallery /
///   企业分发。**不能直接安装到设备**。
///
/// 【为什么不能只改 flutter 命令】`flutter build hap` 只产出 .hap，
/// 没有 .app 支持。必须用 hvigor 的 `assembleApp`，且：
/// - 必须 `--mode project`（`--mode module` 报「任务不存在」）
/// - 必须 JAVA 在 PATH（否则 `spawn java ENOENT`）
void main() {
  String read(String p) => File(p).readAsStringSync();

  const localScript = 'scripts/build_ohos_local.sh';
  const packScript = 'scripts/ohos_pack.sh';

  group('① build_ohos_local.sh 同时构建 HAP + APP', () {
    late String src;

    setUp(() => src = read(localScript));

    test('有 build_app() 且调用 assembleApp', () {
      expect(src, contains('build_app()'));
      expect(src, contains('hvigorw assembleApp'));
    });

    test('assembleApp 用 --mode project（不是 module）', () {
      final start = src.indexOf(r'build_app()');
      expect(start, greaterThan(-1));
      final body = src.substring(start, start + 900);
      expect(body, contains('--mode project'));
      expect(
        body,
        isNot(contains('--mode module')),
        reason: '--mode module 会报「任务不存在」',
      );
    });

    test('构建前检查 java（防 spawn java ENOENT）', () {
      final start = src.indexOf(r'build_app()');
      final body = src.substring(start, start + 900);
      expect(body, contains('command -v java'));
    });

    test('APP 产物路径为 ohos/build/outputs/default/*.app', () {
      expect(src, contains('ohos/build/outputs/default/ohos-default-unsigned.app'));
    });

    test('hap 与 app 都走签名（sign_one 两次调用）', () {
      expect(src, contains(r'sign_one "$INPUT" hap'));
      expect(src, contains(r'sign_one "$APP_INPUT" app'));
    });

    test('清理逻辑同时覆盖 .hap 与 .app', () {
      final start = src.indexOf(r'find "$OUT_DIR" -maxdepth 1');
      expect(start, greaterThan(-1));
      final body = src.substring(start, start + 400);
      expect(body, contains("'*-local-signed.hap'"));
      expect(body, contains("'*-local-signed.app'"));
    });
  });

  group('② ohos_pack.sh 支持 .app 输入', () {
    late String src;

    setUp(() => src = read(packScript));

    test('按扩展名识别输入类型', () {
      expect(src, contains('IS_APP'));
      expect(src, contains('*.app)'));
    });

    test('.app 跳过整个重打包准备流程（无 libs/resources 目录）', () {
      // .app 内部只有 entry-default.hap + pack.info + pac.json，
      // 没有 libs/resources/ets 等目录 → 不能走 app_packing_tool。
      final idx = src.indexOf(r'if [ "$IS_APP" = "1" ]');
      expect(idx, greaterThan(-1));
      final block = src.substring(idx, idx + 900);
      expect(block, contains(r'cp "$INPUT"'));
      expect(block, contains('unsigned.app'));
      expect(block, contains('跳过重打包'));
      // 模板准备（WORK=...）必须在 else 分支内。
      final elseIdx = block.indexOf('else');
      expect(elseIdx, greaterThan(-1));
      expect(block.substring(elseIdx), contains(r'WORK="$TMP/work"'));
    });

    test('.hap 仍走 app_packing_tool 重打包（版本号写入）', () {
      final idx = src.indexOf(r'if [ "$IS_APP" = "1" ]');
      final block = src.substring(idx, idx + 4000);
      expect(block, contains('--mode hap'));
      expect(block, contains('--out-path'));
    });

    test('签名与校验用 sign-app / verify-app（两种格式通用）', () {
      expect(src, contains('sign-app'));
      expect(src, contains('verify-app'));
    });

    test('输出提示按类型区分（HAP / APP）', () {
      expect(src, contains('KIND="HAP"'));
      expect(src, contains('KIND="APP"'));
      expect(src, contains(r'echo "$KIND: $OUTPUT"'));
    });
  });

  group('③ 版本号', () {
    test('pubspec 为 1.5.71+651', () {
      final src = read('pubspec.yaml');
      expect(src, contains('version: 1.5.71+651'));
    });
  });
}
