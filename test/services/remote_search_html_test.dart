import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/remote_search/remote_search_html.dart';

void main() {
  String build() => buildRemoteSearchHtml(
        ips: ['192.168.1.5', '10.0.0.3'],
        port: 17892,
        token: 'abc123',
      );

  test('页面含标题、搜索框与防抖', () {
    final html = build();
    expect(html, contains('HIMI 手机搜索'));
    expect(html, contains('id="q"'));
    expect(html, contains('输入关键词搜索全部服务器'));
    expect(html, contains('setTimeout(doSearch, 300)'));
    expect(html, contains("clearQ()"));
  });

  test('页面含服务器筛选 chips 与两列结果网格', () {
    final html = build();
    expect(html, contains('id="chips"'));
    expect(html, contains('全部'));
    expect(html, contains('grid-template-columns: 1fr 1fr'));
    expect(html, contains('serverId'));
    expect(html, contains('未找到结果'));
  });

  test('点卡片调 /api/select，搜索调 /api/search', () {
    final html = build();
    expect(html, contains("post('/api/search'"));
    expect(html, contains("post('/api/select'"));
    expect(html, contains('已在电视上打开'));
  });

  test('页脚含全部备选 IP 链接（带 token）', () {
    final html = build();
    expect(html, contains('http://192.168.1.5:17892/?t=abc123'));
    expect(html, contains('http://10.0.0.3:17892/?t=abc123'));
  });
}
