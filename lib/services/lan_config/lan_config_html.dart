/// 局域网扫码配置的手机端单页（内嵌 HTML，无外部依赖）。
///
/// 提供 Emby 服务器配置、TMDB 配置、弹幕 API 地址配置与备用线路添加四个区块。
/// [mode] 为 `emby` / `tmdb` / `danmaku` / `route` 时高亮并滚动到对应区块；
/// 其余（含旧链接的 `agora`）不高亮，页面恒为同一份配置页。
/// 页脚提供全部备选 IP 链接（带 token，供多网卡场景切换）。
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
    'tmdb' => _highlightJs('tmdb'),
    'danmaku' => _highlightJs('danmaku'),
    'route' => _highlightJs('route'),
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
  input, select { width: 100%; padding: 10px 12px; border-radius: 8px; font-size: 16px;
          border: 1px solid #343a5c; background: #0d1020; color: #fff; }
  input:focus, select:focus { outline: none; border-color: #6366f1; }
  .row { display: flex; gap: 10px; }
  .row > div { flex: 1; }
  .row > div.wide { flex: 2; }
  .sw { display: flex; align-items: center; justify-content: space-between;
        margin-top: 12px; }
  .sw span { font-size: 13px; color: #b9bed4; }
  .sw input { width: 44px; }
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
  <input id="emby_url" type="url" placeholder="https://emby.example.com:8096 或 https://[2408:...]:8096" autocomplete="url">
  <label>备注名称（可选）</label>
  <input id="emby_name" type="text" placeholder="如：家里NAS">
  <label>用户名</label>
  <input id="emby_user" type="text" autocomplete="username">
  <label>密码</label>
  <input id="emby_pass" type="password" autocomplete="current-password">
  <button id="emby_btn" onclick="submitEmby()">连接并登录</button>
  <div class="msg" id="emby_msg"></div>
</section>

<section id="tmdb">
  <h2>配置 TMDB</h2>
  <label>API Key / Read Access Token（必填）</label>
  <input id="tmdb_key" type="password" autocomplete="off" placeholder="v3 key 或以 eyJ 开头的 v4 token">
  <label>API 代理地址（可选，留空保持当前）</label>
  <input id="tmdb_api_base" type="url" placeholder="https://api.tmdb.org" autocomplete="url">
  <label>图片代理地址（可选，留空保持当前）</label>
  <input id="tmdb_image_base" type="url" placeholder="https://wsrv.nl/?url=https://image.tmdb.org" autocomplete="url">
  <label>流媒体平台区域</label>
  <select id="tmdb_region">
    <option value="">保持当前</option>
    <option value="US">美国 (US)</option>
    <option value="GB">英国 (GB)</option>
    <option value="CA">加拿大 (CA)</option>
    <option value="AU">澳大利亚 (AU)</option>
    <option value="JP">日本 (JP)</option>
    <option value="KR">韩国 (KR)</option>
    <option value="HK">香港 (HK)</option>
    <option value="TW">台湾 (TW)</option>
    <option value="SG">新加坡 (SG)</option>
  </select>
  <button id="tmdb_btn" onclick="submitTmdb()">保存到电视</button>
  <div class="msg" id="tmdb_msg"></div>
</section>

<section id="danmaku">
  <h2>配置弹幕 API 地址</h2>
  <label>弹幕 API 地址</label>
  <input id="danmaku_url" type="url" placeholder="http://192.168.1.10:9321/<token>" autocomplete="url">
  <button id="danmaku_btn" onclick="submitDanmaku()">保存到电视</button>
  <div class="msg" id="danmaku_msg"></div>
</section>

<section id="route">
  <h2>添加备用线路</h2>
  <label>线路名称（可选）</label>
  <input id="route_name" type="text" placeholder="如：备用入口">
  <label>服务器地址（IP / 域名 / [IPv6]，可粘贴完整 URL）</label>
  <input id="route_host" type="text" placeholder="例如：192.168.1.100、[2408:...] 或 https://emby.example.com:8096">
  <div class="row">
    <div class="wide">
      <label>路径（可选）</label>
      <input id="route_path" type="text" placeholder="Path">
    </div>
    <div>
      <label>端口</label>
      <input id="route_port" type="text" inputmode="numeric" value="8096">
    </div>
  </div>
  <div class="sw"><span>使用 HTTPS</span><input id="route_https" type="checkbox"></div>
  <div class="sw"><span>作为反代使用（API 走此线路，媒体直连主线路）</span><input id="route_proxy" type="checkbox"></div>
  <button id="route_btn" onclick="submitRoute()">保存到电视</button>
  <div class="msg" id="route_msg"></div>
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
function submitTmdb() {
  post('/api/tmdb', {
    apiKey: document.getElementById('tmdb_key').value.trim(),
    apiBase: document.getElementById('tmdb_api_base').value.trim(),
    imageBase: document.getElementById('tmdb_image_base').value.trim(),
    region: document.getElementById('tmdb_region').value
  }, 'tmdb_btn', 'tmdb_msg');
}
function submitDanmaku() {
  post('/api/danmaku', {
    url: document.getElementById('danmaku_url').value.trim()
  }, 'danmaku_btn', 'danmaku_msg');
}
function submitRoute() {
  post('/api/route', {
    name: document.getElementById('route_name').value.trim(),
    host: document.getElementById('route_host').value.trim(),
    path: document.getElementById('route_path').value.trim(),
    port: document.getElementById('route_port').value.trim(),
    https: document.getElementById('route_https').checked,
    reverseProxy: document.getElementById('route_proxy').checked
  }, 'route_btn', 'route_msg');
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
