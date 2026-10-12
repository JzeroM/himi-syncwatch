import 'package:flutter/material.dart';

import 'package:himi_syncwatch/widgets/tv/tv_focusable.dart';

/// 播放页顶栏：返回 + 左上角影视信息 + 网速 + 解码胶囊 + 分享。
///
/// 纯参数 widget（不依赖 provider/状态），便于脱离 `mdk.Player` 单测
/// 标题格式化回显与网速显隐。渐变底与内边距沿用原 `_buildTopBar` 样式。
/// 锁按钮已移至画面左缘独立控件（`PlayerLockButton`）。
class PlayerTopBar extends StatelessWidget {
  const PlayerTopBar({
    super.key,
    required this.title,
    required this.networkSpeedText,
    required this.showDecodeButton,
    required this.decodeMenuOpen,
    required this.glassEnabled,
    required this.showVideoFitButton,
    required this.videoFitIcon,
    required this.videoFitLabel,
    required this.onCycleVideoFit,
    required this.showShare,
    required this.onBack,
    required this.onToggleDecode,
    required this.onShare,
    this.showSubtitleStyleButton = true,
    this.subtitleStyleMenuOpen = false,
    this.subtitleStyleFocusNode,
    this.onToggleSubtitleStyle,
    this.showSpeedButton = false,
    this.speedLabel = '1.0x',
    this.speedMenuOpen = false,
    this.speedButtonFocusNode,
    this.onToggleSpeed,
    this.showRotateButton = false,
    this.rotateButtonIcon = Icons.screen_rotation_alt,
    this.onRotate,
  });

  /// 左上角影视信息（电影名 / `剧名 – S01E02`）；空串不渲染。
  final String title;

  /// 网速回显（如 `12.34 Mbps`）；null = 设置关闭不渲染。
  final String? networkSpeedText;

  final bool showDecodeButton;
  final bool decodeMenuOpen;

  /// 液态玻璃开关（设置页）；false 时解码方块降级纯色平底。
  final bool glassEnabled;

  /// 画面比例按钮（解码控件右侧；仅本地单人 + 非 TV）。
  final bool showVideoFitButton;
  final IconData videoFitIcon;

  /// 当前比例模式名（自适应/裁剪/铺满/原始），作 tooltip。
  final String videoFitLabel;
  final VoidCallback onCycleVideoFit;

  final bool showShare;

  final VoidCallback onBack;
  final VoidCallback onToggleDecode;
  final VoidCallback onShare;

  /// 字幕样式按钮（网速显示与解码控件之间）：开关右侧选择器面板。
  final bool showSubtitleStyleButton;

  /// 样式面板展开态（描边高亮同解码胶囊）。
  final bool subtitleStyleMenuOpen;

  /// 按钮焦点（面板打开来源，关闭时归还；TV 遥控 OK 重开）。
  final FocusNode? subtitleStyleFocusNode;

  final VoidCallback? onToggleSubtitleStyle;

  /// 倍速按钮（仅手机本地单人；紧接网速右侧）。显示当前倍速标签，
  /// 点击开关右侧选择器面板；显隐与文字由外部状态决定。
  final bool showSpeedButton;
  final String speedLabel;

  /// 倍速面板展开态（描边高亮）。
  final bool speedMenuOpen;

  /// 倍速按钮焦点（面板打开来源，关闭时归还）。
  final FocusNode? speedButtonFocusNode;

  final VoidCallback? onToggleSpeed;

  /// 手动转屏按钮（仅手机；紧接画面比例右侧）。TV 全程横屏不显示。
  final bool showRotateButton;
  final IconData rotateButtonIcon;
  final VoidCallback? onRotate;

