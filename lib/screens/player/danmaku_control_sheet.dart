import 'package:flutter/material.dart';

import '../../services/danmaku/dandanplay_client.dart';
import '../../services/danmaku/danmaku_matcher.dart';
import '../../services/danmaku/danmaku_search_controller.dart';

/// 弹幕弹窗（694 M3a，Flutter 壳）。
///
/// 全平台 Flutter UI 共用：**点击弹幕开关按钮弹出**（不搞长按快捷）。
/// 弹窗视觉主角是动效开关（胶囊滑轨 + 缓动滑钮 + 弹幕气泡图标）；
/// 开关能力全在弹窗内，入口按钮图标随开关状态变色（不点开也能看状态）。
///
/// 弹窗内含：动效开关 / 绑定状态行 / 搜索·换绑（同窗切搜索态）/
/// 弹幕设置入口。搜索、绑定、记忆写入全在 [DanmakuSearchController]，
/// 本壳只做输入输出。
class DanmakuControlSheet extends StatefulWidget {
  const DanmakuControlSheet({
    super.key,
    required this.controller,
    required this.danmakuOn,
    required this.onToggle,
    required this.onReload,
    required this.prefillKeyword,
    this.currentEpisodeNumber = 0,
    this.onOpenSettings,
  });

  /// 搜索/绑定核心（三壳共用）。
  final DanmakuSearchController controller;

  /// 进入弹窗时的开关状态（开关只从弹窗内切）。
  final bool danmakuOn;

  /// 切换弹幕开关（同步到播放页）。
  final VoidCallback onToggle;

  /// 绑定/解绑后触发弹幕重载。
  final VoidCallback onReload;

  /// 搜索关键词预填（cleanTitle 产物）。
  final String prefillKeyword;

  /// 当前集号（>0 时提供「只看第 N 集」过滤）。
  final int currentEpisodeNumber;

  /// 打开「设置 → 弹幕配置」。
  final VoidCallback? onOpenSettings;

  @override
  State<DanmakuControlSheet> createState() => _DanmakuControlSheetState();
}

class _DanmakuControlSheetState extends State<DanmakuControlSheet> {
  late bool _on = widget.danmakuOn;
  late final TextEditingController _keyword =
      TextEditingController(text: widget.prefillKeyword);
  bool _searchMode = false;
  bool _onlyCurrentEpisode = true;

