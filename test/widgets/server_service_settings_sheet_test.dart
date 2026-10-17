import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/providers/server_avatar_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/widgets/server_service_settings_sheet.dart';

import '../helpers/test_fakes.dart';

EmbyServerConfig _server({bool strmDirectPlay = false}) => EmbyServerConfig(
      id: 'srv_a',
      serverUrl: 'https://a.example.com',
      serverName: '家庭NAS',
      serverId: 's1',
      username: 'user',
      accessToken: 'token',
      userId: 'uid',
      strmDirectPlay: strmDirectPlay,
    );

Future<
    ({
      ProviderContainer container,
      FakeEmbyService service,
      FakeEmbyAuthService auth,
    })> _pumpSheet(
  WidgetTester tester, {
  required EmbyServerConfig server,
  FakeEmbyService? service,
  FakeEmbyAuthService? auth,
}) async {
  final fakeService = service ?? FakeEmbyService();
  final fakeAuth = auth ?? FakeEmbyAuthService();
  final container = ProviderContainer(
    overrides: [
      settingsProvider.overrideWith((ref) => FakeSettingsNotifier()),
      embyServiceProvider.overrideWithValue(fakeService),
      embyAuthClientProvider.overrideWithValue(fakeService),
      embyAuthServiceProvider.overrideWith((ref) => fakeAuth),
      embyServerListProvider.overrideWith(
        (ref) => EmbyServerListNotifier()..setList([server]),
      ),
      embyConfigProvider.overrideWith(
        (ref) => EmbyConfigNotifier()..setConfig(server),
      ),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: ElevatedButton(
                onPressed: () => showServiceSettingsSheet(ctx, server),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return (container: container, service: fakeService, auth: fakeAuth);
}

void main() {
  testWidgets('面板渲染：服务器名 + 三个操作 + STRM 开关', (tester) async {
    await _pumpSheet(tester, server: _server());

    expect(find.text('家庭NAS'), findsOneWidget);
    expect(find.byKey(const ValueKey('serviceRelogin')), findsOneWidget);
    expect(find.byKey(const ValueKey('serviceChangePassword')), findsOneWidget);
    expect(find.byKey(const ValueKey('serviceUploadAvatar')), findsOneWidget);
    expect(find.byKey(const ValueKey('serviceStrmDirectPlay')), findsOneWidget);
    expect(find.text('重新登录'), findsOneWidget);
    expect(find.text('修改密码'), findsOneWidget);
    expect(find.text('上传头像'), findsOneWidget);
  });

  testWidgets('STRM 开关默认关闭，开启后落盘 + 列表更新', (tester) async {
    final server = _server();
    final result = await _pumpSheet(tester, server: server);

    final switchTile =
        tester.widget<SwitchListTile>(find.byKey(const ValueKey('serviceStrmDirectPlay')));
    expect(switchTile.value, false);

    await tester.tap(find.byKey(const ValueKey('serviceStrmDirectPlay')));
    await tester.pumpAndSettle();

    expect(result.auth.updateSessionRoutesCalls, 1);
    expect(result.auth.lastStrmDirectPlay, true);
    expect(
      result.container
          .read(embyServerListProvider)
          .single
          .strmDirectPlay,
      true,
      reason: '列表配置应同步更新',
    );
  });

  testWidgets('STRM 开关已开启时初值为 on，关闭后落盘 false', (tester) async {
    final server = _server(strmDirectPlay: true);
    final result = await _pumpSheet(tester, server: server);

    final switchTile =
        tester.widget<SwitchListTile>(find.byKey(const ValueKey('serviceStrmDirectPlay')));
    expect(switchTile.value, true);

    await tester.tap(find.byKey(const ValueKey('serviceStrmDirectPlay')));
    await tester.pumpAndSettle();
    expect(result.auth.lastStrmDirectPlay, false);
  });

  testWidgets('修改密码：校验两次新密码一致后调用 changePassword', (tester) async {
    final result = await _pumpSheet(tester, server: _server());

    await tester.tap(find.byKey(const ValueKey('serviceChangePassword')));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, '当前密码'), findsOneWidget);
    // 新密码与确认不一致 → 提示且不调用
    await tester.enterText(find.widgetWithText(TextField, '当前密码'), 'old');
    await tester.enterText(find.widgetWithText(TextField, '新密码'), 'a1');
    await tester.enterText(find.widgetWithText(TextField, '确认新密码'), 'a2');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(find.text('两次输入的新密码不一致'), findsOneWidget);
    expect(result.service.passwordCalls, isEmpty);

    // 一致 → 调用
    await tester.enterText(find.widgetWithText(TextField, '确认新密码'), 'a1');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(result.service.passwordCalls.single.current, 'old');
    expect(result.service.passwordCalls.single.next, 'a1');
  });

  testWidgets('重新登录：成功 → 更新列表配置 + 落盘保留 STRM', (tester) async {
    final server = _server(strmDirectPlay: true);
    final service = FakeEmbyService()
      ..authResult = const {
        'User': {'Id': 'uid2'},
        'AccessToken': 'token2',
        'ServerId': 's1',
      };
    final result = await _pumpSheet(tester, server: server, service: service);

    await tester.tap(find.byKey(const ValueKey('serviceRelogin')));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, '用户名'), 'user2');
    await tester.enterText(find.widgetWithText(TextField, '密码'), 'pw2');
    await tester.tap(find.text('登录'));
    await tester.pumpAndSettle();

    expect(service.lastAuthUsername, 'user2');
    final updated = result.container.read(embyServerListProvider).single;
    expect(updated.username, 'user2');
    expect(updated.accessToken, 'token2');
    expect(updated.userId, 'uid2');
    expect(updated.strmDirectPlay, true, reason: '重新登录不应丢失 STRM 开关');
    expect(result.auth.lastSavedStrmDirectPlay, true);
  });

  testWidgets('面板头像加载 Emby 用户头像，版本号变化后刷新 URL（v1.2.9）',
      (tester) async {
    final result = await _pumpSheet(tester, server: _server());

    NetworkImage avatar() =>
        tester.widget<Image>(find.byType(Image)).image as NetworkImage;
    expect(avatar().url, contains('/Users/uid/Images/Primary'));
    expect(avatar().headers?['X-Emby-Token'], 'token');

    result.container.read(serverAvatarVersionProvider.notifier).bump('srv_a');
    await tester.pumpAndSettle();

    expect(avatar().url, contains('/Users/uid/Images/Primary?_v=1'));
  });

  testWidgets('重新登录失败展示简短中文提示（不透出英文异常）（v1.2.9）',
      (tester) async {
    final service = FakeEmbyService()
      ..authError = DioException(
        requestOptions: RequestOptions(path: '/Users/AuthenticateByName'),
        type: DioExceptionType.badResponse,
        response: Response(
          requestOptions: RequestOptions(path: '/Users/AuthenticateByName'),
          statusCode: 401,
        ),
      );
    await _pumpSheet(tester, server: _server(), service: service);

    await tester.tap(find.byKey(const ValueKey('serviceRelogin')));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '用户名'), 'user');
    await tester.enterText(find.widgetWithText(TextField, '密码'), 'bad');
    await tester.tap(find.text('登录'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('重新登录失败：用户名或密码错误'), findsOneWidget);
    expect(find.textContaining('DioException'), findsNothing);
  });
}
