import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/services/player/anime4k/anime4k_catalog.dart';
import 'package:himi_syncwatch/services/player/anime4k/anime4k_manager.dart';

/// 694：Anime4K 着色器链组装 / 三重守卫 / 资产解包 / 管线落属性 的单测。
///
/// 借鉴 NeoPlayer v1.7.4 的 mpv `glsl-shaders` 管线；**链的组装为本项目
/// 自写纯表**，故可矩阵化断言（8 模式 × 3 质量全枚举）。着色器资产为
/// bloc97/Anime4K + Artoriuz/ArtCNN（均 MIT）vendor 原样。
///
/// 覆盖：
/// 1. 链组装矩阵（每档的精确文件序 + 引用文件真实存在）
/// 2. 三重守卫（关 / 4K / HDR / 强开）
/// 3. 资产解包（`debugDirOverride` 注入 + 幂等）
/// 4. 管线落 `glsl-shaders`（跳过清空 / 生效拼接 / 失败清空）
/// 5. AppSettings 五字段往返
/// 6. 接线源码断言（四端调试面板 + Qt 状态属性 + 命令路由）
void main() {
  final glslDir = Directory('third_party/anime4k/glsl');

  // ────────────────────────────────────────────────────────────
  // 1. 链组装矩阵
  // ────────────────────────────────────────────────────────────
  group('Anime4KShaderCatalog.chain 组装矩阵', () {
    test('off → 空链', () {
      for (final q in Anime4KQuality.values) {
        expect(Anime4KShaderCatalog.chain(Anime4KMode.off, q), isEmpty);
      }
    });

    test('ArtCNN：Fast=C4F16，其余=C4F32（单文件端到端）', () {
      expect(
        Anime4KShaderCatalog.chain(Anime4KMode.artCnn, Anime4KQuality.fast),
        ['ArtCNN_C4F16.glsl'],
      );
      expect(
        Anime4KShaderCatalog.chain(
            Anime4KMode.artCnn, Anime4KQuality.balanced),
        ['ArtCNN_C4F32.glsl'],
      );
      expect(
        Anime4KShaderCatalog.chain(Anime4KMode.artCnn, Anime4KQuality.high),
        ['ArtCNN_C4F32.glsl'],
      );
    });

    // 每档的期望链（q 由质量档映射 S/M/L）。
    final expectations =
        <Anime4KMode, String Function(String q)>{
      Anime4KMode.a: (q) =>
          'Anime4K_AutoDownscalePre_x2.glsl|Anime4K_Upscale_CNN_x2_$q.glsl|'
          'Anime4K_Restore_CNN_$q.glsl',
      Anime4KMode.aPlus: (q) =>
          'Anime4K_AutoDownscalePre_x2.glsl|Anime4K_Upscale_CNN_x2_$q.glsl|'
          'Anime4K_Restore_CNN_Soft_$q.glsl',
      Anime4KMode.b: (q) =>
          'Anime4K_AutoDownscalePre_x2.glsl|'
          'Anime4K_Upscale_Denoise_CNN_x2_$q.glsl|Anime4K_Restore_CNN_$q.glsl',
      Anime4KMode.bPlus: (q) =>
          'Anime4K_AutoDownscalePre_x2.glsl|'
          'Anime4K_Upscale_Denoise_CNN_x2_$q.glsl|'
          'Anime4K_Restore_CNN_Soft_$q.glsl',
      Anime4KMode.c: (q) =>
          'Anime4K_AutoDownscalePre_x2.glsl|Anime4K_Upscale_CNN_x2_$q.glsl|'
          'Anime4K_Restore_CNN_$q.glsl|Anime4K_Clamp_Highlights.glsl',
      Anime4KMode.cPlus: (q) =>
          'Anime4K_AutoDownscalePre_x2.glsl|'
          'Anime4K_Upscale_Denoise_CNN_x2_$q.glsl|'
          'Anime4K_Restore_CNN_Soft_$q.glsl|Anime4K_Clamp_Highlights.glsl',
    };

    for (final entry in expectations.entries) {
      for (final q in Anime4KQuality.values) {
        test('${entry.key.id} / ${q.id} → 精确链', () {
          final chain = Anime4KShaderCatalog.chain(entry.key, q);
          expect(chain.join('|'), entry.value(q.sizeTag));
        });
      }
    }

    test('链内引用的文件全部真实存在（防拼写错/漏 vendor）', () {
      final missing = <String>[];
      for (final mode in Anime4KMode.values) {
        for (final q in Anime4KQuality.values) {
          for (final f in Anime4KShaderCatalog.chain(mode, q)) {
            if (!File('${glslDir.path}/$f').existsSync()) missing.add(f);
          }
        }
      }
      expect(missing, isEmpty, reason: '缺失着色器: $missing');
    });

    test('allFileNames 覆盖 16 个 vendor 文件且均存在', () {
      expect(Anime4KShaderCatalog.allFileNames.length, 16);
      for (final f in Anime4KShaderCatalog.allFileNames) {
        expect(File('${glslDir.path}/$f').existsSync(), isTrue,
            reason: '缺失: $f');
      }
    });
  });

  // ────────────────────────────────────────────────────────────
  // 2. 三重守卫
  // ────────────────────────────────────────────────────────────
  group('Anime4KGuard 三重守卫', () {
    Anime4KSkipReason check({
      bool enabled = true,
      Anime4KMode mode = Anime4KMode.b,
      int w = 1920,
      int h = 1080,
      bool hdr = false,
      bool in4k = false,
      bool onHdr = false,
    }) =>
        Anime4KGuard.check(
          enabled: enabled,
          mode: mode,
          videoWidth: w,
          videoHeight: h,
          isHdrContent: hdr,
          in4k: in4k,
          onHdr: onHdr,
        );

    test('总开关关 → off', () {
      expect(check(enabled: false), Anime4KSkipReason.off);
    });

    test('模式 off → off', () {
      expect(check(mode: Anime4KMode.off), Anime4KSkipReason.off);
    });

    test('1080p SDR → 放行', () {
      expect(check(), Anime4KSkipReason.none);
    });

    test('4K+ 默认跳过（长边 ≥3840）', () {
      expect(check(w: 3840, h: 2160), Anime4KSkipReason.highRes);
      expect(check(w: 1920, h: 3840), Anime4KSkipReason.highRes); // 竖屏长边
    });

    test('4K+ 但强开 → 放行', () {
      expect(check(w: 3840, h: 2160, in4k: true), Anime4KSkipReason.none);
    });

    test('HDR 默认跳过', () {
      expect(check(hdr: true), Anime4KSkipReason.hdr);
    });

    test('HDR 但强开 → 放行', () {
      expect(check(hdr: true, onHdr: true), Anime4KSkipReason.none);
    });

    test('4K + HDR 同时命中优先报 4K', () {
      expect(check(w: 3840, h: 2160, hdr: true), Anime4KSkipReason.highRes);
    });
  });

  // ────────────────────────────────────────────────────────────
  // 3. 资产解包
  // ────────────────────────────────────────────────────────────
  group('Anime4KAssets.ensureUnpacked 解包', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('a4k_unpack_test');
    });

    tearDown(() {
      Anime4KAssets.debugDirOverride = null;
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('debugDirOverride 注入 + 写出全部着色器 + 幂等', () async {
      Anime4KAssets.debugDirOverride = () async => tmp.path;
      final dirPath = await Anime4KAssets.ensureUnpacked(bundle: _diskBundle());
      expect(dirPath, tmp.path);

      // 全部 16 个着色器落地且非空。
      for (final name in Anime4KShaderCatalog.allFileNames) {
        final f = File('${tmp.path}${Platform.pathSeparator}$name');
        expect(f.existsSync(), isTrue, reason: '未解包: $name');
        expect(f.lengthSync(), greaterThan(0), reason: '空文件: $name');
      }
      // 幂等标记存在。
      expect(
        File('${tmp.path}${Platform.pathSeparator}.ok').existsSync(),
        isTrue,
      );

      // 幂等：再跑一次不抛、路径一致。
      final again = await Anime4KAssets.ensureUnpacked(bundle: _diskBundle());
      expect(again, tmp.path);
    });
  });

  // ────────────────────────────────────────────────────────────
  // 4. 管线落 glsl-shaders
  // ────────────────────────────────────────────────────────────
  group('Anime4KPipeline.apply 落属性', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('a4k_pipeline_test');
      Anime4KAssets.debugDirOverride = () async => tmp.path;
    });

    tearDown(() {
      Anime4KAssets.debugDirOverride = null;
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('守卫拦截 → glsl-shaders 置空（不残留）', () async {
      final calls = <String, String>{};
      final result = await Anime4KPipeline.apply(
        enabled: true,
        mode: Anime4KMode.b,
        quality: Anime4KQuality.balanced,
        in4k: false,
        onHdr: false,
        videoWidth: 3840,
        videoHeight: 2160,
        isHdrContent: false,
        setProperty: (n, v) async => calls[n] = v,
        bundle: _diskBundle(),
      );
      expect(calls['glsl-shaders'], '');
      expect(result.applied, isFalse);
      expect(result.statusLabel, Anime4KSkipReason.highRes.label);
    });

    test('生效 → 拼接为绝对路径列表（分隔符按平台）', () async {
      final calls = <String, String>{};
      final result = await Anime4KPipeline.apply(
        enabled: true,
        mode: Anime4KMode.cPlus,
        quality: Anime4KQuality.high,
        in4k: false,
        onHdr: false,
        videoWidth: 1920,
        videoHeight: 1080,
        isHdrContent: false,
        setProperty: (n, v) async => calls[n] = v,
        bundle: _diskBundle(),
      );
      expect(result.applied, isTrue);
      final value = calls['glsl-shaders']!;
      final parts =
          value.split(Platform.isWindows ? ';' : ':');
      expect(parts.length, 4); // C+ = AutoDown + Denoise + Soft + Clamp
      for (final p in parts) {
        expect(p.startsWith(tmp.path), isTrue, reason: '非绝对/非解包路径: $p');
        expect(File(p).existsSync(), isTrue, reason: '链指向不存在的文件: $p');
      }
      expect(result.statusLabel, contains('✓'));
    });

    test('setProperty 抛错 → 清空 + 状态行带失败原因', () async {
      final calls = <String, String>{};
      final result = await Anime4KPipeline.apply(
        enabled: true,
        mode: Anime4KMode.a,
        quality: Anime4KQuality.fast,
        in4k: false,
        onHdr: false,
        videoWidth: 1920,
        videoHeight: 1080,
        isHdrContent: false,
        setProperty: (n, v) async {
          calls[n] = v;
          throw StateError('boom');
        },
        bundle: _diskBundle(),
      );
      expect(result.applied, isFalse);
      expect(result.error, contains('boom'));
      expect(result.statusLabel, contains('✗'));
      expect(calls['glsl-shaders'], '');
    });
  });

  // ────────────────────────────────────────────────────────────
  // 4b. 回读校验（三级状态：已挂载 / 写入未生效 / 编译失败）
  // ────────────────────────────────────────────────────────────
  group('Anime4KPipeline.apply 回读校验（三级状态）', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('a4k_readback_test');
      Anime4KAssets.debugDirOverride = () async => tmp.path;
    });

    tearDown(() {
      Anime4KAssets.debugDirOverride = null;
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    Future<Anime4KApplyResult> run({
      Future<String?> Function(String)? readProperty,
      List<String> Function()? recentErrors,
    }) {
      return Anime4KPipeline.apply(
        enabled: true,
        mode: Anime4KMode.b,
        quality: Anime4KQuality.balanced,
        in4k: false,
        onHdr: false,
        videoWidth: 1920,
        videoHeight: 1080,
        isHdrContent: false,
        setProperty: (n, v) async {},
        readProperty: readProperty,
        recentErrors: recentErrors,
        bundle: _diskBundle(),
      );
    }

    test('回读非空 → ✓ 已挂载渲染中', () async {
      final r = await run(readProperty: (n) async => 'shaderA:shaderB');
      expect(r.applied, isTrue);
      expect(r.statusLabel, contains('已挂载渲染中'));
    });

    test('回读为空 → ⚠ 写入未生效', () async {
      final r = await run(readProperty: (n) async => '');
      expect(r.applied, isFalse);
      expect(r.statusLabel, contains('写入未生效'));
    });

    test('回读 null（无法校验）→ 乐观 ✓（已写入）', () async {
      final r = await run(readProperty: (n) async => null);
      expect(r.applied, isTrue);
      expect(r.statusLabel, contains('已写入'));
    });

    test('无 readProperty 回调 → 乐观 ✓', () async {
      final r = await run();
      expect(r.applied, isTrue);
      expect(r.statusLabel, contains('✓'));
    });

    test('着色器编译错误 → ⚠ 编译失败（回读非空但没编译过）', () async {
      final r = await run(
        readProperty: (n) async => 'shader',
        recentErrors: () => ['无关日志', 'Failed to compile shader xyz'],
      );
      expect(r.statusLabel, contains('编译失败'));
      expect(r.error, contains('compile shader'));
    });
  });

  // ────────────────────────────────────────────────────────────
  // 4c. ArtCNN 临时降档判定（高%8≠0 → C+；设置不动）
  // ────────────────────────────────────────────────────────────
  group('Anime4KResolve ArtCNN 临时降档', () {
    test('720x540（高%8≠0）→ 降 C+', () {
      expect(Anime4KResolve.isArtCnnUnsafe(videoHeight: 540), isTrue);
      expect(
        Anime4KResolve.resolveEffectiveMode(
            mode: Anime4KMode.artCnn, videoHeight: 540),
        Anime4KMode.cPlus,
      );
    });

    test('1280x720（高%8=0）→ 保持 ArtCNN', () {
      expect(Anime4KResolve.isArtCnnUnsafe(videoHeight: 720), isFalse);
      expect(
        Anime4KResolve.resolveEffectiveMode(
            mode: Anime4KMode.artCnn, videoHeight: 720),
        Anime4KMode.artCnn,
      );
    });

    test('尺寸未知（0）→ 保守降 C+（防初次应用撞未知片源）', () {
      expect(Anime4KResolve.isArtCnnUnsafe(videoHeight: 0), isTrue);
      expect(
        Anime4KResolve.resolveEffectiveMode(
            mode: Anime4KMode.artCnn, videoHeight: 0),
        Anime4KMode.cPlus,
      );
    });

    test('1080p / DVD 720x480 → 保持 ArtCNN', () {
      for (final h in [1080, 480, 576, 720]) {
        expect(
          Anime4KResolve.resolveEffectiveMode(
              mode: Anime4KMode.artCnn, videoHeight: h),
          Anime4KMode.artCnn,
          reason: 'height=$h 高%8=0 应保持 ArtCNN',
        );
      }
    });

    test('其它模式不受影响（a/b/c 任意高度都不降档）', () {
      for (final m in [
        Anime4KMode.a,
        Anime4KMode.b,
        Anime4KMode.c,
        Anime4KMode.cPlus,
        Anime4KMode.bPlus,
      ]) {
        expect(
          Anime4KResolve.resolveEffectiveMode(mode: m, videoHeight: 540),
          m,
          reason: '${m.id} 不该被降档',
        );
      }
    });

    test('奇数/非 8 倍数高度也判不安全', () {
      for (final h in [540, 548, 486, 242, 1001]) {
        expect(Anime4KResolve.isArtCnnUnsafe(videoHeight: h), isTrue,
            reason: 'height=$h 高%8≠0 应判不安全');
      }
    });
  });

  // ────────────────────────────────────────────────────────────
  // 5. AppSettings 五字段往返
  // ────────────────────────────────────────────────────────────
  group('AppSettings Anime4K 五字段', () {
    test('toJson/fromJson 往返 + 默认值', () {
      const s = AppSettings();
      expect(s.anime4kEnabled, isFalse);
      expect(s.anime4kMode, 'b');
      expect(s.anime4kQuality, 'balanced');
      expect(s.anime4kIn4k, isFalse);
      expect(s.anime4kOnHdr, isFalse);

      final custom = s.copyWith(
        anime4kEnabled: true,
        anime4kMode: 'c_plus',
        anime4kQuality: 'high',
        anime4kIn4k: true,
        anime4kOnHdr: true,
      );
      final back = AppSettings.fromJson(custom.toJson());
      expect(back.anime4kEnabled, isTrue);
      expect(back.anime4kMode, 'c_plus');
      expect(back.anime4kQuality, 'high');
      expect(back.anime4kIn4k, isTrue);
      expect(back.anime4kOnHdr, isTrue);
    });

    test('旧存档无字段 → 全默认（向后兼容）', () {
      final back = AppSettings.fromJson(const <String, dynamic>{});
      expect(back.anime4kEnabled, isFalse);
      expect(back.anime4kMode, 'b');
      expect(back.anime4kQuality, 'balanced');
      expect(back.anime4kIn4k, isFalse);
      expect(back.anime4kOnHdr, isFalse);
    });

    test('catalog fromId 容错（未知 id → 安全默认）', () {
      expect(Anime4KMode.fromId('nope'), Anime4KMode.off);
      expect(Anime4KMode.fromId(null), Anime4KMode.off);
      expect(Anime4KQuality.fromId('nope'), Anime4KQuality.balanced);
      expect(Anime4KQuality.fromId(null), Anime4KQuality.balanced);
    });
  });

  // ────────────────────────────────────────────────────────────
  // 6. 接线源码断言
  // ────────────────────────────────────────────────────────────
  group('接线源码断言（四端）', () {
    String read(String path) => File(path).readAsStringSync();

    test('Dart 管线：manager 落 glsl-shaders；player_screen 接线 + 命令', () {
      final mgr = read('lib/services/player/anime4k/anime4k_manager.dart');
      expect(mgr, contains("setProperty('glsl-shaders'"));
      final s = read('lib/screens/player/player_screen.dart');
      expect(s, contains('_setMpvProperty'));
      expect(s, contains('_applyAnime4K'));
      expect(s, contains('case ToggleAnime4K():'));
    });

    test('状态回显：_applyAnime4K 状态变化后必推送（防面板冻结在旧值）', () {
      // 694 真机回归：开关开了、着色器设进 mpv 了，但面板状态串冻结在「关」。
      // 根因是 _applyAnime4K 更新 _anime4kStatus 后没触发 _syncNativePanelData。
      final s = read('lib/screens/player/player_screen.dart');
      final applyBody = s.substring(
        s.indexOf('Future<void> _applyAnime4K'),
        s.indexOf('DanmakuSearchController? _danmakuPanelController'),
      );
      // 状态赋值后必须紧跟推送调用。
      expect(applyBody, contains('_anime4kStatus = status'));
      expect(applyBody, contains('_syncNativePanelData()'));
    });

    test('回读校验接线：三端 live 读 + main.cpp round-trip', () {
      // pipeline 有回读/错误注入参数
      final mgr = read('lib/services/player/anime4k/anime4k_manager.dart');
      expect(mgr, contains('readProperty'));
      expect(mgr, contains('recentErrors'));
      expect(mgr, contains('已挂载渲染中'));
      expect(mgr, contains('写入未生效'));
      expect(mgr, contains('编译失败'));
      // MpvPlayerAdapter live 读（安卓/鸿蒙）
      final mpv = read('lib/services/player/mpv_player_adapter.dart');
      expect(mpv, contains('Future<String?> readProperty'));
      expect(mpv, contains('recentMpvErrors'));
      // QtPlayerAdapter round-trip（Windows）
      final qt = read('lib/services/player/qt_player_adapter.dart');
      expect(qt, contains("'getProperty'"));
      expect(qt, contains("'propertyValue'"));
      // main.cpp getProperty handler 回发 propertyValue
      final cpp = read('native/windows_qt_player/src/main.cpp');
      expect(cpp, contains('getProperty'));
      expect(cpp, contains('readMpvString'));
      expect(cpp, contains('propertyValue'));
      // player_screen 类型分发注入
      final scr = read('lib/screens/player/player_screen.dart');
      expect(scr, contains('_readMpvProperty'));
      expect(scr, contains('_recentMpvErrors'));
    });

    test('降档接线：_applyAnime4K 用生效档 + 设置不动', () {
      final mgr = read('lib/services/player/anime4k/anime4k_manager.dart');
      expect(mgr, contains('class Anime4KResolve'));
      expect(mgr, contains('resolveEffectiveMode'));
      expect(mgr, contains('videoHeight % 8 != 0'));
      final scr = read('lib/screens/player/player_screen.dart');
      expect(scr, contains('Anime4KResolve.resolveEffectiveMode'));
      // 用生效档应用 + 降档标注
      expect(scr, contains('mode: effectiveMode'));
      expect(scr, contains('ArtCNN 临时降档'));
    });

    test('命令路由：toggleAnime4K → ToggleAnime4K', () {
      final s = read('lib/services/player/native/native_player_command.dart');
      expect(s, contains("'toggleAnime4K'"));
      expect(s, contains('return const ToggleAnime4K();'));
    });

    test('Qt 状态属性：playerState 暴露 anime4kStatus/Enabled', () {
      final h = read('native/windows_qt_player/src/player_state.h');
      expect(h, contains('Q_PROPERTY(QString anime4kStatus'));
      expect(h, contains('Q_PROPERTY(bool anime4kEnabled'));
      final cpp = read('native/windows_qt_player/src/player_state.cpp');
      expect(cpp, contains('readString(json, "anime4kStatus"'));
      expect(cpp, contains('readBool(json, "anime4kEnabled"'));
    });

    test('Windows QML 调试面板：状态行 + 点击 toggleAnime4K', () {
      final s = read('native/windows_qt_player/src/qml/DebugPanel.qml');
      expect(s, contains('playerState.anime4kStatus'));
      expect(s, contains('"toggleAnime4K"'));
    });

    test('鸿蒙 ArkTS 调试面板：状态行 + 点击经宿主乐观切换', () {
      final s = read(
          'plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/DebugPanel.ets');
      expect(s, contains('anime4kStatus'));
      expect(s, contains('optimisticToggleAnime4K'));
      final host = read(
          'plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/HimiMpvNativeHost.ets');
      expect(host, contains('anime4kStatus: string'));
      expect(host, contains('anime4kEnabled: boolean'));
      expect(host, contains("'toggleAnime4K'")); // 命令串在宿主转发
    });

    test('Android Kotlin 调试面板：状态行 + 回调 toggleAnime4K', () {
      final s = read(
          'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/DebugPanelView.kt');
      expect(s, contains('anime4kStatus'));
      expect(s, contains('onToggleAnime4K'));
      final host = read(
          'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/AndroidNativePlayerHost.kt');
      expect(host, contains('"toggleAnime4K"'));
      final state = read(
          'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/AndroidNativePlayerState.kt');
      expect(state, contains('val anime4kStatus: String'));
      expect(state, contains('val anime4kEnabled: Boolean'));
    });

    test('vendor 着色器带 MIT 许可证与 NOTICE', () {
      expect(File('third_party/anime4k/LICENSE-anime4k').existsSync(), isTrue);
      expect(File('third_party/anime4k/LICENSE-artcnn').existsSync(), isTrue);
      expect(File('third_party/anime4k/NOTICE.md').existsSync(), isTrue);
    });
  });
}

/// 从真实 `third_party/anime4k/glsl/` 目录读文件的假 AssetBundle——
/// 既验证解包流程，又顺带校验 vendor 资产真实存在且非空。
class _DiskAssetBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    final name = key.split('/').last;
    final f = File('third_party/anime4k/glsl/$name');
    if (!f.existsSync()) {
      throw StateError('测试资产缺失: $key');
    }
    final bytes = f.readAsBytesSync();
    return ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.length);
  }
}

_DiskAssetBundle _diskBundle() => _DiskAssetBundle();