  @override
  void dispose() {
    _keyword.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _on = !_on);
    widget.onToggle();
  }

  Future<void> _bind(MatchCandidate c) async {
    await widget.controller.bind(c);
    widget.onReload();
    if (mounted) setState(() => _searchMode = false);
  }

  Future<void> _unbind() async {
    await widget.controller.unbind();
    widget.onReload();
    setState(() {});
  }

  List<MatchCandidate> get _visibleResults {
    final n = widget.currentEpisodeNumber;
    if (!_onlyCurrentEpisode || n <= 0) return widget.controller.results;
    return [
      for (final c in widget.controller.results)
        if (DanmakuMatcher.parseEpisodeNumber(c.episodeTitle) == n) c,
    ];
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller.revision,
      builder: (context, _) {
        // 694：弹卡抬升到控制条之上（不盖进度条；116 与原生
        // PANEL_BOTTOM_OFFSET 同值）+ 整体限高可滚动（结果多）。
        final bottomReserve = 116 + MediaQuery.of(context).padding.bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: bottomReserve),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1E2126),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
              border: Border.all(color: Colors.white24),
            ),
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
            child: Material(
              type: MaterialType.transparency,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.6,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildHeader(context),
                      const SizedBox(height: 20),
                      _DanmakuSwitch(on: _on, onChanged: _toggle),
                      const SizedBox(height: 12),
                      Text(
                        _on
                            ? '已开启 · ${widget.controller.bindingLabel}'
                            : '已关闭',
                        style:
                            const TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                      const SizedBox(height: 16),
                      const Divider(height: 1, color: Colors.white24),
                      const SizedBox(height: 8),
                      if (_searchMode)
                        _buildSearchView(context)
                      else
                        _buildHomeView(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        const Text(
          '弹幕',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close, color: Colors.white54, size: 20),
        ),
      ],
    );
  }

  Widget _buildHomeView() {
    final controller = widget.controller;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          leading: const Icon(Icons.search, color: Colors.white70),
          title: const Text('搜索 / 换绑', style: TextStyle(color: Colors.white)),
          subtitle: Text(
            controller.bindingLabel,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => setState(() => _searchMode = true),
        ),
        if (controller.binding != null)
          ListTile(
            leading: const Icon(Icons.link_off, color: Colors.white70),
            title: const Text('解除绑定', style: TextStyle(color: Colors.white)),
            subtitle: const Text(
              '回到自动匹配',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            onTap: _unbind,
          ),
        if (widget.onOpenSettings != null)
          ListTile(
            leading: const Icon(Icons.settings, color: Colors.white70),
            title: const Text('弹幕设置', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.of(context).pop();
              widget.onOpenSettings!();
            },
          ),
      ],
    );
  }

  Widget _buildSearchView(BuildContext context) {
    final controller = widget.controller;
    final results = _visibleResults;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _keyword,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: '输入剧名搜索…',
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: Colors.white10,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  isDense: true,
                ),
                onSubmitted: (v) => controller.search(v),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed:
                  controller.searching ? null : () => controller.search(_keyword.text),
              child: controller.searching
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('搜索'),
            ),
          ],
        ),
        if (widget.currentEpisodeNumber > 0)
          CheckboxListTile(
            value: _onlyCurrentEpisode,
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(
              '只看第 ${widget.currentEpisodeNumber} 集',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            onChanged: (v) =>
                setState(() => _onlyCurrentEpisode = v ?? true),
          ),
        if (controller.error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              controller.error!,
              style: const TextStyle(color: Colors.orangeAccent, fontSize: 13),
            ),
          ),
        if (results.isNotEmpty)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: results.length,
              itemBuilder: (context, i) {
                final c = results[i];
                return ListTile(
                  dense: true,
                  title: Text(
                    c.animeTitle.isNotEmpty ? c.animeTitle : 'episodeId ${c.episodeId}',
                    style: const TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    c.episodeTitle,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  trailing: TextButton(
                    onPressed: () => _bind(c),
                    child: const Text('绑定'),
                  ),
                );
              },
            ),
          ),
        TextButton(
          onPressed: () => setState(() => _searchMode = false),
          child: const Text('返回'),
        ),
      ],
    );
  }
}

/// 弹幕动效开关（694 M3：弹窗视觉主角，三壳同款规格）。
///
/// 胶囊滑轨：开 = 主题色渐变 + 白色圆钮（内嵌弹幕气泡图标）；
/// 关 = 中性灰。切换 180ms 缓动滑移 + 滑轨颜色过渡。
class _DanmakuSwitch extends StatelessWidget {
  const _DanmakuSwitch({required this.on, required this.onChanged});

  final bool on;
  final VoidCallback onChanged;

  static const _accent = Color(0xFFFF8A3D);
  static const _accentDark = Color(0xFFE06A1B);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const Key('danmaku-switch'),
      toggled: on,
      label: '弹幕开关',
      child: GestureDetector(
        onTap: onChanged,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          width: 84,
          height: 44,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            gradient: on
                ? const LinearGradient(
                    colors: [_accent, _accentDark],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: on ? null : const Color(0xFF4A4F57),
            borderRadius: BorderRadius.circular(22),
            boxShadow: on
                ? [
                    BoxShadow(
                      color: _accent.withValues(alpha: 0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : const [],
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutBack,
            alignment: on ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Icon(
                Icons.chat_bubble,
                size: 18,
                color: on ? _accentDark : const Color(0xFF8A9099),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
