import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/widgets/server_card.dart';

EmbyServerConfig _server({String? userId = 'uid', String? accessToken = 'token'}) =>
    EmbyServerConfig(
      id: 'srv_a',
      serverUrl: 'https://a.example.com',
      serverName: '家庭NAS',
      serverId: 's1',
      username: 'user',
      accessToken: accessToken,
      userId: userId,
    );

void main() {
  group('serverAvatarUrl', () {
    test('有 userId + token → 指向 Emby 用户头像', () {
      final url = serverAvatarUrl(_server());
      expect(url, '${_server().mediaUrl}/Users/uid/Images/Primary');
    });

    test('version 非空 → 追加 _v 参数破缓存', () {
      expect(serverAvatarUrl(_server(), version: 3),
          '${_server().mediaUrl}/Users/uid/Images/Primary?_v=3');
    });

    test('无 token 或 userId → null（回退渐变）', () {
      expect(serverAvatarUrl(_server(accessToken: null)), isNull);
      expect(serverAvatarUrl(_server(userId: null)), isNull);
      expect(serverAvatarUrl(_server(userId: '')), isNull);
    });
  });

  testWidgets('有 imageUrl 时渲染网络头像并携带 token 头', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ServerAvatar(
        label: '家庭NAS',
        size: 40,
        imageUrl: 'https://a.example.com/Users/uid/Images/Primary?_v=1',
        imageHeaders: const {'X-Emby-Token': 'token'},
      ),
    ));

    final image = tester.widget<Image>(find.byType(Image));
    final provider = image.image as NetworkImage;
    expect(provider.url, contains('/Users/uid/Images/Primary?_v=1'));
    expect(provider.headers?['X-Emby-Token'], 'token');
  });

  testWidgets('无 imageUrl 时回退渐变字标', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: ServerAvatar(label: 'Himi', size: 40),
    ));

    expect(find.byType(Image), findsNothing);
    expect(find.text('H'), findsOneWidget);
  });
}
