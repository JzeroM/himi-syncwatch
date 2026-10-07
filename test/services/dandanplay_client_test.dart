import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/danmaku/dandanplay_client.dart';
import 'package:himi_syncwatch/services/danmaku/danmaku_comment.dart';

typedef _Handler = Future<ResponseBody> Function(RequestOptions options);

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);
  final _Handler handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) =>
      handler(options);

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object payload, {int status = 200}) =>
    ResponseBody.fromString(
      jsonEncode(payload),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );

DandanplayClient _client(_Handler handler,
    {String baseUrl = 'http://10.0.0.2:9321'}) {
  final dio = Dio()..httpClientAdapter = _FakeAdapter(handler);
  return DandanplayClient(baseUrl: baseUrl, dio: dio);
}

void main() {
  setUp(() {
    // 重试退避即时返回，避免测试真实等待
    DandanplayClient.retryDelay = (_) async {};
  });
  tearDown(() {
    DandanplayClient.retryDelay =
        (d) => Future<void>.delayed(d);
  });

  group('DandanplayClient.normalizeBaseUrl', () {
    test('去尾部斜杠 / 无 scheme 补 http:// / trim', () {
      expect(
        DandanplayClient.normalizeBaseUrl(' http://192.168.1.7:9321/ '),
        'http://192.168.1.7:9321',
      );
      expect(
        DandanplayClient.normalizeBaseUrl('192.168.1.7:9321'),
        'http://192.168.1.7:9321',
      );
      expect(
        DandanplayClient.normalizeBaseUrl('https://danmaku.example.com'),
        'https://danmaku.example.com',
      );
    });

    test('含 token 路径保留', () {
      expect(
        DandanplayClient.normalizeBaseUrl('http://10.0.0.2:9321/87654321/'),
        'http://10.0.0.2:9321/87654321',
      );
    });

    test('丢弃 query/fragment；空与非法返回 null', () {
      expect(
        DandanplayClient.normalizeBaseUrl('http://a.b/c?x=1#f'),
        'http://a.b/c',
      );
      expect(DandanplayClient.normalizeBaseUrl(''), isNull);
      expect(DandanplayClient.normalizeBaseUrl('   '), isNull);
      expect(DandanplayClient.normalizeBaseUrl('ftp://a.b'), isNull);
      expect(DandanplayClient.normalizeBaseUrl('not a url'), isNull);
    });
  });

  group('DandanplayClient.match', () {
    test('URL 追加 /api/v2/match（token 路径不被覆盖）+ 请求体形状', () async {
      late RequestOptions seen;
      final client = _client((options) async {
        seen = options;
        return _json({
          'isMatched': false,
          'matches': [
            {
              'episodeId': 100001,
              'animeTitle': '测试动画',
              'episodeTitle': '第1话',
            },
            {'episodeId': 100002},
          ],
        });
      }, baseUrl: 'http://10.0.0.2:9321/TOKEN');

      final list = await client.match(fileName: '测试动画 S01E01', fileSize: 123);

      expect(
        seen.uri.toString(),
        'http://10.0.0.2:9321/TOKEN/api/v2/match',
        reason: 'token 路径必须保留',
      );
      expect(seen.method, 'POST');
      final body = seen.data as Map<String, dynamic>;
      expect(body['fileName'], '测试动画 S01E01');
      expect(body['matchMode'], 'fileNameOnly');
      expect(body['fileSize'], 123);
      expect(list.map((c) => c.episodeId), [100001, 100002]);
      expect(list.first.animeTitle, '测试动画');
    });

    test('fileSize 省略时不进请求体', () async {
      late RequestOptions seen;
      final client = _client((options) async {
        seen = options;
        return _json({
          'isMatched': true,
          'matches': [
            {'episodeId': 7}
          ]
        });
      });
      await client.match(fileName: '电影');
      final body = seen.data as Map<String, dynamic>;
      expect(body.containsKey('fileSize'), isFalse);
    });

    test('未配置地址 → notConfigured，且不发请求', () async {
      var called = false;
      final client = _client((_) async {
        called = true;
        return _json({});
      }, baseUrl: '');
      expect(client.isConfigured, isFalse);
      await expectLater(
        client.match(fileName: 'x'),
        throwsA(isA<DanmakuApiException>().having(
          (e) => e.kind,
          'kind',
          DanmakuApiError.notConfigured,
        )),
      );
      expect(called, isFalse);
    });

    test('success:false → business 异常携带 errorMessage', () async {
      final client = _client(
        (_) async => _json({'success': false, 'errorMessage': '识别服务不可用'}),
      );
      await expectLater(
        client.match(fileName: 'x'),
        throwsA(isA<DanmakuApiException>()
            .having((e) => e.kind, 'kind', DanmakuApiError.business)
            .having((e) => e.message, 'message', '识别服务不可用')),
      );
    });

    test('缺 matches 字段 → business', () async {
      final client = _client((_) async => _json({'isMatched': false}));
      await expectLater(
        client.match(fileName: 'x'),
        throwsA(isA<DanmakuApiException>().having(
          (e) => e.kind,
          'kind',
          DanmakuApiError.business,
        )),
      );
    });

    test('HTTP 500 → http 异常', () async {
      final client =
          _client((_) async => _json({'error': 'boom'}, status: 500));
      await expectLater(
        client.match(fileName: 'x'),
        throwsA(isA<DanmakuApiException>().having(
          (e) => e.kind,
          'kind',
          DanmakuApiError.http,
        )),
      );
    });

    test('网络异常 → network 异常', () async {
      final client = _client((_) async => throw Exception('conn refused'));
      await expectLater(
        client.match(fileName: 'x'),
        throwsA(isA<DanmakuApiException>().having(
          (e) => e.kind,
          'kind',
          DanmakuApiError.network,
        )),
      );
    });

    test('HTTP 530 首两次失败、第三次成功 → 重试命中', () async {
      var calls = 0;
      final client = _client((_) async {
        calls++;
        if (calls < 3) return _json({'error': 'cf'}, status: 530);
        return _json({
          'matches': [
            {'episodeId': 5, 'animeTitle': 'x'},
          ],
        });
      });
      final list = await client.match(fileName: 'x');
      expect(list.single.episodeId, 5);
      expect(calls, 3, reason: '首次 530 后重试 2 次');
    });

    test('持续 530 → 重试耗尽抛 http(530)', () async {
      var calls = 0;
      final client = _client((_) async {
        calls++;
        return _json({'error': 'cf'}, status: 530);
      });
      await expectLater(
        client.match(fileName: 'x'),
        throwsA(isA<DanmakuApiException>()
            .having((e) => e.kind, 'kind', DanmakuApiError.http)
            .having((e) => e.statusCode, 'statusCode', 530)),
      );
      expect(calls, DandanplayClient.maxRetries + 1);
    });

    test('HTTP 4xx 非瞬时 → 不重试', () async {
      var calls = 0;
      final client = _client((_) async {
        calls++;
        return _json({'error': 'bad'}, status: 404);
      });
      await expectLater(
        client.match(fileName: 'x'),
        throwsA(isA<DanmakuApiException>()),
      );
      expect(calls, 1, reason: '4xx 不重试');
    });

    test('网络异常首失败、再成功 → 重试命中', () async {
      var calls = 0;
      final client = _client((_) async {
        calls++;
        if (calls < 2) throw Exception('conn refused');
        return _json({
          'matches': [
            {'episodeId': 8},
          ],
        });
      });
      final list = await client.match(fileName: 'x');
      expect(list.single.episodeId, 8);
      expect(calls, 2);
    });

    test('坏 matches 项（缺 episodeId）跳过', () async {
      final client = _client((_) async => _json({
            'matches': [
              {'episodeId': 'not-number'},
              {'episodeId': 42},
            ],
          }));
      final list = await client.match(fileName: 'x');
      expect(list.single.episodeId, 42);
    });
  });

  group('DandanplayClient.searchEpisodes', () {
    test('GET search/episodes 带 anime 参数，扁平化 animes[].episodes[]', () async {
      late RequestOptions seen;
      final client = _client((options) async {
        seen = options;
        return _json({
          'success': true,
          'animes': [
            {
              'animeTitle': '某剧',
              'episodes': [
                {'episodeId': 11, 'episodeTitle': '第1话 序'},
                {'episodeId': 12, 'episodeTitle': '第2话 承'},
              ],
            },
            {
              'animeTitle': '另一剧',
              'episodes': [
                {'episodeId': 21, 'episodeTitle': '【x】 第1集'},
              ],
            },
          ],
        });
      }, baseUrl: 'https://danmu.example.com/TOKEN');

      final list = await client.searchEpisodes('某剧');

      expect(
        seen.uri.toString(),
        'https://danmu.example.com/TOKEN/api/v2/search/episodes'
        '?anime=%E6%9F%90%E5%89%A7',
        reason: 'token 路径保留 + anime 查询参数编码',
      );
      expect(seen.method, 'GET');
      expect(list.map((c) => c.episodeId), [11, 12, 21]);
      expect(list.first.animeTitle, '某剧');
      expect(list.first.episodeTitle, '第1话 序');
    });

    test('空关键词不发请求返回空', () async {
      var called = false;
      final client = _client((_) async {
        called = true;
        return _json({});
      });
      expect(await client.searchEpisodes('   '), isEmpty);
      expect(called, isFalse);
    });

    test('success:false → business', () async {
      final client = _client(
        (_) async => _json({'success': false, 'errorMessage': '源不可用'}),
      );
      await expectLater(
        client.searchEpisodes('x'),
        throwsA(isA<DanmakuApiException>()
            .having((e) => e.kind, 'kind', DanmakuApiError.business)
            .having((e) => e.message, 'message', '源不可用')),
      );
    });

    test('缺 animes 字段 → invalidResponse', () async {
      final client = _client((_) async => _json({'success': true}));
      await expectLater(
        client.searchEpisodes('x'),
        throwsA(isA<DanmakuApiException>().having(
          (e) => e.kind,
          'kind',
          DanmakuApiError.invalidResponse,
        )),
      );
    });

    test('坏剧集项（缺 episodeId）跳过', () async {
      final client = _client((_) async => _json({
            'animes': [
              {
                'animeTitle': 'a',
                'episodes': [
                  {'episodeTitle': '无 id'},
                  {'episodeId': 9, 'episodeTitle': '第1话'},
                ],
              },
            ],
          }));
      final list = await client.searchEpisodes('a');
      expect(list.single.episodeId, 9);
    });
  });

  group('DandanplayClient.fetchComments', () {    test('GET 带 withRelated+format 参数，返回解析后弹幕', () async {
      late RequestOptions seen;
      final client = _client((options) async {
        seen = options;
        return _json({
          'count': 2,
          'comments': [
            {'p': '1.5,1,25,16777215', 'm': '弹幕一'},
            {'p': '2.5,5,25,255', 'm': '弹幕二'},
          ],
        });
      });
      final list = await client.fetchComments(100001);
      expect(
        seen.uri.toString(),
        'http://10.0.0.2:9321/api/v2/comment/100001'
        '?withRelated=true&format=json',
      );
      expect(seen.method, 'GET');
      expect(list.length, 2);
      expect(list.first.mode, DanmakuMode.scroll);
      expect(list.last.mode, DanmakuMode.top);
    });

    test('success:false → business', () async {
      final client = _client(
        (_) async => _json({'success': false, 'errorMessage': '无权限'}),
      );
      await expectLater(
        client.fetchComments(1),
        throwsA(isA<DanmakuApiException>()
            .having((e) => e.kind, 'kind', DanmakuApiError.business)
            .having((e) => e.message, 'message', '无权限')),
      );
    });

    test('缺 comments 字段 → invalidResponse', () async {
      final client = _client((_) async => _json({'count': 0}));
      await expectLater(
        client.fetchComments(1),
        throwsA(isA<DanmakuApiException>().having(
          (e) => e.kind,
          'kind',
          DanmakuApiError.invalidResponse,
        )),
      );
    });

    test('未配置地址 → notConfigured', () async {
      final client = _client((_) async => _json({}), baseUrl: 'ftp://x.y');
      await expectLater(
        client.fetchComments(1),
        throwsA(isA<DanmakuApiException>().having(
          (e) => e.kind,
          'kind',
          DanmakuApiError.notConfigured,
        )),
      );
    });
  });
}
