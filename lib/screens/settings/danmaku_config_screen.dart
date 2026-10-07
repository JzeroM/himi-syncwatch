import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/widgets/tv/tv_focusable.dart';

/// 弹幕配置页：默认开关 / API 地址 / 行数 / 屏蔽 / 同屏上限。
///
/// 速度 / 大小 / 透明度属播放页「显示调节」面板（播放中实时调），
/// 不在此页。恢复默认会把 13 项弹幕设置（含显示三参数）全部归位。
class DanmakuConfigScreen extends ConsumerStatefulWidget {
  const DanmakuConfigScreen({super.key});

  @override
  ConsumerState<DanmakuConfigScreen> createState() =>
      _DanmakuConfigScreenState();
}

class _DanmakuConfigScreenState extends ConsumerState<DanmakuConfigScreen> {
  late final TextEditingController _apiUrl;
  late final TextEditingController _blockWords;

  @override
  void initState() {
    super.initState();
    final s = ref.read(settingsProvider);
    _apiUrl = TextEditingController(text: s.danmakuApiUrl);
    _blockWords = TextEditingController(text: s.danmakuBlockWords);
  }

  @override
  void dispose() {
    _apiUrl.dispose();
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
    bool? danmakuLimitCount,
    int? danmakuMaxCount,
    double? danmakuSpeed,
    double? danmakuFontSize,
    double? danmakuOpacity,
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
          danmakuLimitCount: danmakuLimitCount,
          danmakuMaxCount: danmakuMaxCount,
          danmakuSpeed: danmakuSpeed,
          danmakuFontSize: danmakuFontSize,
          danmakuOpacity: danmakuOpacity,
        );
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
      danmakuLimitCount: false,
      danmakuMaxCount: 500,
      danmakuSpeed: 1.0,
      danmakuFontSize: 0.5,
      danmakuOpacity: 0.6,
    );
    _apiUrl.clear();
    _blockWords.clear();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('弹幕配置')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
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
          _sectionHeader('弹幕源'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              key: const ValueKey('danmakuApiUrlField'),
              controller: _apiUrl,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: '弹幕 API 地址',
                hintText: 'http://192.168.1.10:9321/<token>',
                helperText: 'danmaku_api 自建服务地址（可含 token 路径），'
                    '留空关闭弹幕',
                helperMaxLines: 2,
              ),
              onChanged: (v) => _update(danmakuApiUrl: v),
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
          _sectionHeader('数量'),
          _tvWrapRow(
            tvMode: s.tvMode,
            onTap: () => _update(danmakuLimitCount: !s.danmakuLimitCount),
            child: SwitchListTile(
              key: const ValueKey('danmakuLimitCountSwitch'),
              title: const Text('限制同屏数量'),
              subtitle: const Text('超量时等间隔采样，防高密度弹幕卡顿'),
              value: s.danmakuLimitCount,
              onChanged: (v) => _update(danmakuLimitCount: v),
            ),
          ),
          if (s.danmakuLimitCount)
            _rowsSlider(
              label: '数量上限',
              valueKey: 'danmakuMaxCount',
              value: s.danmakuMaxCount,
              min: AppSettings.danmakuMaxCountMin.toDouble(),
              max: AppSettings.danmakuMaxCountMax.toDouble(),
              divisions: AppSettings.danmakuMaxCountMax -
                  AppSettings.danmakuMaxCountMin,
              onChanged: (v) => _update(danmakuMaxCount: v),
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
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      key: ValueKey('${title}SectionHeader'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Text(
        title,
        style: const TextStyle(fontSize: 12, color: Colors.white54),
      ),
    );
  }

  /// 整数滑杆行（行数 / 数量上限共用）：标签 + 滑杆 + 数值。
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
              style: const TextStyle(fontSize: 13, color: Colors.white70),
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
              style: const TextStyle(fontSize: 12, color: Colors.white70),
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
