#ifndef MPV_WINDOW_H
#define MPV_WINDOW_H

#include <QMap>
#include <QObject>
#include <QRect>
#include <QString>
#include <QUrl>
#include <QVariantList>
#include <QWindow>

#ifndef NOMINMAX
#define NOMINMAX
#endif
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif

#include <windows.h>

struct mpv_handle;
class QTimer;

/// 656：mpv 直出窗口。
///
/// 【为什么是原生 HWND 而不是画进 QML】libmpv 的 render API 只有 OpenGL
/// 与软件后端，没有 D3D11。把视频画进 QML 就得走 OpenGL FBO → mpv 先把
/// 画面转成 SDR RGBA 再交给 Qt → **HDR 直出必然丢失**。
///
/// 所以：mpv 自己拥有一个 HWND（`wid`），`vo=gpu-next` +
/// `d3d11-output-mode=window` 直出到 DWM，HDR 由 mpv 直接和显示器协商。
/// QML 只负责控件层（独立于视频像素路径）。
///
/// 【原生子窗口会盖住 QML】Win32 硬规则。所以视频子窗口高度要减去
/// 顶栏/底栏的高度，把控件区域让出来（`setOverlayInsets`）。
class MpvWindow : public QObject {
    Q_OBJECT

public:
    explicit MpvWindow(QObject* parent = nullptr);
    ~MpvWindow() override;

    /// 绑定 Qt 窗口并创建 mpv 会话。
    bool attach(QWindow* host, bool hdr, bool hlg);

    /// 加载媒体。`headers` 用于 Emby 鉴权（拼进 `http-header-fields`）。
    void load(const QString& url, const QMap<QString, QString>& headers = {});

    /// 680：卸载当前媒体（删除「正在播放的资源」时调用）。
    ///
    /// 语义对齐 Dart 侧 `unloadMedia()`：`stop` 结束 playlist、释放解码器，
    /// 进度/时长归零，弹幕轨清空。只 pause 会让画面停在最后一帧
    ///（真机回归「删了但还在播」）。
    void stopPlayback();

    // 664：以下控件操作暴露给 QML 直驱（控件本地化）——Flutter 侧
    // 无人应答（播放页已回详情页）时控件依然可用；QML 同时把命令
    // 发给 Flutter 做记账（弹幕同步等），两边都写幂等无副作用。
    Q_INVOKABLE void setPaused(bool paused);
    Q_INVOKABLE void togglePause();
    Q_INVOKABLE void setVolume(double volume);   ///< 0.0 ~ 1.0
    Q_INVOKABLE void setSpeed(double speed);
    Q_INVOKABLE void seekTo(qint64 positionMs);

    /// 按序号选轨（type: "audio"/"subtitle"；index 从 0 起；-1 = 关闭）。
    /// 664：序号 = NativePlayerState 轨道列表里的序号（Emby id-1），
    /// 内部按 `track-list` 的顺序映射到 mpv 轨道 id。
    Q_INVOKABLE void selectTrack(const QString& type, int index);

    /// 通用属性透传（HDR 切换、字幕延迟等场景）。
    void setProperty(const QString& name, const QString& value);

    /// 给 QML 控件让出的高度（顶栏 + 底栏）。视频子窗口会相应收窄。
    void setOverlayInsets(int top, int bottom);

    // 【668】挖孔机制已退役：控件层移到**逐像素透明悬浮窗**（顶层窗口
    // 永远盖住子窗口 = 真合成），视频满铺直出、玻璃任意半透明、零黑底。

    /// 切换宿主窗口全屏（控件在悬浮层，全屏对象是视频宿主）。
    Q_INVOKABLE void toggleHostFullscreen();
    Q_INVOKABLE bool isHostFullscreen() const;

    /// 677：全屏态提升为 **Q_PROPERTY**（按钮图标双向切换的依据）。
    ///
    /// 旧实现只在 QML 里每次调 `isHostFullscreen()`——属性绑定不会因
    /// 窗口状态变化重新求值，全屏后图标仍是「全屏」而不是「退出全屏」。
    Q_PROPERTY(bool hostFullscreen READ isHostFullscreen NOTIFY
                   hostFullscreenChanged)

    /// 677：显式设置全屏态（房间并排的摆位命令也走这里）。
    Q_INVOKABLE void setHostFullscreen(bool fullscreen);

