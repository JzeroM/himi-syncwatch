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

    /// 677：定位 Flutter 主窗（`--parent-pid` + 类名 + 顶层可见）。
    HWND findParentWindow();
    /// 677：按 Flutter 主窗当前矩形重算并应用本窗矩形（房间并排跟随）。
    void followParentOnce();

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
    bool hdrRequested_ = false;
    bool initialized_ = false;  ///< mpv_initialize 已完成（option→property）

    QString outPrimaries_;
    QString outGamma_;
    QString lastError_;

    QTimer* timer_ = nullptr;
};

#endif  // MPV_WINDOW_H
