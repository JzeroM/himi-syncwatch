import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/providers/lan_config_provider.dart';
import 'package:himi_syncwatch/screens/settings/qr_config_screen.dart';
import 'package:qr_flutter/qr_flutter.dart';

void main() {
  /// 真实 IO（端口绑定/网络接口枚举）需在 runAsync 窗口执行。
  Future<ProviderContainer> pumpScreen(
    WidgetTester tester, {
    String mode = '',
  }) async {
    late ProviderContainer container;
    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            lanConfigBasePortProvider.overrideWithValue(0),
          ],
          child: MaterialApp(home: _Entry(mode: mode)),
        ),
      );
      await tester.pump(); // Entry postFrame → push
      await tester.pump(); // 转场开始
      await Future<void>.delayed(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      container = ProviderScope.containerOf(
        tester.element(find.byType(QrConfigScreen)),
      );
    });
    return container;
  }

  testWidgets('进入页面自动启动服务并显示二维码与地址', (tester) async {
    final container = await pumpScreen(tester);

    expect(find.byType(QrImageView), findsOneWidget);

    final state = container.read(lanConfigProvider);
    expect(state.running, isTrue);
    expect(state.url, startsWith('http://'));
    expect(state.url, contains('t='));
    expect(find.textContaining('http://${state.ips.first}'), findsWidgets);
    expect(find.textContaining('同一 WiFi'), findsOneWidget);
  });

  testWidgets('mode=emby 时二维码 URL 携带 mode 参数', (tester) async {
    await pumpScreen(tester, mode: 'emby');

    // 页面展示的地址（即二维码内容）带 mode 锚点
    expect(find.textContaining('mode=emby'), findsOneWidget);
  });

  testWidgets('手机提交失败后页面展示错误结果卡片', (tester) async {
    final container = await pumpScreen(tester);
    final state = container.read(lanConfigProvider);
    final token = Uri.parse(state.url!).queryParameters['t'];
    // flutter_test 的 HttpOverrides 全局 mock 会劫持真实请求，此处显式绕过
    await tester.runAsync(() {
      return HttpOverrides.runWithHttpOverrides(() async {
        final client = HttpClient()..findProxy = ((_) => 'DIRECT');
        final postUri = Uri.parse(
          'http://127.0.0.1:${state.port}/api/agora?t=$token',
        );
        final req = await client.openUrl('POST', postUri);
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode({'appId': '', 'appCertificate': ''}));
        final res = await req.close();
        final bodyText = await utf8.decoder.bind(res).join();
        expect(res.statusCode, HttpStatus.badRequest, reason: bodyText);
        client.close();
      }, _DirectHttpOverrides());
    });

    await tester.pump();
    expect(find.text('App ID 与 Certificate 不能为空'), findsOneWidget);
  });

  testWidgets('返回页面时自动停止服务', (tester) async {
    final container = await pumpScreen(tester);
    expect(container.read(lanConfigProvider).running, isTrue);

    await tester.pageBack();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // stop() 的服务关闭是真实 IO，需在 runAsync 窗口等待完成
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();

    expect(container.read(lanConfigProvider).running, isFalse);
    expect(container.read(lanConfigProvider).url, isNull);
  });
}

class _Entry extends StatefulWidget {
  const _Entry({required this.mode});

  final String mode;

  @override
  State<_Entry> createState() => _EntryState();
}

class _EntryState extends State<_Entry> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => QrConfigScreen(mode: widget.mode),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox());
}

/// flutter_test 全局 mock（HttpOverrides.global）下仍创建真实 HttpClient。
class _DirectHttpOverrides extends HttpOverrides {}