    /// 677：房间并排矩形（由 Dart 下发）。
    ///
    /// 【为什么 Qt 要记】`showNormal()` 恢复的是 Qt 内部记忆的
    /// `normalGeometry`——房间并排是外部改的几何，Qt 并不知道，
    /// 退全屏后会落回上次的位置（与 Flutter 面板重叠/错位）。
    /// 记住并排矩形后，退全屏**显式** `setGeometry` 回去。
    ///
    /// 全屏中收到**不同**矩形 → 自动退全屏再应用（用户明确要求）；
    /// 相同则忽略（防面板刷新重发导致误退全屏）。
    Q_INVOKABLE void setWindowRect(int x, int y, int w, int h);

    /// 677：房间并排跟随开关。开启后本窗口自动占满「Flutter 主窗左侧
    /// 剩余区域」，随 Flutter 窗口拖动/缩放实时跟随（50ms 节拍）。
    Q_INVOKABLE void setFollowParent(bool enabled);

    /// 677：按 `QScreen::availableGeometry()` 计算并排矩形并回传
    /// （`splitLayout` 帧）。Qt 的屏幕信息是权威值（多屏/DPI），
    /// Dart 侧 `window_manager` 拿不到工作区。
    void requestSplitLayout(int panelWidth, int minVideoWidth);

    /// 677：把本窗口拉到最前（Dart 取消退房/点面板时用）。
    Q_INVOKABLE void raiseToFront();

    /// 683：房间并排时与 Flutter 面板窗**保持同一层**（不是置顶）。
    ///
    /// 【需求澄清】用户要的是「两窗在 z-order 里始终相邻、不被拆散」，
    /// **不是**「压在所有软件之上」——682 误实现成了 `HWND_TOPMOST`，
    /// 结果房间开着时把别的软件全盖住，用户明确否掉了。
    ///
    /// 现在改为「联动抬升」：
    ///   - 本窗被激活 → `HWND_TOP` 抬到非置顶层最前，并通知 Dart 把面板
    ///     一起抬上来
    ///   - 面板被激活 → Dart 发 `raise` 让本窗跟着抬
    ///   - 切到别的软件 → 两窗一起被正常盖住（没有任何置顶属性）
    ///
    /// 结构上仍然保证「要么都在上面、要么都被盖住」——因为两窗永远一起动。
    Q_INVOKABLE void raiseTogether();

    /// 682→683：置顶开关（已废弃，保留为 no-op 兼容旧 IPC）。
    ///
    /// 早期房间实现用 `HWND_TOPMOST` 把两窗压在所有软件之上；用户要求
    /// 改为「同层但不置顶」，此接口不再改变窗口层级。
    Q_INVOKABLE void setTopmost(bool topmost);

    /// 678：临时显示/隐藏宿主窗（房间弹窗期间让位给 Flutter 主窗）。
    ///
    /// 【为什么不用最小化】最小化后 mpv 会停渲染，恢复时要重新起播
    ///（黑屏一瞬）；`hide`/`show` 保住解码状态，弹窗关掉即恢复画面。
    Q_INVOKABLE void setWindowVisible(bool visible);

    /// 679：无边框窗口的系统拖动（顶栏拖拽区调用）。
    ///
    /// 【为什么需要】`Qt.FramelessWindowHint` 去掉了系统标题栏，窗口不再
    /// 可拖。Qt 6 的 `QWindow::startSystemMove()` 交给系统做原生拖动
    ///（带 DWM 吸附/半屏贴靠），比自己算 mouseMove 更稳。
    Q_INVOKABLE void startSystemMove();

    /// 679：无边框窗口的边缘拉伸。
    ///
    /// [edges] 位掩码：1=左 2=上 4=右 8=下（与 `Qt::Edges` 数值一致，
    /// QML 侧用数字传，避免引入 Qt::Edge 枚举绑定）。
    Q_INVOKABLE void startSystemResize(int edges);

    /// 677：触发 Escape 语义（main.cpp 的事件过滤器调用）。
    ///
    /// 信号不能从类外 emit（虽然 Qt 的 `signals` 是 public，但语义上
    /// 应由类自己发）——这里提供显式入口。
    void notifyEscape() { emit escapePressed(); }

