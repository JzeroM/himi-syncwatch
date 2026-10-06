/// 扫码远程搜索的手机端单页（内嵌 HTML，无外部依赖）。
///
/// 搜索框（JS 防抖 300ms）+ 横滑服务器筛选 chips + 2 列海报网格；
/// 点卡片 `POST /api/select`，电视自动打开对应详情并回 toast。
/// 页脚提供全部备选 IP 链接（带 token，供多网卡场景切换）。
String buildRemoteSearchHtml({
  required List<String> ips,
  required int port,
  required String token,
}) {
  final alternates = ips.map((ip) {
    final href = 'http://$ip:$port/?t=$token';
    return '<a href="$href">$ip</a>';
  }).join(' · ');

  return '''
<!doctype html>
<html lang="zh">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>HIMI 手机搜索</title>
<style>
  * { box-sizing: border-box; }
  body { margin: 0; padding: 16px; font-family: system-ui, -apple-system, "PingFang SC", sans-serif;
         background: #0f1220; color: #e7e9f3; }
  h1 { font-size: 20px; margin: 4px 0 6px; }
  .tip { color: #9aa0b8; font-size: 13px; margin: 0 0 14px; }
  .searchbar { display: flex; gap: 8px; margin-bottom: 12px; }
  .searchbar input { flex: 1; padding: 11px 14px; border-radius: 12px; font-size: 16px;
         border: 1px solid #343a5c; background: #171b30; color: #fff; }
  .searchbar input:focus { outline: none; border-color: #6366f1; }
  .searchbar button { width: 44px; border: none; border-radius: 12px; background: #2a2f4d;
         color: #e7e9f3; font-size: 18px; display: none; }
  .chips { display: flex; gap: 8px; overflow-x: auto; padding-bottom: 10px; margin-bottom: 6px;
         -webkit-overflow-scrolling: touch; scrollbar-width: none; }
  .chips::-webkit-scrollbar { display: none; }
  .chip { flex: none; padding: 8px 14px; border-radius: 12px; font-size: 13px; white-space: nowrap;
         background: rgba(255,255,255,.08); border: 1px solid rgba(255,255,255,.18); color: #e7e9f3; }
  .chip.on { background: #6366f1; border-color: #6366f1; font-weight: 700; }
  .status { min-height: 20px; font-size: 13px; color: #9aa0b8; margin: 2px 0 10px; }
  .status.err { color: #f87171; }
  .grid { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; }
  .card { background: #171b30; border: 1px solid #2a2f4d; border-radius: 14px; overflow: hidden;
         cursor: pointer; }
  .card:active { border-color: #6366f1; }
  .poster { position: relative; width: 100%; aspect-ratio: 2/3; background: #0d1020; }
  .poster img { width: 100%; height: 100%; object-fit: cover; display: block; }
  .badge { position: absolute; top: 6px; left: 6px; max-width: 62%; overflow: hidden;
         text-overflow: ellipsis; white-space: nowrap; padding: 2px 7px; border-radius: 7px;
         background: rgba(0,0,0,.6); color: #fff; font-size: 10px; font-weight: 700; }
  .name { padding: 8px 8px 2px; font-size: 13px; font-weight: 600; overflow: hidden;
         text-overflow: ellipsis; white-space: nowrap; }
  .year { padding: 0 8px 8px; font-size: 11px; color: #9aa0b8; }
  .toast { position: fixed; left: 50%; bottom: 34px; transform: translateX(-50%) translateY(20px);
         background: #6366f1; color: #fff; padding: 10px 18px; border-radius: 999px;
         font-size: 14px; opacity: 0; pointer-events: none; transition: all .25s; max-width: 86%;
         white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .toast.show { opacity: 1; transform: translateX(-50%) translateY(0); }
  footer { color: #6f7590; font-size: 12px; text-align: center; margin-top: 14px; }
  footer a { color: #9aa0b8; }
</style>
</head>
<body>
<h1>HIMI 手机搜索</h1>
<p class="tip">在同一 WiFi 下搜索，点选卡片后电视自动打开详情。</p>

<div class="searchbar">
  <input id="q" type="search" placeholder="输入关键词搜索全部服务器" autocomplete="off">
  <button id="clear" onclick="clearQ()">×</button>
</div>
<div id="chips" class="chips"></div>
<div id="status" class="status">输入关键词开始搜索</div>
<div id="grid" class="grid"></div>
<div id="toast" class="toast"></div>

<footer>备选地址：$alternates</footer>

<script>
var all = [], sel = '', timer = null;

function esc(s) {
  return String(s).replace(/[&<>"']/g, function (c) {
    return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c];
  });
}
function setStatus(text, err) {
  var el = document.getElementById('status');
  el.textContent = text;
  el.className = 'status' + (err ? ' err' : '');
}
function post(path, data) {
  return fetch(path, {
    method: 'POST',
    headers: {'Content-Type': 'application/json'},
    body: JSON.stringify(data),
    credentials: 'same-origin'
  }).then(function (r) {
    return r.json().catch(function () { return {ok: false, error: '响应异常'}; });
  }).catch(function () { return {ok: false, error: '网络错误'}; });
}
function clearQ() {
  document.getElementById('q').value = '';
  document.getElementById('clear').style.display = 'none';
  all = []; sel = '';
  document.getElementById('chips').innerHTML = '';
  document.getElementById('grid').innerHTML = '';
  setStatus('输入关键词开始搜索', false);
}
function onInput() {
  var v = document.getElementById('q').value;
  document.getElementById('clear').style.display = v ? 'block' : 'none';
  clearTimeout(timer);
  if (!v.trim()) { clearQ(); return; }
  setStatus('搜索中…', false);
  timer = setTimeout(doSearch, 300);
}
function doSearch() {
  var q = document.getElementById('q').value.trim();
  if (!q) return;
  post('/api/search', {q: q}).then(function (j) {
    if (!j.ok) { setStatus(j.error || '搜索失败', true); return; }
    all = j.results || [];
    renderChips();
    render();
  });
}
function renderChips() {
  var servers = [], seen = {};
  all.forEach(function (r) {
    if (!seen[r.serverId]) { seen[r.serverId] = true; servers.push(r); }
  });
  if (servers.length && !seen[sel]) sel = '';
  var html = '<div class="chip' + (sel === '' ? ' on' : '') + '" data-id="">全部</div>';
  servers.forEach(function (r) {
    html += '<div class="chip' + (sel === r.serverId ? ' on' : '') + '" data-id="' +
      esc(r.serverId) + '">' + esc(r.serverName) + '</div>';
  });
  var el = document.getElementById('chips');
  el.innerHTML = html;
  Array.prototype.forEach.call(el.querySelectorAll('.chip'), function (chip) {
    chip.onclick = function () { sel = chip.getAttribute('data-id'); renderChips(); render(); };
  });
}
function render() {
  var list = sel ? all.filter(function (r) { return r.serverId === sel; }) : all;
  var grid = document.getElementById('grid');
  if (!list.length) {
    grid.innerHTML = '';
    setStatus('未找到结果', false);
    return;
  }
  setStatus('', false);
  grid.innerHTML = list.map(function (r, i) {
    var poster = r.poster
      ? '<img src="' + esc(r.poster) + '" alt="" loading="lazy">'
      : '';
    return '<div class="card" data-i="' + i + '">' +
      '<div class="poster">' + poster +
      '<span class="badge">' + esc(r.serverName) + '</span></div>' +
      '<div class="name">' + esc(r.name) + '</div>' +
      '<div class="year">' + esc(r.year || '') + '</div></div>';
  }).join('');
  Array.prototype.forEach.call(grid.querySelectorAll('.card'), function (card) {
    card.onclick = function () { pick(list[+card.getAttribute('data-i')]); };
  });
}
function pick(r) {
  post('/api/select', {serverId: r.serverId, itemId: r.id}).then(function (j) {
    toast(j.ok ? '已在电视上打开：' + r.name : (j.error || '操作失败'));
  });
}
function toast(text) {
  var el = document.getElementById('toast');
  el.textContent = text;
  el.className = 'toast show';
  clearTimeout(el._t);
  el._t = setTimeout(function () { el.className = 'toast'; }, 2600);
}
document.getElementById('q').addEventListener('input', onInput);
</script>
</body>
</html>
''';
}
