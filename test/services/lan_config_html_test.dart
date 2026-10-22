import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/lan_config/lan_config_html.dart';

void main() {
  String html({String mode = ''}) => buildLanConfigHtml(
        ips: ['192.168.1.5'],
        port: 8096,
        token: 'tok',
        mode: mode,
      );

  test('任意 mode：恒为配置页（Emby+弹幕区块），不出现声网任何痕迹', () {
    for (final mode in ['', 'emby', 'agora', 'danmaku']) {
      final text = html(mode: mode);
      expect(text, contains('<section id="emby">'));
      expect(text, contains('emby_url'));
      expect(text, contains('<section id="danmaku">'));
      expect(text, contains('danmaku_url'));
      expect(text, isNot(contains('<section id="agora">')));
      expect(text, isNot(contains('agora_id')));
      expect(text, isNot(contains('submitAgora()')));
      expect(text, isNot(contains("highlight('agora')")));
    }
  });

  test('mode=emby：高亮滚动指向 emby', () {
    final text = html(mode: 'emby');
    expect(text, contains("highlight('emby')"));
    expect(text, isNot(contains("highlight('danmaku')")));
  });

  test('mode=danmaku：高亮滚动指向 danmaku', () {
    final text = html(mode: 'danmaku');
    expect(text, contains("highlight('danmaku')"));
    expect(text, isNot(contains("highlight('emby')")));
  });

  test('mode 为空（旧链接）：不高亮、提交函数齐全', () {
    final text = html();
    expect(text, isNot(contains("highlight('")));
    expect(text, contains('submitEmby()'));
    expect(text, contains('submitDanmaku()'));
    expect(text, contains('/api/danmaku'));
  });

  test('备用线路区块 + submitRoute 提交 /api/route（v1.1.243）', () {
    for (final mode in ['', 'emby', 'danmaku', 'route']) {
      final text = html(mode: mode);
      expect(text, contains('<section id="route">'));
      expect(text, contains('route_host'));
      expect(text, contains('submitRoute()'));
      expect(text, contains("/api/route"));
      expect(text, contains('route_https'));
      expect(text, contains('route_proxy'));
    }
  });

  test('mode=route：高亮滚动指向 route 区块', () {
    final text = html(mode: 'route');
    expect(text, contains("highlight('route')"));
    expect(text, isNot(contains("highlight('emby')")));
    expect(text, isNot(contains("highlight('danmaku')")));
  });

  test('服务器地址提示包含 IPv6 与完整 URL 粘贴', () {
    final text = html();
    expect(text, contains('[IPv6]'));
    expect(text, contains('[2408:'));
    expect(text, contains('可粘贴完整 URL'));
  });

  test('页脚备选链接带 token（各 mode 均保留）', () {
    for (final mode in ['', 'emby', 'agora']) {
      expect(html(mode: mode), contains('http://192.168.1.5:8096/?t=tok'));
    }
  });
}
