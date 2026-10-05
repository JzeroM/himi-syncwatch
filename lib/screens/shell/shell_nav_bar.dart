import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/widgets/glass/blob_lens.dart';
import 'package:himi_syncwatch/widgets/glass/glass_container.dart';
import 'package:himi_syncwatch/widgets/glass/glass_tuning.dart';
import 'package:himi_syncwatch/widgets/tv/tv_focusable.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as lg;

/// 选中态图标/文字主色（柔和薄荷青，仅跟随水珠所在格的图标，水珠本体为透明玻璃）。
const Color kNavBlobColor = Color(0xFF86E3D6);

/// 四标签底部导航（含胶囊玻璃底与移动态镜片水珠）。
///
/// - 胶囊玻璃 [GlassContainer] 与全部 icon+label 图标包在同一个
///   `RepaintBoundary`（[_navCaptureKey]）内作镜片采样纹理；
///   水珠镜片在边界之外的顶层兄弟 → 溢出胶囊不被裁剪、图标被真实
///   折射形变、镜片不自采样（无反馈环），镜片内 [IgnorePointer]
///   放行点击给下层图标
/// - 每格 icon+label 组在胶囊内上下左右严格居中，四格对齐
/// - 单个水珠指示器：点击平滑移形；横向滑动或长按均可跟手拖动，
///   拖动中水珠所在格图标实时点亮青色，松手按落点切换
class ShellNavBar extends ConsumerStatefulWidget {
  const ShellNavBar({
    super.key,
    required this.currentIndex,
    required this.onSelect,
  });

  final int currentIndex;
  final ValueChanged<int> onSelect;

  @override
  ConsumerState<ShellNavBar> createState() => _ShellNavBarState();
}

