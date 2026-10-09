import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/models/agora_config_model.dart';
import 'package:himi_syncwatch/widgets/tv/tv_exclude_editable.dart';
import 'package:himi_syncwatch/widgets/tv/tv_focusable.dart';
import 'package:himi_syncwatch/providers/agora_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/widgets/glass/glass_config.dart';
import 'package:himi_syncwatch/widgets/glass/glass_container.dart';
import 'package:himi_syncwatch/widgets/app_toast.dart';

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

  @override
  void initState() {
    super.initState();
    final config = ref.read(agoraConfigProvider);
    _appIdController = TextEditingController(text: config?.appId ?? '');
    _certController = TextEditingController(text: config?.appCertificate ?? '');
    _editing = config?.isConfigured != true;
  }

  @override
  void dispose() {
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

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('声网配置'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: const GlassBackdrop(),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: '配置说明',
            onPressed: () => _showAgoraGuide(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          16,
          GlassConfig.topInsetOf(context),
          16,
          GlassConfig.bottomReserveOf(context),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StatusCard(
              configured: configured,
              appId: agoraConfig?.appId ?? '',
              onEdit: configured ? () => setState(() => _editing = true) : null,
            ),
            const SizedBox(height: 20),
            if (_editing || !configured) ...[
              const Text(
                'App ID',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              tvExcludeEditable(
                tvMode: tvMode,
                child: TextField(
                  controller: _appIdController,
                  decoration: const InputDecoration(
                    hintText: '声网 App ID',
                    prefixIcon: Icon(Icons.vpn_key),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'App Certificate',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              tvExcludeEditable(
                tvMode: tvMode,
                child: TextField(
                  controller: _certController,
                  decoration: const InputDecoration(
                    hintText: '声网 App Certificate',
                    prefixIcon: Icon(Icons.lock),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '开房 / 加入房间需要声网 RTM 凭证，填写后点击保存。',
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 44,
                child: FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.save, size: 18),
                  label: const Text('保存'),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showAgoraGuide(context),
                    icon: const Icon(Icons.menu_book_outlined, size: 18),
                    label: const Text('配置说明'),
                  ),
                ),
                if (configured) ...[
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: _clear,
                    child:
                        const Text('清空', style: TextStyle(color: Colors.red)),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showAgoraGuide(BuildContext context) {
    final pageController = PageController();
    var currentPage = 0;

    final steps = [
      _AgoraGuideStep(
        title: '注册登录并创建通用项目',
        image: 'assets/images/agora_step1.png',
        description: '访问 shengwang.cn 注册并登录\n'
            '创建项目时选择「通用项目」',
      ),
      _AgoraGuideStep(
        title: '开通体验版套餐包',
        image: 'assets/images/agora_step2.png',
        description: '套餐包 → RTM\n'
            '选择「体验版」（免费）',
      ),
      _AgoraGuideStep(
        title: '开启 Presence 和 Storage',
        image: 'assets/images/agora_step3.png',
        description: '全部产品 → 实时消息 RTM → 基础配置\n'
            '启用「出席通知 (Presence)」\n'
            '启用「状态同步 (Storage)」\n'
            '数据存储区域选「中国」',
      ),
      _AgoraGuideStep(
        title: '获取 APP ID 和证书',
        image: 'assets/images/agora_step4.png',
        description: '项目总览页 → 复制 APP ID\n'
            '展开查看主要证书 → 复制 APP Certificate\n'
            '填入输入框 → 点击保存',
      ),
    ];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          content: SizedBox(
            width: 360,
            height: 420,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(steps.length, (i) {
                    return Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i == currentPage
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey[600],
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: PageView.builder(
                    controller: pageController,
                    itemCount: steps.length,
                    onPageChanged: (i) {
                      currentPage = i;
                      setDialogState(() {});
                    },
                    itemBuilder: (ctx, i) {
                      final step = steps[i];
                      return SingleChildScrollView(
                        child: Column(
                          children: [
                            Text(
                              '步骤 ${i + 1}: ${step.title}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            TvFocusable(
                              onTap: () => _showFullImage(context, step.image),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.asset(
                                  step.image,
                                  fit: BoxFit.contain,
                                  height: 220,
                                  errorBuilder: (_, __, ___) => Container(
                                    height: 220,
                                    decoration: BoxDecoration(
                                      color: Colors.grey[800],
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Center(
                                      child: Text(
                                        '请将截图放到:\n${step.image}',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: Colors.grey[400],
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '点击放大',
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey[400]),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              step.description,
                              style: const TextStyle(fontSize: 13, height: 1.5),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('关闭'),
                    ),
                    FilledButton(
                      onPressed: currentPage < steps.length - 1
                          ? () {
                              pageController.nextPage(
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeInOut,
                              );
                            }
                          : () => Navigator.pop(ctx),
                      child:
                          Text(currentPage < steps.length - 1 ? '下一步' : '完成'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
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
                    child: Image.asset(
                      imagePath,
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

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.configured,
    required this.appId,
    this.onEdit,
  });

  final bool configured;
  final String appId;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final color = configured ? Colors.green : Colors.orange;
    return GlassContainer(
      borderRadius: BorderRadius.circular(16),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(
            configured ? Icons.check_circle : Icons.info_outline,
            color: color,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  configured ? '已配置' : '未配置',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  configured
                      ? 'App ID: ${appId.length > 8 ? '${appId.substring(0, 8)}...' : appId}'
                      : '填写 App ID 后即可开房与加入房间',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          if (onEdit != null)
            IconButton(
              key: const ValueKey('agoraEditButton'),
              icon: const Icon(Icons.edit_outlined, size: 20),
              tooltip: '编辑',
              onPressed: onEdit,
            ),
        ],
      ),
    );
  }
}

class _AgoraGuideStep {
  final String title;
  final String image;
  final String description;
  const _AgoraGuideStep({
    required this.title,
    required this.image,
    required this.description,
  });
}
