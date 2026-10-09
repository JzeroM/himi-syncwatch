/// 局域网扫码配置的手机端单页（内嵌 HTML，无外部依赖）。
///
/// 提供 Emby 服务器配置与弹幕 API 地址配置两个区块。[mode] 为 `emby` /
/// `danmaku` 时高亮并滚动到对应区块；其余（含旧链接的 `agora`）不高亮，
/// 页面恒为同一份配置页。页脚提供全部备选 IP 链接（带 token，供多网卡
/// 场景切换）。
String buildLanConfigHtml({
  required List<String> ips,
  required int port,
  required String token,
  String mode = '',
}) {
  final alternates = ips.map((ip) {
    final href = 'http://$ip:$port/?t=$token';
    return '<a href="$href">$ip</a>';
  }).join(' · ');

  final highlightJs = switch (mode) {
    'emby' => _highlightJs('emby'),
    'danmaku' => _highlightJs('danmaku'),
    _ => '',
  };

  return '''
<!doctype html>
<html lang="zh">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>HIMI 手机配置</title>
<style>
  * { box-sizing: border-box; }
  body { margin: 0; padding: 16px; font-family: system-ui, -apple-system, "PingFang SC", sans-serif;
         background: #0f1220; color: #e7e9f3; }
  h1 { font-size: 20px; margin: 4px 0 8px; }
  .tip { color: #9aa0b8; font-size: 13px; margin: 0 0 16px; }
  section { background: #171b30; border: 1px solid #2a2f4d; border-radius: 14px;
            padding: 16px; margin-bottom: 16px; }
  section.hl { border-color: #6366f1; box-shadow: 0 0 0 2px #6366f155; }
  h2 { font-size: 16px; margin: 0 0 12px; }
  label { display: block; font-size: 13px; color: #b9bed4; margin: 10px 0 4px; }
  input { width: 100%; padding: 10px 12px; border-radius: 8px; font-size: 16px;
          border: 1px solid #343a5c; background: #0d1020; color: #fff; }
  input:focus { outline: none; border-color: #6366f1; }
  button { width: 100%; margin-top: 14px; padding: 12px; border: none; border-radius: 8px;
           background: #6366f1; color: #fff; font-size: 15px; font-weight: 600; }
  button:disabled { opacity: .5; }
  .msg { margin-top: 10px; font-size: 14px; min-height: 18px; }
  .msg.ok { color: #34d399; }
  .msg.err { color: #f87171; }
  footer { color: #6f7590; font-size: 12px; text-align: center; margin-top: 8px; }
  footer a { color: #9aa0b8; }
</style>
</head>
<body>
<h1>HIMI 手机配置</h1>
<p class="tip">请确保手机与电视/电脑连接同一 WiFi，配置成功后本页会显示结果。</p>

<section id="emby">
  <h2>配置 Emby 服务器</h2>
  <label>服务器地址</label>
  <input id="emby_url" type="url" placeholder="https://emby.example.com:8096" autocomplete="url">
  <label>备注名称（可选）</label>
  <input id="emby_name" type="text" placeholder="如：家里NAS">
  <label>用户名</label>
  <input id="emby_user" type="text" autocomplete="username">
  <label>密码</label>
  <input id="emby_pass" type="password" autocomplete="current-password">
  <button id="emby_btn" onclick="submitEmby()">连接并登录</button>
  <div class="msg" id="emby_msg"></div>
</section>

<section id="danmaku">
  <h2>配置弹幕 API 地址</h2>
  <label>弹幕 API 地址</label>
  <input id="danmaku_url" type="url" placeholder="http://192.168.1.10:9321/<token>" autocomplete="url">
  <button id="danmaku_btn" onclick="submitDanmaku()">保存到电视</button>
  <div class="msg" id="danmaku_msg"></div>
</section>

<footer>备选地址：$alternates</footer>

<script>
function setMsg(id, text, ok) {
  const el = document.getElementById(id);
  el.textContent = text;
  el.className = 'msg ' + (ok ? 'ok' : 'err');
}
async function post(path, data, btn, msgId) {
  const b = document.getElementById(btn);
  b.disabled = true;
  setMsg(msgId, '提交中…', true);
  try {
    const r = await fetch(path, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(data),
      credentials: 'same-origin'
    });
    const j = await r.json().catch(() => ({ ok: false, error: '响应异常' }));
    setMsg(msgId, j.ok ? (j.message || '成功') : (j.error || '失败'), !!j.ok);
  } catch (e) {
    setMsg(msgId, '网络错误：' + e, false);
  } finally {
    b.disabled = false;
  }
}
function submitEmby() {
  post('/api/emby', {
    url: document.getElementById('emby_url').value.trim(),
    name: document.getElementById('emby_name').value.trim(),
    username: document.getElementById('emby_user').value.trim(),
    password: document.getElementById('emby_pass').value
  }, 'emby_btn', 'emby_msg');
}
function submitDanmaku() {
  post('/api/danmaku', {
    url: document.getElementById('danmaku_url').value.trim()
  }, 'danmaku_btn', 'danmaku_msg');
}
function highlight(id) {
  const el = document.getElementById(id);
  if (!el) return;
  el.classList.add('hl');
  el.scrollIntoView({ behavior: 'smooth', block: 'start' });
}
$highlightJs
</script>
</body>
</html>
''';
}

String _highlightJs(String id) =>
    "document.addEventListener('DOMContentLoaded', () => highlight('$id'));";
