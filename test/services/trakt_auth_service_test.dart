import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/trakt_models.dart';
import 'package:himi_syncwatch/services/trakt/trakt_auth_service.dart';
import 'package:himi_syncwatch/services/trakt/trakt_config.dart';
import 'package:himi_syncwatch/services/trakt/trakt_token_store.dart';

class _FakeStorage implements FlutterSecureStorage {
  final Map<String, String> data = {};

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      data[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      data.remove(key);
    } else {
      data[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    data.remove(key);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

typedef _Handler = Future<ResponseBody> Function(RequestOptions options);

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);

  final _Handler handler;
  int calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    calls++;
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object payload, [int status = 200]) =>
    ResponseBody.fromString(
      jsonEncode(payload),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );

TraktConfig _config() => const TraktConfig(
      clientId: 'client-123',
      redirectUri: 'https://example.test/callback',
      apiBase: 'https://api.test',
      authorizeUrl: 'https://auth.test/authorize',
      tokenUrls: ['https://auth.test/token'],
      deviceCodeUrl: 'https://auth.test/device/code',
      deviceTokenUrl: 'https://auth.test/device/token',
      revokeUrls: ['https://auth.test/revoke'],
    );

void main() {
  group('PKCE', () {
    test('生成 verifier/challenge/state 并保存会话', () async {
      final storage = _FakeStorage();
      final store = TraktTokenStore(storage: storage);
      final auth = TraktAuthService(
        config: _config(),
        store: store,
        dio: Dio()..httpClientAdapter = _FakeAdapter((_) async => _json({})),
      );

      final uri = await auth.beginPkce();
      final session = await store.readPkce();

      expect(uri.host, 'auth.test');
      expect(uri.queryParameters['client_id'], 'client-123');
      expect(uri.queryParameters['code_challenge_method'], 'S256');
      expect(
          uri.queryParameters['redirect_uri'], 'https://example.test/callback');
      expect(session, isNotNull);
      expect(uri.queryParameters['state'], session!.state);
      expect(
        uri.queryParameters['code_challenge'],
        base64UrlEncode(sha256.convert(utf8.encode(session.verifier)).bytes)
            .replaceAll('=', ''),
      );
      expect(session.verifier.length, greaterThanOrEqualTo(43));
    });

    test('回调校验 state 并用 code_verifier 兑换 token', () async {
      final storage = _FakeStorage();
      final store = TraktTokenStore(storage: storage);
      late RequestOptions tokenRequest;
      final dio = Dio()
        ..httpClientAdapter = _FakeAdapter((options) async {
          tokenRequest = options;
          return _json({
            'access_token': 'access-1',
            'refresh_token': 'refresh-1',
            'token_type': 'Bearer',
            'expires_in': 7776000,
            'created_at': 1700000000,
          });
        });
      final auth = TraktAuthService(
        config: _config(),
        store: store,
        dio: dio,
        now: () => DateTime.utc(2026, 1, 1),
      );
      final uri = await auth.beginPkce();
      final state = uri.queryParameters['state'];

      final tokens = await auth.handleCallback(
        Uri.parse('himi://oauth/trakt/?code=abc&state=$state'),
      );

      expect(tokens.accessToken, 'access-1');
      expect(tokens.refreshToken, 'refresh-1');
      expect(tokenRequest.uri.toString(), 'https://auth.test/token');
      final body = Map<String, dynamic>.from(tokenRequest.data as Map);
      expect(body['grant_type'], 'authorization_code');
      expect(body['code'], 'abc');
      expect(body['code_verifier'], isNotEmpty);
      expect(body.containsKey('client_secret'), isFalse);
      expect(await store.readPkce(), isNull);
      expect((await store.readTokens())?.accessToken, 'access-1');
    });

    test('state 不匹配时拒绝且不兑换 token', () async {
      final storage = _FakeStorage();
      final store = TraktTokenStore(storage: storage);
      final adapter = _FakeAdapter((_) async => _json({}));
      final auth = TraktAuthService(
        config: _config(),
        store: store,
        dio: Dio()..httpClientAdapter = adapter,
      );
      await auth.beginPkce();

      await expectLater(
        () => auth.handleCallback(
          Uri.parse('himi://oauth/trakt/?code=abc&state=wrong'),
        ),
        throwsA(isA<TraktAuthException>()
            .having((e) => e.code, 'code', 'state_mismatch')),
      );
      expect(adapter.calls, 0);
      expect(await store.readPkce(), isNull);
    });

    test('会话超过 10 分钟拒绝', () async {
      final storage = _FakeStorage();
      final store = TraktTokenStore(storage: storage);
      await store.writePkce(TraktPkceSession(
        verifier: 'v',
        state: 's',
        createdAt: DateTime.utc(2026, 1, 1, 0, 0),
      ));
      final auth = TraktAuthService(
        config: _config(),
        store: store,
        now: () => DateTime.utc(2026, 1, 1, 0, 11),
        dio: Dio()..httpClientAdapter = _FakeAdapter((_) async => _json({})),
      );

      await expectLater(
        () => auth.handleCallback(
          Uri.parse('himi://oauth/trakt/?code=abc&state=s'),
        ),
        throwsA(isA<TraktAuthException>()
            .having((e) => e.code, 'code', 'expired_session')),
      );
    });
  });

  group('refresh', () {
    test('并发刷新只发一次请求', () async {
      final storage = _FakeStorage();
      final store = TraktTokenStore(storage: storage);
      final completer = Completer<ResponseBody>();
      final adapter = _FakeAdapter((_) => completer.future);
      final auth = TraktAuthService(
        config: _config(),
        store: store,
        dio: Dio()..httpClientAdapter = adapter,
        now: () => DateTime.utc(2026, 1, 1),
      );
      final old = TraktTokens(
        accessToken: 'old',
        refreshToken: 'refresh-old',
        tokenType: 'Bearer',
        expiresAt:
            DateTime.utc(2026, 1, 1).subtract(const Duration(minutes: 1)),
        createdAt: DateTime.utc(2025, 1, 1),
      );

      final first = auth.refresh(old);
      final second = auth.refresh(old);
      completer.complete(_json({
        'access_token': 'new',
        'refresh_token': 'refresh-new',
        'expires_in': 3600,
      }));
      final [a, b] = await Future.wait([first, second]);

      expect(adapter.calls, 1);
      expect(a.accessToken, 'new');
      expect(b.accessToken, 'new');
      expect((await store.readTokens())?.refreshToken, 'refresh-new');
    });
  });

  group('Device Flow', () {
    test('设备码和轮询状态映射', () async {
      final storage = _FakeStorage();
      final store = TraktTokenStore(storage: storage);
      var pollStatus = 400;
      final adapter = _FakeAdapter((options) async {
        if (options.path.endsWith('/device/code')) {
          return _json({
            'device_code': 'dev-1',
            'user_code': 'ABCD1234',
            'verification_url': 'https://trakt.tv/activate',
            'expires_in': 600,
            'interval': 5,
          });
        }
        if (pollStatus == 200) {
          return _json({
            'access_token': 'device-access',
            'refresh_token': 'device-refresh',
            'expires_in': 3600,
          });
        }
        return _json({'error': 'pending'}, pollStatus);
      });
      final auth = TraktAuthService(
        config: _config(),
        store: store,
        dio: Dio()..httpClientAdapter = adapter,
        now: () => DateTime.utc(2026, 1, 1),
      );

      final code = await auth.startDeviceFlow();
      expect(code.userCode, 'ABCD1234');
      expect(code.interval, 5);
      expect((await store.readDeviceCode())?.deviceCode, 'dev-1');

      final pending = await auth.pollDeviceFlow(code);
      expect(pending.status, TraktDevicePollStatus.pending);

      pollStatus = 429;
      final slow = await auth.pollDeviceFlow(code);
      expect(slow.status, TraktDevicePollStatus.slowDown);

      pollStatus = 200;
      final success = await auth.pollDeviceFlow(code);
      expect(success.status, TraktDevicePollStatus.success);
      expect(success.tokens?.accessToken, 'device-access');
      expect(await store.readDeviceCode(), isNull);
    });
  });
}