  /// 解码方块装饰：
  /// - 玻璃开：白 22%→10% 渐变 + 白 24% 细描边；展开态换 accent 1.5px
  ///   描边 + accent 外发光（不用实心底，顶栏不突兀）
  /// - 玻璃关（降级）：展开实心 accent / 收起白 15% 平底（旧观）
  static BoxDecoration _decodeChipDecoration({
    required bool open,
    required bool glass,
  }) {
    const accent = Color(0xFF6366F1);
    const radius = BorderRadius.all(Radius.circular(10));
    if (glass) {
      return BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0.22),
            Colors.white.withValues(alpha: 0.10),
          ],
        ),
        borderRadius: radius,
        border: Border.all(
          color: open ? accent : Colors.white.withValues(alpha: 0.24),
          width: open ? 1.5 : 0.8,
        ),
        boxShadow: open
            ? [
                BoxShadow(
                  color: accent.withValues(alpha: 0.40),
                  blurRadius: 8,
                ),
              ]
            : null,
      );
    }
    return BoxDecoration(
      color: open ? accent : Colors.white.withValues(alpha: 0.15),
      borderRadius: radius,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top,
        left: 12,
        right: 12,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.8),
          ],
        ),
      ),
      child: Row(
        children: [
          IconButton(
            key: const ValueKey('playerBackButton'),
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: onBack,
          ),
          if (title.isNotEmpty) ...[
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                title,
                key: const ValueKey('playerTitle'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ] else
            const Spacer(),
          if (networkSpeedText != null) ...[
            Text(
              networkSpeedText!,
              key: const ValueKey('playerNetworkSpeed'),
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(width: 8),
          ],
          // 倍速按钮（网速右侧，仅手机本地单人）：开关右侧选择器面板
          if (showSpeedButton) ...[
            TvFocusable(
              key: const ValueKey('playerTopSpeedButton'),
              focusNode: speedButtonFocusNode,
              radius: 10,
              onTap: onToggleSpeed,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.speed,
                      color: speedMenuOpen
                          ? const Color(0xFF6366F1)
                          : Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      speedLabel,
                      style: TextStyle(
                        color: speedMenuOpen
                            ? const Color(0xFF6366F1)
                            : Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          // 字幕样式按钮（网速与解码之间）：右侧选择器面板调大小/位置/延迟
          if (showSubtitleStyleButton) ...[
            if (networkSpeedText == null && !showSpeedButton)
              const SizedBox(width: 8),
            TvFocusable(
              key: const ValueKey('playerSubtitleStyleButton'),
              focusNode: subtitleStyleFocusNode,
              radius: 10,
              onTap: onToggleSubtitleStyle,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: _decodeChipDecoration(
                  open: subtitleStyleMenuOpen,
                  glass: glassEnabled,
                ),
                child: const Icon(Icons.tune, color: Colors.white, size: 18),
              ),
            ),
            if (showDecodeButton) const SizedBox(width: 8),
          ],
          // 解码模式按钮（TV 隐藏：解码模式仅走设置页切换）
          // 图标化玻璃方块：文字信息移入 DecodeModePanel 标题行
          if (showDecodeButton) ...[
            TvFocusable(
              key: const ValueKey('playerDecodeButton'),
              radius: 10,
              onTap: onToggleDecode,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: _decodeChipDecoration(
                  open: decodeMenuOpen,
                  glass: glassEnabled,
                ),
                child: const Icon(Icons.memory, color: Colors.white, size: 18),
              ),
            ),
          ],
          // 画面比例按钮（解码胶囊右侧；TV 隐藏）
          if (showVideoFitButton) ...[
            const SizedBox(width: 8),
            TvFocusable(
              radius: 12,
              onTap: onCycleVideoFit,
              child: Tooltip(
                message: videoFitLabel,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(videoFitIcon, color: Colors.white, size: 22),
                ),
              ),
            ),
          ],
          // 手动转屏按钮（画面比例右侧；仅手机，TV 全程横屏不显示）
          if (showRotateButton) ...[
            const SizedBox(width: 8),
            TvFocusable(
              key: const ValueKey('playerTopRotateButton'),
              radius: 12,
              onTap: onRotate,
              child: Tooltip(
                message: '旋转屏幕',
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(rotateButtonIcon, color: Colors.white, size: 22),
                ),
              ),
            ),
          ],
          if (showShare) ...[
            const SizedBox(width: 8),
            IconButton(
              key: const ValueKey('playerShareButton'),
              icon: const Icon(Icons.share, color: Colors.white),
              tooltip: '分享房间',
              onPressed: onShare,
            ),
          ],
        ],
      ),
    );
  }
}