class _ShellNavBarState extends ConsumerState<ShellNavBar>
    with SingleTickerProviderStateMixin {
  static const int _tabCount = 4;
  static const double _navHeight = 60;
  static const double _blobHeight = 50;

  static const List<String> _labels = ['首页', 'Emby服务器', '声网配置', '设置'];
  static const List<IconData> _icons = [
    Icons.home_outlined,
    Icons.dns_outlined,
    Icons.key_outlined,
    Icons.settings_outlined,
  ];
  static const List<IconData> _selectedIcons = [
    Icons.home,
    Icons.dns,
    Icons.key,
    Icons.settings,
  ];

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  double _totalWidth = 0;
  double _navGlobalX = 0;

  /// 水珠中心（相对导航宽 0..1）。
  double _blobT = 0;

  /// 导航捕获边界钥匙（胶囊+图标）：镜片 [LiquidBlobLens.backgroundKey]
  /// 采样此 RepaintBoundary → 水珠划过时图标被物理折射形变。
  final GlobalKey _navCaptureKey = GlobalKey(debugLabel: 'navCapture');

  /// 静止水珠宽度占单格宽的比例（圆润度：~1.37:1 不显扁）。
  static const double _restWidthRatio = 0.75;

  /// 移动态整体放大倍数（宽高同倍，与镜片外扩 50→72 = ×1.44 对齐，
  /// 纯整体放大、不拉长不压扁）。
  static const double _activeScale = 1.44;

  double _fromT = 0;
  double _toT = 0;
  bool _dragging = false;

  /// 抓取偏移（水珠中心 - 手指 x，相对导航左沿）。
  /// 手指落在当前水珠范围内时保持相对位置跟手，落在别格时吸附到手指。
  double _grabOffset = 0;

  /// 指示器果冻形变速度（包内坐标系：对齐值 -1..1 的每秒变化量，
  /// 喂给 [LiquidBlobLens.velocity] 驱动 jelly squash）。
  double _blobVelocity = 0;

  /// 速度采样时钟与上一帧状态（单调时钟，dt 异常时归零）。
  final Stopwatch _velClock = Stopwatch()..start();
  int _velLastUs = 0;
  double _velLastT = 0;

  static double _centerT(int index) => (index + 0.5) / _tabCount;

  /// 视觉激活格：以水珠中心所在格为准（拖动/飞行中实时跟随）。
  int get _activeIndex => (_blobT * _tabCount).floor().clamp(0, _tabCount - 1);

  @override
  void initState() {
    super.initState();
    _blobT = _centerT(widget.currentIndex);
    _velLastT = _blobT;
    _velLastUs = _velClock.elapsedMicroseconds;
    _controller.addListener(_onTick);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(ShellNavBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex != widget.currentIndex &&
        !_dragging &&
        !_controller.isAnimating) {
      _animateTo(widget.currentIndex);
    }
  }

  void _onTick() {
    if (!mounted) return;
    final raw = _controller.value;
    final p = Curves.easeOutBack.transform(raw);
    setState(() {
      _blobT = _fromT + (_toT - _fromT) * p;
      _trackVelocity(_blobT);
    });
  }

  /// 跟踪水珠速度并换算成包内 jelly 坐标系（对齐值 -1..1 的每秒变化量）。
  ///
  /// _blobT 0..1 线性映射到 -1..1 故乘 2；dt 过短保留上一采样、
  /// 过长（首帧/后台恢复）视为静止归零，幅度钳制避免测试环境下的
  /// 墙钟极小间隔产生爆炸值。
  void _trackVelocity(double newT) {
    final nowUs = _velClock.elapsedMicroseconds;
    final dt = (nowUs - _velLastUs) / 1e6;
    if (dt <= 0) return;
    if (dt >= 0.25) {
      _blobVelocity = 0;
    } else {
      _blobVelocity = ((newT - _velLastT) * 2 / dt).clamp(-8.0, 8.0);
    }
    _velLastUs = nowUs;
    _velLastT = newT;
  }

  void _animateTo(int index) {
    _fromT = _blobT;
    _toT = _centerT(index);
    _controller.forward(from: 0);
  }

  void _select(int index) {
    if (index != widget.currentIndex) widget.onSelect(index);
    _animateTo(index);
  }

  double _relativeX(double globalX) {
    if (_totalWidth <= 0) return 0;
    return (globalX - _navGlobalX).clamp(0.0, _totalWidth);
  }

  void _captureNavOrigin() {
    final box = context.findRenderObject();
    if (box is RenderBox && box.attached) {
      _navGlobalX = box.localToGlobal(Offset.zero).dx;
    }
  }

  /// 进入拖动态（横向滑动或长按触发共用）。
  void _beginDrag(double globalX) {
    // 测试环境无振动通道实现，忽略失败
    HapticFeedback.mediumImpact().ignore();
    _captureNavOrigin();
    _controller.stop();
    final x = _relativeX(globalX);
    final center = _blobT * _totalWidth;
    // 手指落在当前格内即相对跟手（与旧版静止半宽一致），别格则吸附手指
    final halfW = (_totalWidth / _tabCount) / 2;
    _grabOffset = (x - center).abs() <= halfW ? center - x : 0;
    setState(() => _dragging = true);
    _applyDrag(x);
  }

  void _moveDrag(double globalX) {
    if (!_dragging) return;
    _applyDrag(_relativeX(globalX));
  }

  void _applyDrag(double x) {
    if (_totalWidth <= 0) return;
    final t = ((x + _grabOffset) / _totalWidth).clamp(0.0, 1.0);
    setState(() {
      _blobT = t;
      _trackVelocity(t);
    });
  }

  /// 松手：按手指落点格切换（落点才切，拖动中途不回调）。
  void _endDrag(double globalX) {
    if (!_dragging) return;
    setState(() => _dragging = false);
    if (_totalWidth <= 0) return;
    final t = (_relativeX(globalX) / _totalWidth).clamp(0.0, 1.0);
    final index = (t * _tabCount).floor().clamp(0, _tabCount - 1);
    _select(index);
  }

  /// 拖动被系统/父级手势打断：结束拖动态并回到当前格。
  void _cancelDrag() {
    if (!_dragging) return;
    setState(() => _dragging = false);
    _animateTo(widget.currentIndex);
  }

  /// 水珠本体（返回值已自带定位，直接作为导航 Stack 的子级）。
  ///
  /// `glassUi` 开启时经 [lg.SpringBuilder] 弹簧驱动 [LiquidBlobLens]：
  /// - 静止：宽 = 格宽 × [_restWidthRatio]（~1.37:1 圆润不显扁），
  ///   activity=0 扁平实心胶囊（无明显边框、镜片不挂载、零 shader 开销）；
  /// - 拖动/点击飞行 activity→1：宽高同弹簧放大 ×[_activeScale]
  ///   （纯整体放大，不拉长不压扁），真折射镜片挂载（`blur: 0.01`
  ///   打开 Skia 背景捕获），矩形上下各外扩 6px 超出胶囊；采样
  ///   [_navCaptureKey] 导航边界（胶囊+图标）→ 图标被物理折射弯折，
  ///   沿边 28px 光学带（平方衰减：贴边一圈明显弯折、中带干净）
  ///   出纯物理色散彩虹（vendored 包 [PATCH himi] ×4.0，无自发光色环），
  ///   折射只在移动过程出现，jelly 果冻形变吃 [_blobVelocity]；
  /// - `settings.thickness/saturation/lightIntensity` 取设置滑杆实时值，
  ///   `ambientRim/glowIntensity/ambientStrength/edgeAbsorption` 出
  ///   柔和中性微边与结构亮圈（补偿包内标准路径归一化，位置无关可见）；
  ///   `lightAngle` 随水珠位置扫动 → 亮瓣随移动"流动"；
  /// - 镜片作 [_navCaptureKey] 边界的兄弟层渲染（自身不在采样纹理内，
  ///   无自采样反馈），溢出不被任何裁剪层吃掉，[IgnorePointer]
  ///   放行点击给下层图标。
  /// `glassUi` 关闭时降级为原半透明白色装饰（navBlob key 与装饰参数不变）。
  Widget _buildBlob(double left, double width) {
    final glassEnabled = ref.watch(settingsProvider.select((s) => s.glassUi));
    final tuning = ref.watch(glassTuningProvider);

    if (!glassEnabled) {
      return Positioned(
        left: left,
        top: (_navHeight - _blobHeight) / 2,
        width: width,
        height: _blobHeight,
        child: DecoratedBox(
          key: const ValueKey('navBlob'),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.10),
            borderRadius: BorderRadius.all(Radius.circular(_blobHeight / 2)),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.42),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.16),
                blurRadius: 14,
              ),
            ],
          ),
        ),
      );
    }

    // 活动量 0..1：静止 0（扁平实心胶囊、无镜片、零 shader 开销），
    // 拖动/点击飞行中 1（镜片淡入 + 整体放大 + 背景胶囊淡出）。
    final activity = (_dragging || _controller.isAnimating) ? 1.0 : 0.0;

    final settings = lg.AnimatedGlassIndicator.baseIndicatorSettings.copyWith(
      glassColor: Colors.white.withValues(alpha: 0.14),
      thickness: tuning.thickness ?? glassDefault('glassThickness'),
      saturation: tuning.saturation ?? glassDefault('glassSaturation'),
      // 色散固定加强（忽略滑杆）：配合 vendored shader 真色散补丁
      //（×4.0）在边缘出 ~2px/侧 RGB 彩边（纯物理、无自发光环）
      chromaticAberration: 0.5,
      lightIntensity:
          tuning.lightIntensity ?? glassDefault('glassLightIntensity'),
      // Skia 捕获钥匙：GlassEffect 捕获门槛要求 blur > 0（0.01 无感）
      blur: 0.01,
      // 结构参数（输入值补偿包内标准路径归一化）：
      // ambientRim 驱动中性白 rim（×0.7 归一化、×10 亮度）→ 0.18 出
      // 柔和灰白微边而非硬边框；
      // glow/ambient 降低白色菲涅尔与内壁提亮 → 边框感弱化（设备反馈）；
      // edgeAbsorption 收低 → 边缘暗带更淡。
      ambientRim: 0.18,
      glowIntensity: 1.2,
      ambientStrength: 0.4,
      edgeAbsorption: 0.10,
      // 光源相位随水珠位置扫动：key/kick 亮瓣绕环流动
      lightAngle: math.pi / 2 + (_blobT - 0.5) * math.pi,
    );

    return lg.SpringBuilder(
      spring: lg.GlassSpring.snappy(
        duration: const Duration(milliseconds: 300),
      ),
      value: activity,
      builder: (context, value, child) {
        // 宽高同倍整体放大（宽与镜片外扩高度同比例），中心保持不动
        final scale = 1 + (_activeScale - 1) * value;
        final w = width * scale;
        return LiquidBlobLens(
          key: const ValueKey('navBlob'),
          left: left + (width - w) / 2,
          width: w,
          activity: value,
          velocity: _blobVelocity,
          settings: settings,
          pillColor: Colors.white.withValues(alpha: 0.10),
          backgroundKey: _navCaptureKey,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _totalWidth = constraints.maxWidth;
        final tabW = _totalWidth / _tabCount;
        final restWidth = (tabW * _restWidthRatio).clamp(0.0, _totalWidth);
        final restLeft = _blobT * _totalWidth - restWidth / 2;

        return SizedBox(
          height: _navHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // 捕获边界：胶囊 + 导航图标（GlobalKey 供镜片 backgroundKey
              // 采样 → 水珠划过时图标被物理折射形变）。水珠自身在边界
              // 之外作兄弟层绘制，不会自采样产生反馈环。
              Positioned.fill(
                child: RepaintBoundary(
                  key: _navCaptureKey,
                  child: Stack(
                    children: [
                      // 胶囊玻璃底：水珠镜片溢出其外不被裁剪
                      Positioned.fill(
                        child: GlassContainer(
                          borderRadius:
                              const BorderRadius.all(Radius.circular(28)),
                          padding: EdgeInsets.zero,
                          child: const SizedBox.expand(),
                        ),
                      ),
                      Positioned.fill(
                        child: Row(
                          children: List.generate(_tabCount, (i) {
                            final selected = i == _activeIndex;
                            final color =
                                selected ? kNavBlobColor : Colors.white70;
                            return Expanded(
                              child: TvFocusable(
                                onTap: () => _select(i),
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onHorizontalDragStart: (d) =>
                                      _beginDrag(d.globalPosition.dx),
                                  onHorizontalDragUpdate: (d) =>
                                      _moveDrag(d.globalPosition.dx),
                                  onHorizontalDragEnd: (d) =>
                                      _endDrag(d.globalPosition.dx),
                                  onHorizontalDragCancel: _cancelDrag,
                                  onLongPressStart: (d) =>
                                      _beginDrag(d.globalPosition.dx),
                                  onLongPressMoveUpdate: (d) =>
                                      _moveDrag(d.globalPosition.dx),
                                  onLongPressEnd: (d) =>
                                      _endDrag(d.globalPosition.dx),
                                  child: SizedBox(
                                    height: _navHeight,
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          selected
                                              ? _selectedIcons[i]
                                              : _icons[i],
                                          size: 24,
                                          color: color,
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          _labels[i],
                                          textAlign: TextAlign.center,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: color,
                                            fontWeight: selected
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // 水珠镜片：边界之外的顶层兄弟（IgnorePointer 在镜片内）
              _buildBlob(restLeft, restWidth),
            ],
          ),
        );
      },
    );
  }
}
