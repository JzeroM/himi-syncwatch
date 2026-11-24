import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/services/danmaku/danmaku_caches.dart';
import 'package:himi_syncwatch/services/danmaku/danmaku_match_memory.dart';
import 'package:himi_syncwatch/services/danmaku/danmaku_server.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/settings/settings_common.dart';
import 'package:himi_syncwatch/widgets/glass/glass_config.dart';
import 'package:himi_syncwatch/widgets/glass/glass_container.dart';
import 'package:himi_syncwatch/widgets/tv/tv_app_bar_icon_button.dart';
import 'package:himi_syncwatch/widgets/tv/tv_focusable.dart';

/// 弹幕配置页：默认开关 / 弹幕源 / 行数 / 屏蔽 / 样式。
///
/// 速度 / 大小 / 透明度属播放页「显示调节」面板（播放中实时调），
/// 不在此页。恢复默认会把本页所有弹幕设置归位。
class DanmakuConfigScreen extends ConsumerStatefulWidget {
  const DanmakuConfigScreen({super.key});

  @override
  ConsumerState<DanmakuConfigScreen> createState() =>
      _DanmakuConfigScreenState();
}

class _DanmakuConfigScreenState extends ConsumerState<DanmakuConfigScreen> {
  late final TextEditingController _blockWords;

  /// 694 M3：已保存的弹幕绑定（匹配记忆管理列表）。
  List<DanmakuMatchEntry> _matchEntries = const [];

  @override
  void initState() {
    super.initState();
    final s = ref.read(settingsProvider);
    _blockWords = TextEditingController(text: s.danmakuBlockWords);
    _loadMatchEntries();
  }

  Future<void> _loadMatchEntries() async {
    final entries = await DanmakuCaches.matchMemory.all();
    if (mounted) setState(() => _matchEntries = entries);
  }

  @override
  void dispose() {
    _blockWords.dispose();
    super.dispose();
  }

  void _update({
    bool? danmakuDefaultOn,
    String? danmakuApiUrl,
    int? danmakuScrollRows,
    int? danmakuTopRows,
    int? danmakuBottomRows,
    bool? danmakuBlockTop,
    bool? danmakuBlockBottom,
    String? danmakuBlockWords,
    double? danmakuSpeed,
    double? danmakuFontSize,
    double? danmakuOpacity,
    String? danmakuServersJson,
    String? danmakuColorMode,
    int? danmakuCustomColor,
    double? danmakuOutlineWidth,
    int? danmakuOutlineColor,
  }) {
    ref.read(settingsProvider.notifier).update(
          danmakuDefaultOn: danmakuDefaultOn,
          danmakuApiUrl: danmakuApiUrl,
          danmakuScrollRows: danmakuScrollRows,
          danmakuTopRows: danmakuTopRows,
          danmakuBottomRows: danmakuBottomRows,
          danmakuBlockTop: danmakuBlockTop,
          danmakuBlockBottom: danmakuBlockBottom,
          danmakuBlockWords: danmakuBlockWords,
          danmakuSpeed: danmakuSpeed,
          danmakuFontSize: danmakuFontSize,
          danmakuOpacity: danmakuOpacity,
          danmakuServersJson: danmakuServersJson,
          danmakuColorMode: danmakuColorMode,
          danmakuCustomColor: danmakuCustomColor,
          danmakuOutlineWidth: danmakuOutlineWidth,
          danmakuOutlineColor: danmakuOutlineColor,
        );
  }

  /// 写回服务器列表（同时把「优先级最高且启用」同步到老字段，兼容旧逻辑）。
  void _applyServers(List<DanmakuServer> servers) {
    final reindexed = <DanmakuServer>[
      for (var i = 0; i < servers.length; i++) servers[i].copyWith(priority: i),
    ];
    final active = reindexed.where((e) => e.enabled).toList();
    _update(
      danmakuServersJson: AppSettings.encodeDanmakuServers(reindexed),
      danmakuApiUrl: active.isEmpty ? '' : active.first.baseUrl,
    );
  }

