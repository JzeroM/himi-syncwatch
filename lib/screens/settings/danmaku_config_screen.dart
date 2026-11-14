import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/settings/settings_common.dart';
import 'package:himi_syncwatch/widgets/glass/glass_config.dart';
import 'package:himi_syncwatch/widgets/app_toast.dart';
import 'package:himi_syncwatch/widgets/glass/glass_container.dart';
import 'package:himi_syncwatch/widgets/tv/tv_confirm_dialog.dart';
import 'package:himi_syncwatch/widgets/tv/tv_app_bar_icon_button.dart';
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
          danmakuLimitCount: danmakuLimitCount,
          danmakuMaxCount: danmakuMaxCount,
          danmakuSpeed: danmakuSpeed,
          danmakuFontSize: danmakuFontSize,
          danmakuOpacity: danmakuOpacity,
          danmakuColorMode: danmakuColorMode,
          danmakuCustomColor: danmakuCustomColor,
          danmakuOutlineWidth: danmakuOutlineWidth,
          danmakuOutlineColor: danmakuOutlineColor,
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
      danmakuSpeed: 0.7,
      danmakuFontSize: 0.5,
      danmakuOpacity: 0.8,
      danmakuColorMode: 'color',
      danmakuCustomColor: 0xFFFFFFFF,
      danmakuOutlineWidth: 1.0,
      danmakuOutlineColor: 0xFF000000,
    );
    _apiUrl.clear();
    _blockWords.clear();
  }

  /// 扫码配置：打开二维码页（mode=danmaku），手机提交后落库；返回时同步
  /// 本地输入框（手机端改了地址）。
  Future<void> _openQrConfig() async {
    await context.push<void>('/settings/player/danmaku/qr');
    if (!mounted) return;
    final url = ref.read(settingsProvider).danmakuApiUrl;
    if (_apiUrl.text != url) {
      _apiUrl.text = url;
    }
  }

  Future<void> _clearApiConfig() async {
    if (ref.read(settingsProvider).danmakuApiUrl.isEmpty) return;
    final confirmed = await showTvConfirmDialog(
      context: context,
      title: '清除弹幕 API 地址？',
      message: '只清除弹幕 API 地址，行数、屏蔽、同屏数量等设置保持不变。',
      confirmLabel: '清除',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    await ref.read(settingsProvider.notifier).update(danmakuApiUrl: '');
    if (!mounted) return;
    _apiUrl.clear();
    showAppToast(context, '弹幕 API 地址已清除');
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
            _sectionHeader('弹幕源'),
            if (s.tvMode) ...[
              // TV 无输入法：只保留扫码配置；手机扫码提交后落库。
              settingsTvWrapRow(
                tvMode: s.tvMode,
                onTap: _openQrConfig,
                child: ListTile(
                  key: const ValueKey('danmakuQrConfigEntry'),
                  leading: const Icon(Icons.qr_code),
                  title: const Text('扫码配置'),
                  subtitle: const Text('手机扫码打开网页，填弹幕 API 地址提交到电视'),
                  trailing: const Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: Colors.white54,
                  ),
                  onTap: _openQrConfig,
                ),
              ),
              settingsTvWrapRow(
                tvMode: s.tvMode,
                onTap: _clearApiConfig,
                child: ListTile(
                  key: const ValueKey('danmakuClearConfigEntry'),
                  leading:
                      Icon(Icons.delete_outline, color: Colors.red.shade300),
                  title: const Text('清除配置'),
                  subtitle: const Text('只清除弹幕 API 地址，保留行数/屏蔽设置'),
                  onTap: _clearApiConfig,
                ),
              ),
            ] else ...[
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
            ],
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
                                  : Colors.white24,
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
                  const SizedBox(
                    width: 76,
                    child: Text(
                      '描边宽度',
                      style: TextStyle(fontSize: 13, color: Colors.white70),
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
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                ],
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
