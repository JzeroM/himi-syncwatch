import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/providers/agora_provider.dart';
import 'package:himi_syncwatch/providers/cache_provider.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/settings/cache_settings_screen.dart';
import 'package:himi_syncwatch/services/backup/backup_file_io.dart';
import 'package:himi_syncwatch/services/backup/backup_service.dart';
import 'package:himi_syncwatch/services/trakt/trakt_token_store.dart';

import '../helpers/cache_fakes.dart';
import '../helpers/fake_secure_storage.dart';
import '../helpers/test_fakes.dart';

/// 697：「数据」页的备份与还原分组。
///
/// 只验证 UI 编排（点击 → 调用服务 → 二次确认 → 提示），
/// 备份内容/校验规则由 `services/backup_service_test.dart` 覆盖。
void main() {
  /// 组装被测页面所需的一切（内存假实现，不触平台通道）。
  ({
    Widget widget,
    _FakeFileIo fileIo,
    FakeEmbyAuthService auth,
    FakeSecureStorage storage,
  }) build({
    AppSettings settings = const AppSettings(),
    _FakeFileIo? fileIo,
    List<String> serverIds = const [],
  }) {
    final storage = FakeSecureStorage();
    final auth = FakeEmbyAuthService(serverIds: serverIds);
    final settingsNotifier = _SeededSettingsNotifier(storage: storage)
      ..state = settings;
    final agoraNotifier = AgoraConfigNotifier(storage: storage);
    final traktStore = TraktTokenStore(storage: storage);
    final io = fileIo ?? _FakeFileIo();

    final service = BackupService(
      authService: auth,
      settings: settingsNotifier,
      agora: agoraNotifier,
      traktTokens: traktStore,
      // 测试环境不触 PackageInfo 平台通道（否则 pumpAndSettle 会挂住）。
      appVersionLoader: () async => '1.6.8+688',
    );

    final container = ProviderContainer(overrides: [
      appCacheServiceProvider.overrideWithValue(FakeAppCacheService(
        cacheSnapshot(images: 100),
      )),
      settingsProvider.overrideWith((ref) => settingsNotifier),
      agoraConfigProvider.overrideWith((ref) => agoraNotifier),
      embyAuthServiceProvider.overrideWithValue(auth),
    ]);
    addTearDown(container.dispose);

    return (
      widget: UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: CacheSettingsScreen(backupService: service, fileIo: io),
        ),
      ),
      fileIo: io,
      auth: auth,
      storage: storage,
    );
  }

  Future<void> pump(WidgetTester tester, Widget widget) async {
    tester.view.physicalSize = const Size(1080, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(widget);
    await tester.pumpAndSettle();
  }

  /// 一份合法备份（1 个服务器 + TMDB）。
  String validBackup({String tmdbKey = 'restored_key'}) => jsonEncode({
        'app': 'himi_syncwatch',
        'version': 1,
        'createdAt': '2026-11-13T04:00:00.000Z',
        'appVersion': '1.6.7+687',
        'data': {
          'embyServers': [
            {
              'id': 'cfg_new',
              'serverId': 'srv_new',
              'serverUrl': 'http://192.168.1.9:8096',
              'serverName': '备份服务器',
              'username': 'mojito',
              'accessToken': 'tok_new',
              'userId': 'uid_new',
            },
          ],
          'selectedServerId': 'cfg_new',
          'tmdb': {'apiKey': tmdbKey},
        },
      });

  group('备份与还原分组', () {
    testWidgets('数据页显示备份与还原两行', (tester) async {
      await pump(tester, build().widget);

      expect(find.text('备份与还原'), findsOneWidget);
      expect(find.byKey(const ValueKey('backupExport')), findsOneWidget);
      expect(find.byKey(const ValueKey('backupRestore')), findsOneWidget);
      expect(find.text('备份配置'), findsOneWidget);
      expect(find.text('还原配置'), findsOneWidget);
    });

    testWidgets('备份写入 JSON 内容并提示路径', (tester) async {
      final env = build(
        settings: const AppSettings(tmdbApiKey: 'my_key'),
      );
      await pump(tester, env.widget);

      await tester.tap(find.byKey(const ValueKey('backupExport')));
      await tester.pumpAndSettle();

      expect(env.fileIo.savedContent, isNotNull);
      final decoded = jsonDecode(env.fileIo.savedContent!) as Map;
      expect(decoded['app'], 'himi_syncwatch');
      expect((decoded['data'] as Map)['tmdb']['apiKey'], 'my_key');
      expect(env.fileIo.savedFileName, startsWith('himi-backup-'));
      expect(find.textContaining('已备份到'), findsOneWidget);
    });

    testWidgets('备份取消（saveFile 返回 null）不提示成功', (tester) async {
      final env = build(fileIo: _FakeFileIo(savePath: null));
      await pump(tester, env.widget);

      await tester.tap(find.byKey(const ValueKey('backupExport')));
      await tester.pumpAndSettle();

      expect(find.textContaining('已备份到'), findsNothing);
    });

    testWidgets('备份失败提示错误', (tester) async {
      final env = build(fileIo: _FakeFileIo()..saveError = StateError('磁盘满'));
      await pump(tester, env.widget);

      await tester.tap(find.byKey(const ValueKey('backupExport')));
      await tester.pumpAndSettle();

      expect(find.textContaining('备份失败'), findsOneWidget);
    });

    testWidgets('还原：无效备份直接提示，不弹确认', (tester) async {
      final env = build(fileIo: _FakeFileIo(pickText: '{"app":"other"}'));
      await pump(tester, env.widget);

      await tester.tap(find.byKey(const ValueKey('backupRestore')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('tvConfirmOk')), findsNothing);
      expect(find.textContaining('HIMI'), findsOneWidget);
      expect(env.auth.deleteAllSessionsCalls, 0);
    });

    testWidgets('还原：取消二次确认不写入任何数据', (tester) async {
      final env = build(fileIo: _FakeFileIo(pickText: validBackup()));
      await pump(tester, env.widget);

      await tester.tap(find.byKey(const ValueKey('backupRestore')));
      await tester.pumpAndSettle();
      expect(find.text('还原配置？'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('tvConfirmCancel')));
      await tester.pumpAndSettle();

      expect(env.auth.deleteAllSessionsCalls, 0);
      expect(env.auth.savedSessions, isEmpty);
    });

    testWidgets('还原：确认后完全替换服务器并提示已还原项', (tester) async {
      final env = build(
        serverIds: ['srv_old'],
        fileIo: _FakeFileIo(pickText: validBackup()),
      );
      await pump(tester, env.widget);

      await tester.tap(find.byKey(const ValueKey('backupRestore')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tvConfirmOk')));
      await tester.pumpAndSettle();

      expect(env.auth.deleteAllSessionsCalls, 1);
      expect(env.auth.savedSessions, hasLength(1));
      expect(env.auth.savedSessions.first['serverId'], 'srv_new');
      expect(find.textContaining('已还原'), findsOneWidget);
      expect(find.textContaining('Emby 服务器'), findsOneWidget);
    });

    testWidgets('还原：确认框展示备份时间与服务器数', (tester) async {
      final env = build(fileIo: _FakeFileIo(pickText: validBackup()));
      await pump(tester, env.widget);

      await tester.tap(find.byKey(const ValueKey('backupRestore')));
      await tester.pumpAndSettle();

      expect(find.textContaining('将用备份内容完全替换现有配置'), findsOneWidget);
      expect(find.textContaining('Emby 服务器（1 个）'), findsOneWidget);
      expect(find.textContaining('备份时间：'), findsOneWidget);
      expect(find.textContaining('himi-backup.json'), findsOneWidget);
    });

    testWidgets('还原：用户取消选择文件时无任何动作', (tester) async {
      final env = build();
      await pump(tester, env.widget);

      await tester.tap(find.byKey(const ValueKey('backupRestore')));
      await tester.pumpAndSettle();

      expect(env.fileIo.pickCalls, 1);
      expect(env.auth.deleteAllSessionsCalls, 0);
      expect(find.byKey(const ValueKey('tvConfirmOk')), findsNothing);
    });

    testWidgets('还原：读取文件异常时提示失败', (tester) async {
      final env = build(fileIo: _FakeFileIo()..pickError = StateError('无权访问'));
      await pump(tester, env.widget);

      await tester.tap(find.byKey(const ValueKey('backupRestore')));
      await tester.pumpAndSettle();

      expect(find.textContaining('读取备份文件失败'), findsOneWidget);
    });
  });
}

/// `SettingsNotifier` 的 `state` 是 protected，子类内可写。
class _SeededSettingsNotifier extends SettingsNotifier {
  _SeededSettingsNotifier({required super.storage});
}

/// 记录 save/pick 调用并返回预置结果的假文件层。
class _FakeFileIo implements BackupFileIo {
  _FakeFileIo({this.pickText, this.savePath = '/tmp/b.json'});

  String? pickText;
  String? savePath;
  Object? pickError;
  Object? saveError;

  String? savedFileName;
  String? savedContent;
  int pickCalls = 0;

  @override
  Future<String?> save({
    required String fileName,
    required String content,
  }) async {
    if (saveError != null) throw saveError!;
    savedFileName = fileName;
    savedContent = content;
    return savePath;
  }

  @override
  Future<PickedBackupFile?> pick() async {
    pickCalls++;
    if (pickError != null) throw pickError!;
    final text = pickText;
    if (text == null) return null;
    return PickedBackupFile(name: 'himi-backup.json', text: text);
  }
}

