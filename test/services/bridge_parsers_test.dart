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

  group('extractDoubanSubjects（搜索候选）', () {
    test('抽 subject id + 锚文本标题（去重）', () {
      const html = '<a href="https://movie.douban.com/subject/3541415/">盗梦空间</a>'
          '<a href="https://movie.douban.com/subject/3541415/?from=rec">重复</a>'
          '<a href="https://movie.douban.com/subject/1295644/">这个杀手不太冷</a>';
      final out = BridgeParsers.extractDoubanSubjects(html);
      expect(out.length, 2);
      expect(out.first['id'], '3541415');
      expect(out.first['title'], '盗梦空间');
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

  group('parseYear', () {
    test('抽取年份（含中文括号/分隔形态）', () {
      expect(BridgeParsers.parseYear('盗梦空间 (2010)'), 2010);
      expect(BridgeParsers.parseYear('Inception 2010'), 2010);
      expect(BridgeParsers.parseYear('无年份'), isNull);
    });
  });
}