  /// 新增 / 编辑弹幕源（同一个对话框，[existing] 非空即编辑）。
  Future<void> _editServer([DanmakuServer? existing]) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final urlCtrl = TextEditingController(text: existing?.baseUrl ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? '添加弹幕源' : '编辑弹幕源'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const ValueKey('danmakuServerNameField'),
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: '名称'),
            ),
            TextField(
              key: const ValueKey('danmakuServerUrlField'),
              controller: urlCtrl,
              decoration: const InputDecoration(
                labelText: '地址',
                hintText: 'http://192.168.1.10:9321/TOKEN',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const ValueKey('danmakuServerAddConfirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(existing == null ? '添加' : '保存'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      final url = urlCtrl.text.trim();
      if (url.isEmpty) return;
      final name = nameCtrl.text.trim().isEmpty ? url : nameCtrl.text.trim();
      final current = ref.read(settingsProvider).danmakuServers;
      if (existing == null) {
        _applyServers([
          ...current,
          DanmakuServer(
            id: 'srv-${DateTime.now().microsecondsSinceEpoch}',
            name: name,
            baseUrl: url,
          ),
        ]);
      } else {
        _applyServers([
          for (final srv in current)
            srv.id == existing.id
                ? srv.copyWith(name: name, baseUrl: url)
                : srv,
        ]);
      }
    }
    nameCtrl.dispose();
    urlCtrl.dispose();
  }

  void _resetDefaults() {
    _update(
      danmakuDefaultOn: true,
      danmakuApiUrl: '',
      danmakuScrollRows: 30,
      danmakuTopRows: 4,
      danmakuBottomRows: 4,
      danmakuBlockTop: false,
      danmakuBlockBottom: false,
      danmakuBlockWords: '',
      danmakuSpeed: 0.7,
      danmakuFontSize: 0.5,
      danmakuOpacity: 0.8,
      danmakuColorMode: 'color',
      danmakuCustomColor: 0xFFFFFFFF,
      danmakuOutlineWidth: 1.0,
      danmakuOutlineColor: 0xFF000000,
      danmakuServersJson: '',
    );
    _blockWords.clear();
  }

  /// 扫码配置：打开二维码页（mode=danmaku），手机提交后落库；返回时同步
  /// 本地输入框（手机端改了地址）。
  Future<void> _openQrConfig() async {
    await context.push<void>('/settings/player/danmaku/qr');
    if (!mounted) return;
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);

    return SettingsPageBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          title: const Text('弹幕配置'),
          backgroundColor: Colors.transparent,
          elevation: 0,
          flexibleSpace: const GlassBackdrop(),
          leading: const TvBackButton(),
        ),
        body: ListView(
          padding: EdgeInsets.only(
            top: GlassConfig.topInsetOf(context),
            bottom: GlassConfig.bottomReserveOf(context),
          ),
          children: [
            _tvWrapRow(
              tvMode: s.tvMode,
              onTap: () => _update(danmakuDefaultOn: !s.danmakuDefaultOn),
              child: SwitchListTile(
                key: const ValueKey('danmakuDefaultOnSwitch'),
                title: const Text('弹幕默认打开'),
                subtitle: const Text('进播放页自动开启；未配置 API 地址时不生效'),
                value: s.danmakuDefaultOn,
                onChanged: (v) => _update(danmakuDefaultOn: v),
              ),
            ),
            const Divider(height: 1),
            _sectionHeader('弹幕源（从上到下按优先级）'),
            // TV 无输入法：保留扫码入口（手机扫码写入第一个弹幕源）。
            if (s.tvMode)
              settingsTvWrapRow(
                tvMode: s.tvMode,
                onTap: _openQrConfig,
                child: ListTile(
                  key: const ValueKey('danmakuQrConfigEntry'),
                  leading: const Icon(Icons.qr_code),
                  title: const Text('扫码添加弹幕源'),
                  subtitle: const Text('手机扫码填地址，提交后写入第一个弹幕源'),
                  trailing: Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54),
                  ),
                  onTap: _openQrConfig,
                ),
              ),
            for (var i = 0; i < s.danmakuServers.length; i++)
              ListTile(
                key: ValueKey('danmakuServer-${s.danmakuServers[i].id}'),
                dense: true,
                leading: Checkbox(
                  value: s.danmakuServers[i].enabled,
                  onChanged: (v) {
                    final list = [...s.danmakuServers];
                    list[i] = list[i].copyWith(enabled: v ?? false);
                    _applyServers(list);
                  },
                ),
                title: Text(
                  s.danmakuServers[i].name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  s.danmakuServers[i].baseUrl,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      key: ValueKey(
                          'danmakuServerEdit-${s.danmakuServers[i].id}'),
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => _editServer(s.danmakuServers[i]),
                    ),
                    IconButton(
                      key: ValueKey(
                          'danmakuServerDelete-${s.danmakuServers[i].id}'),
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () {
                        final list = [...s.danmakuServers]..removeAt(i);
                        _applyServers(list);
                      },
                    ),
                  ],
                ),
              ),
            if (s.danmakuServers.isEmpty)
              Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  '还没有弹幕源，点下面「添加弹幕源」',
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54)),
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('danmakuServerAdd'),
                onPressed: () => _editServer(),
                icon: const Icon(Icons.add),
                label: const Text('添加弹幕源'),
              ),
            ),
            const Divider(height: 1),
            _sectionHeader('行数（滚动按屏高自动铺满，此值为上限）'),
            _rowsSlider(
              label: '滚动上限',
              valueKey: 'danmakuScrollRows',
              value: s.danmakuScrollRows,
              onChanged: (v) => _update(danmakuScrollRows: v),
            ),
            _rowsSlider(
              label: '顶部行数',
              valueKey: 'danmakuTopRows',
              value: s.danmakuTopRows,
              onChanged: (v) => _update(danmakuTopRows: v),
            ),
            _rowsSlider(
              label: '底部行数',
              valueKey: 'danmakuBottomRows',
              value: s.danmakuBottomRows,
              onChanged: (v) => _update(danmakuBottomRows: v),
            ),
            const Divider(height: 1),
            _sectionHeader('屏蔽'),
            _tvWrapRow(
              tvMode: s.tvMode,
              onTap: () => _update(danmakuBlockTop: !s.danmakuBlockTop),
              child: SwitchListTile(
                key: const ValueKey('danmakuBlockTopSwitch'),
                title: const Text('屏蔽顶部弹幕'),
                value: s.danmakuBlockTop,
                onChanged: (v) => _update(danmakuBlockTop: v),
              ),
            ),
            const Divider(height: 1),
            _tvWrapRow(
              tvMode: s.tvMode,
              onTap: () => _update(danmakuBlockBottom: !s.danmakuBlockBottom),
              child: SwitchListTile(
                key: const ValueKey('danmakuBlockBottomSwitch'),
                title: const Text('屏蔽底部弹幕'),
                value: s.danmakuBlockBottom,
                onChanged: (v) => _update(danmakuBlockBottom: v),
              ),
            ),
            if (!s.tvMode)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: TextField(
                  key: const ValueKey('danmakuBlockWordsField'),
                  controller: _blockWords,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: '屏蔽关键词',
                    hintText: '剧透, 广告',
                    helperText: '英文逗号分隔，命中的弹幕整条不显示',
                  ),
                  onChanged: (v) => _update(danmakuBlockWords: v),
                ),
              ),
            const Divider(height: 1),
            _sectionHeader('样式'),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: SegmentedButton<String>(
                key: const ValueKey('danmakuColorMode'),
                segments: const [
                  ButtonSegment(value: 'color', label: Text('源色')),
                  ButtonSegment(value: 'white', label: Text('白色')),
                  ButtonSegment(value: 'custom', label: Text('自定义')),
                ],
                selected: {s.danmakuColorMode},
                onSelectionChanged: (v) =>
                    _update(danmakuColorMode: v.first),
              ),
            ),
            if (s.danmakuColorMode == 'custom')
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final c in const [
                      0xFFFFFFFF,
                      0xFFFFD54F,
                      0xFF81C784,
                      0xFF64B5F6,
                      0xFFBA68C8,
                      0xFFFF8A65,
                      0xFF4DD0E1,
                      0xFFE57373,
                    ])
                      InkWell(
                        key: ValueKey('danmakuColor-$c'),
                        onTap: () => _update(danmakuCustomColor: c),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: Color(c),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: s.danmakuCustomColor == c
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.24),
                              width: s.danmakuCustomColor == c ? 3 : 1,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            // 描边宽度是小数（0~4），用原生 Slider（`_rowsSlider` 只收 int）。
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 76,
                    child: Text(
                      '描边宽度',
                      style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.70)),
                    ),
                  ),
                  Expanded(
                    child: Slider(
                      key: const ValueKey('danmakuOutlineWidthSlider'),
                      min: AppSettings.danmakuOutlineWidthMin,
                      max: AppSettings.danmakuOutlineWidthMax,
                      divisions: 8,
                      value: s.danmakuOutlineWidth.clamp(
                        AppSettings.danmakuOutlineWidthMin,
                        AppSettings.danmakuOutlineWidthMax,
                      ),
                      onChanged: (v) => _update(danmakuOutlineWidth: v),
                    ),
                  ),
                  SizedBox(
                    width: 40,
                    child: Text(
                      s.danmakuOutlineWidth.toStringAsFixed(1),
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.70),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // ── 694 M3：已保存的弹幕绑定（匹配记忆管理）──
            _sectionHeader('已保存的弹幕绑定'),
            if (_matchEntries.isEmpty)
              ListTile(
                dense: true,
                title: Text(
                  '暂无绑定记录（自动/手动匹配成功后自动保存）',
                  style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54)),
                ),
              ),
            for (final entry in _matchEntries)
              ListTile(
                key: ValueKey('danmakuMatch-${entry.key}'),
                dense: true,
                title: Text(
                  entry.record.animeTitle.isNotEmpty
                      ? '${entry.record.animeTitle}'
                          '${entry.record.episodeTitle.isNotEmpty ? ' · ${entry.record.episodeTitle}' : ''}'
                      : 'episodeId ${entry.record.episodeId}',
                ),
                subtitle: Text(
                  '${entry.record.source == DanmakuMatchSource.manual ? '手动绑定' : '自动匹配'}'
                  ' · ${DateTime.fromMillisecondsSinceEpoch(entry.record.savedAtMs).toString().substring(0, 16)}',
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54)),
                ),
                trailing: IconButton(
                  key: ValueKey('danmakuMatchDelete-${entry.key}'),
                  icon: Icon(
                    Icons.delete_outline,
                    size: 18,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54),
                  ),
                  onPressed: () async {
                    await DanmakuCaches.matchMemory
                        .remove(itemKey: entry.key, nameKey: entry.key);
                    await _loadMatchEntries();
                  },
                ),
              ),
            if (_matchEntries.isNotEmpty)
              Center(
                child: TextButton(
                  key: const ValueKey('danmakuClearMatches'),
                  onPressed: () async {
                    await DanmakuCaches.matchMemory.clear();
                    await _loadMatchEntries();
                  },
                  child: const Text('全部清除'),
                ),
              ),
            const Divider(height: 1),
            Center(
              child: TextButton(
                key: const ValueKey('danmakuResetDefaults'),
                onPressed: _resetDefaults,
                child: const Text('恢复默认'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      key: ValueKey('${title}SectionHeader'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Text(
        title,
        style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54)),
      ),
    );
  }

  /// 整数滑杆行（行数）：标签 + 滑杆 + 数值。
  Widget _rowsSlider({
    required String label,
    required String valueKey,
    required int value,
    required ValueChanged<int> onChanged,
    double? min,
    double? max,
    int? divisions,
  }) {
    final lo = min ?? AppSettings.danmakuRowsMin.toDouble();
    final hi = max ?? AppSettings.danmakuRowsMax.toDouble();
    final steps = divisions ?? (hi - lo).round();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 76,
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.70)),
            ),
          ),
          Expanded(
            child: Slider(
              key: ValueKey('${valueKey}Slider'),
              min: lo,
              max: hi,
              divisions: steps == 0 ? null : steps,
              value: value.clamp(lo.round(), hi.round()).toDouble(),
              onChanged: (v) => onChanged(v.round()),
            ),
          ),
          SizedBox(
            width: 48,
            child: Text(
              '$value',
              key: ValueKey(valueKey),
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.70)),
            ),
          ),
        ],
      ),
    );
  }

  /// TV 模式把开关行包成 TvFocusable 描边焦点（与设置主页同交互）。
  Widget _tvWrapRow({
    required bool tvMode,
    required VoidCallback onTap,
    required Widget child,
  }) {
    if (!tvMode) return child;
    return TvFocusable(
      onTap: onTap,
      child: ExcludeFocus(child: child),
    );
  }
}