    /// 677：父进程（Flutter）pid —— 房间并排跟随用它定位主窗。
    /// 由 main.cpp 从 `--parent-pid` 注入。
    void setParentPid(qint64 pid) { parentPid_ = pid; }

    /// 677：供 main.cpp 的 50ms 节拍调用（`followParentOnce` 是私有实现）。
    void followParentOncePublic() { followParentOnce(); }

    /// 【669：HDR 晚绑定】媒体信息解析完才决定 HDR/HLG 档位，而进程
    /// 为「起播直接弹窗」早已拉起（Flutter 侧 _ensureQtPlayerProcess）。
    /// 流程：先 setHdrMode 再 load，mpv 首帧前应用与启动参数等效。
    Q_INVOKABLE void setHdrMode(bool hdr, bool hlg);

    /// 【672】活跃轨道在同类型组内的序号（0 起；无 = -1）——面板 id =
    /// 序号 + 1（与 Flutter「Emby 索引 + 1」约定一致），供选中态回填。
    Q_INVOKABLE int activeTrackIndex(const QString& type);

    /// 通用 mpv 命令透传（sub-add / sub-remove / screenshot-to-file …）。
    Q_INVOKABLE bool command(const QStringList& args);

    /// 【665：弹幕 ASS 旁路】把弹幕生成的 ASS 内容写临时文件并挂成
    /// **次字幕轨**（`secondary-sid`）——mpv 0.37+ 支持双字幕轨，主字幕
    /// 与弹幕可同时渲染（wid 直出架构下 QML 画不进视频，ASS 是唯一
    /// 浮绘通道）。空文本 = 移除弹幕轨。
    Q_INVOKABLE void setDanmakuAss(const QString& assText);

    /// 实际输出是否为 HDR（`video-out-params` 的 gamma/primaries 判定）。
    bool hdrOutput() const;
    QString videoOutputActual() const;

signals:
    /// 播放位置变化（供 QML 进度条绑定，约 20Hz）。
    void positionChanged(qint64 positionMs, qint64 durationMs);

    /// 暂停状态变化（用户按空格 / 点了按钮）。
    void pausedChanged(bool paused);

    /// 播放结束。
    void playbackEnded();

    /// 首帧就绪（用于隐藏加载指示器）。
    void firstFrameRendered();

    /// 677：全屏态变化（Q_PROPERTY 通知 + QML 图标绑定）。
    void hostFullscreenChanged();

    /// 677：并排布局计算结果（`requestSplitLayout` → main.cpp → IPC）。
    void splitLayoutReady(int panelX, int panelY, int panelW, int panelH,
                          int videoX, int videoY, int videoW, int videoH,
                          int maxPanelW, int maxPanelH, bool ok);

    /// 679：**用户**拖动/缩放窗口后回传新矩形（`windowMoved` 帧）。
    ///
    /// 【只回传用户操作】程序性 `setGeometry`（跟随时）会置
    /// `applyingProgrammaticGeometry_` 标志，那条路径**不发**本信号——
    /// 否则「A 跟随 B → B 收到通知又跟随 A」形成死循环。
    void userWindowMoved(int x, int y, int w, int h);

    /// 683：Qt 窗被抬到前面 → Dart 把 Flutter 面板窗也抬上来（两窗同层）。
    ///
    /// 【为什么不直接置顶】用户明确要求「两窗同一层，但不要固定最上层」：
    /// 切到别的软件时两窗要能一起被盖住。所以只在**激活时联动抬升**，
    /// 不设任何 `HWND_TOPMOST`。
    void raisedToFront();

    /// 677：Escape 按下（**两窗统一入口**）。
    ///
    /// 【为什么放 C++】旧实现两窗各挂一份 `Shortcut { sequence: "Escape" }`：
    /// Overlay 有「收面板→退全屏→退出」三层，Main.qml 却只有
    /// `requestExit + Qt.quit()`——焦点在宿主窗（点标题栏/视频区）时按
    /// Esc，**全屏状态下会直接关掉播放器**（真机回归）。
    /// 改为 C++ 统一拦截后只剩一份三层语义，不会再走错分支。
    void escapePressed();

private:
    void createVideoWindow();
    void syncGeometry();
    void pumpEvents();
    void applyHdrOptions(bool hdr, bool hlg);

