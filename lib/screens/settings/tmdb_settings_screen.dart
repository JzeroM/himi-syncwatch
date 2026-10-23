import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/settings/settings_common.dart';
import 'package:himi_syncwatch/services/tmdb_service.dart';
import 'package:himi_syncwatch/widgets/app_toast.dart';
import 'package:himi_syncwatch/widgets/tv/tv_exclude_editable.dart';

/// TMDB 聚合模式设置：凭据 / API 与图片代理 / 观看区域。
class TmdbSettingsScreen extends ConsumerStatefulWidget {
  const TmdbSettingsScreen({super.key});

  @override
  ConsumerState<TmdbSettingsScreen> createState() => _TmdbSettingsScreenState();
}

class _TmdbSettingsScreenState extends ConsumerState<TmdbSettingsScreen> {
  late final TextEditingController _key;
  late final TextEditingController _apiBase;
  late final TextEditingController _imageBase;
  final FocusNode _qrFocusNode = FocusNode(debugLabel: 'tmdbQrConfigEntry');
  Animation<double>? _routeAnimation;
  bool _obscure = true;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    final s = ref.read(settingsProvider);
    _key = TextEditingController(text: s.tmdbApiKey);
    _apiBase = TextEditingController(text: s.tmdbApiBase);
    _imageBase = TextEditingController(text: s.tmdbImageBase);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ref.read(settingsProvider).tvMode) {
        _qrFocusNode.requestFocus();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animation = ModalRoute.of(context)?.animation;
    if (animation == null || identical(animation, _routeAnimation)) return;
    _routeAnimation?.removeStatusListener(_onRouteStatus);
    _routeAnimation = animation;
    animation.addStatusListener(_onRouteStatus);
    if (animation.isCompleted) _focusQrIfTv();
  }

  void _onRouteStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) _focusQrIfTv();
  }

  void _focusQrIfTv() {
    if (!mounted || !ref.read(settingsProvider).tvMode) return;
    if (!_qrFocusNode.hasFocus) _qrFocusNode.requestFocus();
  }

  @override
  void dispose() {
    _routeAnimation?.removeStatusListener(_onRouteStatus);
    _key.dispose();
    _apiBase.dispose();
    _imageBase.dispose();
    _qrFocusNode.dispose();
    super.dispose();
  }

  void _update({
    String? tmdbApiKey,
    String? tmdbApiBase,
    String? tmdbImageBase,
    String? tmdbWatchRegion,
  }) {
    ref.read(settingsProvider.notifier).update(
          tmdbApiKey: tmdbApiKey,
          tmdbApiBase: tmdbApiBase,
          tmdbImageBase: tmdbImageBase,
          tmdbWatchRegion: tmdbWatchRegion,
        );
  }

  Future<void> _test() async {
    final s = ref.read(settingsProvider);
    if (!s.hasTmdbCredentials) {
      showAppToast(context, '请先填写 TMDB API Key 或 Read Token');
      return;
    }
    setState(() => _testing = true);
    try {
      final service = TmdbService(
        apiBase: s.effectiveTmdbApiBase,
        credential: s.tmdbApiKey,
      );
      await service.testConnection();
      if (!mounted) return;
      showAppToast(context, 'TMDB 连接成功');
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, '连接失败：$e');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _openQrConfig() async {
    await context.push<void>('/settings/general/tmdb/qr');
    if (!mounted) return;
    final s = ref.read(settingsProvider);
    if (_key.text != s.tmdbApiKey) _key.text = s.tmdbApiKey;
    if (_apiBase.text != s.tmdbApiBase) _apiBase.text = s.tmdbApiBase;
    if (_imageBase.text != s.tmdbImageBase) _imageBase.text = s.tmdbImageBase;
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    return SettingsSubPage(
      pageKey: const ValueKey('tmdbSettingsPage'),
      title: 'TMDB 聚合',
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Text(
            s.tvMode
                ? 'TMDB 聚合模式会跨全部已认证服务器聚合收藏与继续观看，'
                    '并用 TMDB 目录发现服务器中已有的电影/剧集。'
                    'TV 模式请使用下方扫码配置，用手机填写 API Key、代理与区域。'
                : 'TMDB 聚合模式会跨全部已认证服务器聚合收藏与继续观看，'
                    '并用 TMDB 目录发现服务器中已有的电影/剧集。应用不内置公共 Key，'
                    '请填写自己的 v3 API Key 或 v4 Read Access Token。',
            style: const TextStyle(
              fontSize: 12,
              color: Colors.white54,
              height: 1.5,
            ),
          ),
        ),
        const Divider(height: 1),
        KeyedSubtree(
          key: const ValueKey('tmdbQrConfigFocus'),
          child: settingsTvWrapRow(
            tvMode: s.tvMode,
            focusNode: _qrFocusNode,
            onTap: _openQrConfig,
            child: ListTile(
              key: const ValueKey('tmdbQrConfigEntry'),
              leading: const Icon(Icons.qr_code),
              title: const Text('扫码配置'),
              subtitle: const Text('手机扫码填写 API Key、代理地址与观看区域'),
              trailing: const Icon(
                Icons.chevron_right,
                size: 18,
                color: Colors.white54,
              ),
              onTap: _openQrConfig,
            ),
          ),
        ),
        const Divider(height: 1),
        if (!s.tvMode) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: tvExcludeEditable(
              tvMode: s.tvMode,
              child: TextField(
                key: const ValueKey('tmdbApiKeyField'),
                controller: _key,
                obscureText: _obscure,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: 'API Key / Read Token',
                  hintText: 'v3 key 或以 eyJ 开头的 v4 token',
                  helperText: '保存在本机安全存储，不会上传或写入日志',
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                onChanged: (v) => _update(tmdbApiKey: v),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: tvExcludeEditable(
              tvMode: s.tvMode,
              child: TextField(
                key: const ValueKey('tmdbApiBaseField'),
                controller: _apiBase,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'API 代理地址（可选）',
                  hintText: 'https://api.tmdb.org',
                  helperText: '默认使用 https://api.tmdb.org；'
                      '代理地址无需带 /3，留空使用 https://api.themoviedb.org',
                ),
                onChanged: (v) => _update(tmdbApiBase: v),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: tvExcludeEditable(
              tvMode: s.tvMode,
              child: TextField(
                key: const ValueKey('tmdbImageBaseField'),
                controller: _imageBase,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: '图片代理地址（可选）',
                  hintText: 'https://wsrv.nl/?url=https://image.tmdb.org',
                  helperText:
                      '默认使用 https://wsrv.nl/?url=https://image.tmdb.org；'
                      '代理地址无需带 /t/p，留空使用 https://image.tmdb.org',
                ),
                onChanged: (v) => _update(tmdbImageBase: v),
              ),
            ),
          ),
        ],
        KeyedSubtree(
          key: const ValueKey('tmdbWatchRegionTile'),
          child: settingOptionTile(
            context: context,
            tvMode: s.tvMode,
            title: '流媒体平台区域',
            subtitle: '平台栏与平台网格使用的 TMDB watch region',
            labels: {
              for (final region in AppSettings.tmdbWatchRegions)
                region: _regionLabel(region),
            },
            value: s.tmdbWatchRegion,
            onSelected: (value) => _update(tmdbWatchRegion: value),
          ),
        ),
        const Divider(height: 1),
        const ExcludeFocus(
          child: ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('为什么需要 TMDB Key'),
            subtitle: Text(
              'TMDB 目录接口需要凭据。资源匹配仍完全依赖 Emby 的 ProviderIds，'
              '收藏和继续观看不会上传到 TMDB。',
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: KeyedSubtree(
            key: const ValueKey('tmdbTestConnectionTile'),
            child: settingsTvWrapRow(
              tvMode: s.tvMode,
              onTap: () {
                if (!_testing) _test();
              },
              child: tvExcludeEditable(
                tvMode: s.tvMode,
                child: FilledButton.icon(
                  key: const ValueKey('tmdbTestConnection'),
                  onPressed: _testing ? null : _test,
                  icon: _testing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_tethering),
                  label: const Text('测试连接'),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  static String _regionLabel(String region) => switch (region) {
        'US' => '美国 (US)',
        'GB' => '英国 (GB)',
        'CA' => '加拿大 (CA)',
        'AU' => '澳大利亚 (AU)',
        'JP' => '日本 (JP)',
        'KR' => '韩国 (KR)',
        'HK' => '香港 (HK)',
        'TW' => '台湾 (TW)',
        'SG' => '新加坡 (SG)',
        _ => region,
      };
}
