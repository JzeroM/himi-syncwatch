import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/settings/settings_common.dart';

/// media_kit（libmpv）引擎专属设置页：hwdec / tone-mapping / cache-size。
///
/// Phase 3 起从播放器枢纽页进入；仅手机/桌面（TV 模式不注册该引擎）。
/// 三项均为 mpv 属性，通过 NativePlayer.setProperty 直写。
class MediaKitSettingsScreen extends ConsumerStatefulWidget {
  const MediaKitSettingsScreen({super.key});

  @override
  ConsumerState<MediaKitSettingsScreen> createState() =>
      _MediaKitSettingsScreenState();
}

class _MediaKitSettingsScreenState
    extends ConsumerState<MediaKitSettingsScreen> {
  /// hwdec：'auto-safe'（默认）/ 'no'（软解）/ 'auto'（含不安全硬件路径）。
  String _hwdec = 'auto-safe';

  /// tone-mapping：'auto'（默认）/ 'no' / 'bt.2446a' / ' spline' 等。
  String _toneMapping = 'auto';

  /// cache-size：MB，0 = 关闭缓存。
  double _cacheSize = 150;

  static const _hwdecLabels = {'auto-safe': '安全硬解', 'auto': '全部硬解', 'no': '软解'};
  static const _toneMappingLabels = {
    'auto': '自动',
    'no': '关闭',
    'bt.2446a': 'BT.2446A',
    'spline': 'Spline',
  };

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);

    return SettingsSubPage(
      pageKey: const ValueKey('mediaKitSettingsPage'),
      title: 'media_kit 引擎',
      children: [
        settingOptionTile(
          context: context,
          tvMode: settings.tvMode,
          title: '硬件解码',
          subtitle: 'libmpv vo-gpu 硬解路径（Dolby Vision P5 不支持）',
          labels: _hwdecLabels,
          value: _hwdec,
          onSelected: (v) => setState(() => _hwdec = v),
        ),
        const Divider(height: 1),
        settingOptionTile(
          context: context,
          tvMode: settings.tvMode,
          title: '色调映射',
          subtitle: 'HDR → SDR 色调映射算法',
          labels: _toneMappingLabels,
          value: _toneMapping,
          onSelected: (v) => setState(() => _toneMapping = v),
        ),
        const Divider(height: 1),
        settingsTvWrapRow(
          tvMode: settings.tvMode,
          onTap: () {},
          child: ListTile(
            title: const Text('缓存大小'),
            subtitle: Text('${_cacheSize.toInt()} MB（0 = 关闭）'),
            trailing: SizedBox(
              width: 200,
              child: Slider(
                value: _cacheSize,
                min: 0,
                max: 500,
                divisions: 10,
                label: '${_cacheSize.toInt()} MB',
                onChanged: (v) => setState(() => _cacheSize = v),
              ),
            ),
          ),
        ),
        const Divider(height: 1),
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'media_kit 引擎为实验性功能，Dolby Vision Profile 5 不支持硬解，'
            'P7 会退化为 HDR10。遇到兼容性问题请切换回 MDK 引擎。',
            style: TextStyle(fontSize: 12, color: Colors.white54),
          ),
        ),
      ],
    );
  }
}