    /// 679：定位 Flutter 主窗（`--parent-pid` + 类名 + 顶层可见）。
    HWND findParentWindow();
    /// 677：按 Flutter 主窗当前矩形重算并应用本窗矩形（房间并排跟随）。
    void followParentOnce();
    /// 680：用户拖动/拉伸开始 → 挂起跟随托管（停手 400ms 自动恢复）。
    void suspendFollowForUserGesture();

    /// 669：初始化前用 option、初始化后用 property（mpv 规则）。
    void setMpvString(const char* name, const QString& value);
    void refreshOutputParams();

    static LRESULT CALLBACK VideoWndProc(HWND hwnd, UINT msg, WPARAM wparam,
                                         LPARAM lparam);

    QWindow* host_ = nullptr;
    HWND host_hwnd_ = nullptr;
    HWND video_hwnd_ = nullptr;
    mpv_handle* mpv_ = nullptr;

    // 677：房间并排 / 全屏 / 跟随
    QRect splitRect_;              ///< 并排矩形（退全屏显式回这里）
    bool hasSplitRect_ = false;
    bool followParent_ = false;    ///< 房间并排跟随开关
    HWND parentHwnd_ = nullptr;    ///< Flutter 主窗（缓存，失效重找）
    qint64 parentPid_ = 0;         ///< --parent-pid
    QRect lastFollowRect_;         ///< 上一次应用的跟随矩形（变化才动）

    /// 679：程序性几何变更标志（防双向跟随死循环）。
    bool applyingProgrammaticGeometry_ = false;
    /// 679：上一次回传的用户矩形（去重，避免拖动中每像素发一帧）。
    QRect lastUserRect_;

    /// 680：用户正在拖动/拉伸本窗 → 挂起「跟随 Flutter 窗」的托管。
    ///
    /// 【真机回归：拖 Qt 窗面板不跟随】旧实现 `setFollowParent(true)` 下
    /// `followParentOnce()` 每 50ms 把窗口拽回 Flutter 窗左侧——用户拖走
    /// 后立刻被拉回，那次拉回又是程序性移动（被 applyingProgrammaticGeometry_
    /// 屏蔽）→ 面板永远收不到 `windowMoved`。
    /// 现在：拖动/拉伸期间挂起托管，停手 400ms 后自动恢复并重新对齐。
    bool followParentSuspended_ = false;
    QTimer* suspendResumeTimer_ = nullptr;

    /// 682→683：当前是否处于「与面板联动抬升」模式（房间并排时开启）。
    ///
    /// 注意：这**不是**置顶。开启后本窗被激活时会通知 Dart 把面板一起
    /// 抬上来（两窗同层），切到别的软件时两窗一起被正常盖住。
    bool topmost_ = false;

    int insetTop_ = 0;
    int insetBottom_ = 0;
    int lastX_ = -1;
    int lastY_ = -1;
    int lastW_ = -1;
    int lastH_ = -1;


    QString danmakuFile_;  ///< 当前弹幕 ASS 临时文件
    int danmakuSubId_ = -1;  ///< 当前弹幕轨 id（次字幕轨）

    qint64 positionMs_ = 0;
    qint64 durationMs_ = 0;
    bool paused_ = true;

    /// 682：当前是否已加载媒体（`stop` 后为 false，`load` 后为 true）。
    ///
    /// 【为什么需要】`stopPlayback()` 只把本地镜像 `paused_` 置 true，而
    /// mpv 的 `pause` 属性仍停在 `no` → 镜像与实际错位。下一次 `load`
    /// 新资源时 mpv 实际在播、镜像却仍是「暂停」→ QML `togglePause()`
    /// 取反得到「继续暂停」→ **播放/暂停点了没反应**（真机回归：删除在播
    /// 资源后再播其他资源）。这里用显式标志把「有没有媒体」与「暂停态」
    /// 解耦，并在 `load`/`stop` 两头强制对齐 mpv 真实 `pause` 属性。
    bool hasMedia_ = false;
    bool hdrRequested_ = false;
    bool initialized_ = false;  ///< mpv_initialize 已完成（option→property）

    QString outPrimaries_;
    QString outGamma_;
    QString lastError_;

    QTimer* timer_ = nullptr;
};

#endif  // MPV_WINDOW_H
