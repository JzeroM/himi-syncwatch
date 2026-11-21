import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/bridge_parsers.dart';

void main() {
  group('extractJsonLdRating（JSON-LD 优先，698 ②）', () {
    test('单对象 aggregateRating', () {
      const html = '<script type="application/ld+json">'
          '{"@type":"Movie","aggregateRating":{"ratingValue":"9.4"}}'
          '</script>';
      expect(BridgeParsers.extractJsonLdRating(html), 9.4);
    });

    test('对象数组形态（多个 @graph 节点）', () {
      const html = '<script type="application/ld+json">'
          '[{"@type":"Movie"},{"@type":"Movie","aggregateRating":{"ratingValue":"4.2"}}]'
          '</script>';
      expect(BridgeParsers.extractJsonLdRating(html), 4.2);
    });

    test('多 script 块：脏块不影响好块', () {
      const html = '<script type="application/ld+json">{broken</script>'
          '<script type="application/ld+json">'
          '{"aggregateRating":{"ratingValue":"8.8"}}</script>';
      expect(BridgeParsers.extractJsonLdRating(html), 8.8);
    });

    test('无 JSON-LD / 无 aggregateRating → null', () {
      expect(BridgeParsers.extractJsonLdRating('<html></html>'), isNull);
      expect(
        BridgeParsers.extractJsonLdRating(
          '<script type="application/ld+json">{"@type":"Movie"}</script>',
        ),
        isNull,
      );
    });

    test('ratingValue 数字类型兼容', () {
      const html = '<script type="application/ld+json">'
          '{"aggregateRating":{"ratingValue":7.5}}</script>';
      expect(BridgeParsers.extractJsonLdRating(html), 7.5);
    });
  });

  group('extractMetaRating（降级）', () {
    test('豆瓣 v:average（单双引号兼容）', () {
      expect(
        BridgeParsers.extractMetaRating('<meta property="v:average" content="8.9">'),
        8.9,
      );
      expect(
        BridgeParsers.extractMetaRating("<meta property='v:average' content='8.1'>"),
        8.1,
      );
    });

    test('Letterboxd twitter:data2（"4.2 average" 取前缀数）', () {
      expect(
        BridgeParsers.extractMetaRating(
          '<meta name="twitter:data2" content="4.2 average">',
        ),
        4.2,
      );
    });

    test('extractRating 综合：JSON-LD 优先于 meta', () {
      const html = '<meta property="v:average" content="8.0">'
          '<script type="application/ld+json">'
          '{"aggregateRating":{"ratingValue":"9.1"}}</script>';
      expect(BridgeParsers.extractRating(html), 9.1);
    });
  });

  group('extractImdbId（豆瓣页 tt 反补，698 ②）', () {
    test('从 IMDb: tt 文本抽 id', () {
      const html = '<span>IMDb:</span> tt0133093';
      expect(BridgeParsers.extractImdbId(html), 'tt0133093');
    });

    test('无 IMDb 文本 → null', () {
      expect(BridgeParsers.extractImdbId('<html></html>'), isNull);
    });
  });

  group('extractDoubanSubjects（搜索候选三级，698 N7-E）', () {
    test('① 抽 subject id + 锚文本标题（去重）', () {
      const html = '<a href="https://movie.douban.com/subject/3541415/">盗梦空间</a>'
          '<a href="https://movie.douban.com/subject/3541415/?from=rec">重复</a>'
          '<a href="https://movie.douban.com/subject/1295644/">这个杀手不太冷</a>';
      final out = BridgeParsers.extractDoubanSubjects(html);
      expect(out.length, 2);
      expect(out.first['id'], '3541415');
      expect(out.first['title'], '盗梦空间');
    });

    test('② window.__DATA__ 内嵌 JSON（锚点缺席的 JS 渲染页）', () {
      const html = '<script>window.__DATA__ = {"items":['
          '{"id":"3541415","title":"盗梦空间 Inception","url":"https://movie.douban.com/subject/3541415/"},'
          '{"id":"1295644","title":"这个杀手不太冷"}'
          ']};</script><script>other()</script>';
      final out = BridgeParsers.extractDoubanSubjects(html);
      expect(out.length, 2);
      expect(out.first['id'], '3541415');
      expect(out.first['title'], '盗梦空间 Inception');
    });

    test('② 脏 JSON 不影响锚点路径', () {
      const html = '<a href="https://movie.douban.com/subject/111/">好片</a>'
          '<script>window.__DATA__ = {broken</script>';
      final out = BridgeParsers.extractDoubanSubjects(html);
      expect(out.single['id'], '111');
    });
  });

  group('normalizeTitle + titleSimilarity（film-bridge 移植）', () {
    test('归一：去标点/音标/大小写', () {
      expect(BridgeParsers.normalizeTitle('Léon: The Professional'), 'leontheprofessional');
      expect(BridgeParsers.normalizeTitle('盗梦空间'), '盗梦空间');
    });

    test('相似度：完全相同 1，包含关系长度比×0.92', () {
      expect(BridgeParsers.titleSimilarity('Inception', 'Inception'), 1);
      final partial = BridgeParsers.titleSimilarity('Inception', 'Inception 2010');
      expect(partial, greaterThan(0.5));
      expect(partial, lessThan(1));
    });

    test('相似度：不同标题低分（bigram Dice）', () {
      expect(
        BridgeParsers.titleSimilarity('搏击俱乐部', '完全不相干的片子'),
        lessThan(0.3),
      );
    });

    test('空串安全', () {
      expect(BridgeParsers.titleSimilarity('', 'x'), 0);
      expect(BridgeParsers.titleSimilarity('x', ''), 0);
    });
  });

  group('豆瓣反爬挑战（698 N5-C）', () {
    const challengeHtml = '<html><body>'
        '<form name="sec" id="sec" method="POST" action="/c">'
        '<input type="hidden" id="tok" name="tok" value="TOK123@yyy" />'
        '<input type="hidden" id="cha" name="cha" value="test-cha-130197" />'
        '<input type="hidden" id="sol" name="sol" value="" />'
        '<input type="hidden" id="red" name="red" value="https://movie.douban.com/subject/3541415/" />'
        '</form></body></html>';

    test('isDoubanChallenge：挑战页识别（假 200 空壳）', () {
      expect(BridgeParsers.isDoubanChallenge(challengeHtml), isTrue);
      expect(BridgeParsers.isDoubanChallenge('<html>正常页</html>'), isFalse);
      // 只有 tok 没 cha 不算（防误判普通表单）。
      expect(BridgeParsers.isDoubanChallenge('<form id="tok">'), isFalse);
    });

    test('parseDoubanChallenge：tok/cha/red/action 提取', () {
      final form = BridgeParsers.parseDoubanChallenge(challengeHtml);
      expect(form, {
        'tok': 'TOK123@yyy',
        'cha': 'test-cha-130197',
        'red': 'https://movie.douban.com/subject/3541415/',
        'action': '/c',
      });
    });

    test('parseDoubanChallenge：特征不全 → null', () {
      expect(
        BridgeParsers.parseDoubanChallenge('<input id="tok" value="a">'),
        isNull,
      );
    });

    test('mineDoubanNonce：sha512(cha+nonce) 前 4 位十六进制为 0（JS 同款）', () {
      // 秒解向量（cha 预选使 nonce=1 即解）。
      expect(BridgeParsers.mineDoubanNonce('test-cha-130197'), '1');
      // 真实挑战页实录 cha → 预计算 nonce（难度 4，22375 次命中）。
      expect(
        BridgeParsers.mineDoubanNonce(
          'f3fa74b04ee749aab6aa058e00e5a20f84dc7ed882e8f42fe68fad640a36a98c'
          '4066e0785350b4dd7500fb25ea5c2de34b6d72f5c463cd5c3138c8d9a5bcbace',
        ),
        '22375',
      );
    });

    test('mineDoubanNonce：难度参数与上限兜底', () {
      // 难度 1 好挖；挖出的 nonce 必须满足目标。
      final nonce = BridgeParsers.mineDoubanNonce('any-cha', difficulty: 1);
      expect(nonce, isNotNull);
      // 上限过小 → null（保守放弃，不抛错）。
      expect(
        BridgeParsers.mineDoubanNonce('any-cha',
            difficulty: 4, maxIterations: 10),
        isNull,
      );
    });
  });

  group('parseYear', () {
    test('抽取年份（含中文括号/分隔形态）', () {
      expect(BridgeParsers.parseYear('盗梦空间 (2010)'), 2010);
      expect(BridgeParsers.parseYear('Inception 2010'), 2010);
      expect(BridgeParsers.parseYear('无年份'), isNull);
    });
  });
}
