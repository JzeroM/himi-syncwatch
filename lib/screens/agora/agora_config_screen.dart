import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/models/agora_config_model.dart';
import 'package:himi_syncwatch/widgets/agora/agora_book_config_page.dart';
import 'package:himi_syncwatch/widgets/agora/agora_guide_book.dart';
import 'package:himi_syncwatch/providers/agora_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/shell/shell_nav_visibility.dart';
import 'package:himi_syncwatch/widgets/glass/glass_config.dart';
import 'package:himi_syncwatch/widgets/glass/glass_container.dart';
import 'package:himi_syncwatch/widgets/app_toast.dart';
import 'package:himi_syncwatch/utils/asset_image.dart';

/// 声网（Agora RTM）配置页（原侧边栏底部入口，现为独立标签页）。
class AgoraConfigScreen extends ConsumerStatefulWidget {
  const AgoraConfigScreen({super.key});

  @override
  ConsumerState<AgoraConfigScreen> createState() => _AgoraConfigScreenState();
}

class _AgoraConfigScreenState extends ConsumerState<AgoraConfigScreen> {
  late final TextEditingController _appIdController;
  late final TextEditingController _certController;

  /// 已配置时默认收起表单，通过状态卡「编辑」按钮展开。
  late bool _editing;

  /// 687：切走分支时**发重置信号**让书回到合上封面（v1.2.41 行为）。
  ///
  /// 【为什么不再用 epoch + ValueKey 重建】旧实现每次切走/切回都让
  /// `AgoraGuideBook` 的 key 变化 → Flutter 销毁旧 State、重建整棵
  /// 子树：封面 6 处 `BoxShadow`（blur 30/26/14）重新离屏渲染、4 页
  /// 内容全部重建、`TweenAnimationBuilder` 白跑 320ms 颜色动画。
  /// 安卓真机切到「声网」标签时明显卡一下，就是这么来的。
  ///
  /// 现在只发一个信号，书本 State 保留 → 零重建。
  final ValueNotifier<int> _bookReset = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    final config = ref.read(agoraConfigProvider);
    _appIdController = TextEditingController(text: config?.appId ?? '');
    _certController = TextEditingController(text: config?.appCertificate ?? '');
    _editing = config?.isConfigured != true;
    // 681：post-frame 预热 4 张截图——首次切到声网分支时不再同步解码，
    // 消除切标签的掉帧（原图分辨率解码 4 张约 20~80ms）。
    precacheAssetImagesAfterFrame(
      context,
      agoraGuideSteps.map((s) => s.image),
      displayWidth: 320, // 书本页宽量级；与渲染侧 LayoutBuilder 同一 cacheWidth 源
    );
  }

  @override
  void dispose() {
    _bookReset.dispose();
    _appIdController.dispose();
    _certController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final appId = _appIdController.text.trim();
    if (appId.isEmpty) {
      showAppToast(context, 'App ID 不能为空');
      return;
    }

    await ref.read(agoraConfigProvider.notifier).save(
          AgoraConfigModel(
            appId: appId,
            appCertificate: _certController.text.trim(),
          ),
        );
    if (!mounted) return;
    setState(() => _editing = false);
    showAppToast(context, '声网配置已保存');
  }

  Future<void> _clear() async {
    await ref.read(agoraConfigProvider.notifier).clear();
    _appIdController.clear();
    _certController.clear();
    if (!mounted) return;
    setState(() => _editing = true);
    showAppToast(context, '声网配置已清空');
  }

  @override
  Widget build(BuildContext context) {
    final agoraConfig = ref.watch(agoraConfigProvider);
    final configured = agoraConfig?.isConfigured == true;
    // 防御性：声网页在 TV 顶栏被隐藏（当前不可达），但表单字段仍
    // 统一屏蔽焦点（遥控器无输入法）
    final tvMode = ref.watch(settingsProvider.select((s) => s.tvMode));
    final themeColor = ref.watch(settingsProvider.select((s) => s.themeColor));

    // 切 tab 离开本页（v1.1.243）：未点保存的输入一律丢弃，
    // 输入框还原为已保存值；已配置时收起表单。
    ref.listen(
      shellBranchEpochProvider.select((m) => m[3] ?? 0),
      (previous, next) {
        if (previous == next || !mounted) return;
        final saved = ref.read(agoraConfigProvider);
        _appIdController.text = saved?.appId ?? '';
        _certController.text = saved?.appCertificate ?? '';
        setState(() {
          _editing = saved?.isConfigured != true;
        });
        // 687：只发重置信号，不换 key（不重建书本）。
        _bookReset.value++;
      },
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('声网配置'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: const GlassBackdrop(),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          16,
          GlassConfig.topInsetOf(context),
          16,
          GlassConfig.bottomReserveOf(context),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540),
            child: AgoraGuideBook(
              resetSignal: _bookReset,
              themeColor: themeColor == null ? null : Color(themeColor),
              onImageTap: (image) => _showFullImage(context, image),
              extraPageBuilder: (context, palette, index, total) {
                return AgoraBookConfigPage(
                  index: index,
                  total: total,
                  palette: palette,
                  configured: configured,
                  editing: _editing || !configured,
                  tvMode: tvMode,
                  appId: agoraConfig?.appId ?? '',
                  appIdController: _appIdController,
                  certController: _certController,
                  onEdit: () => setState(() => _editing = true),
                  onCancel: configured
                      ? () {
                          final saved = ref.read(agoraConfigProvider);
                          _appIdController.text = saved?.appId ?? '';
                          _certController.text = saved?.appCertificate ?? '';
                          setState(() => _editing = false);
                        }
                      : null,
                  onSave: _save,
                  onClear: _clear,
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  void _showFullImage(BuildContext context, String imagePath) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: EdgeInsets.zero,
        backgroundColor: Colors.black,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 5.0,
                child: GestureDetector(
                  onTap: () => Navigator.pop(ctx),
                  child: Center(
                    child: assetImage(
                      context,
                      imagePath,
                      // 681：全屏查看用**全屏宽**解码（不复用书本宽度，
                      // 否则放大后模糊）。
                      displayWidth: MediaQuery.sizeOf(context).width,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Center(
                        child: Text('图片加载失败',
                            style: TextStyle(color: Colors.white)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('关闭'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
