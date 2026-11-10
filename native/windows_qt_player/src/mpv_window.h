#ifndef MPV_WINDOW_H
#define MPV_WINDOW_H

#include <QMap>
#include <QObject>
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

    /// 【664：视频窗口挖孔】QML 浮层（锁钮/Logo/面板）落在视频子窗口
    /// 覆盖带内会被 Win32 子窗口盖住（永远在 QML 之上）——面板点不到、
    /// 锁钮/Logo 不可见（真机截图实证）。把浮层矩形从视频窗口的
    /// SetWindowRgn 区域里挖掉，孔内露出下层 QML，可点可渲染。
    /// `rects` 元素为 QRectF，坐标是**窗口逻辑像素**（QML
    /// `mapToItem(null, 0, 0)` 的结果），内部按 DPR 换算。
    Q_INVOKABLE void setOverlayHoles(const QVariantList& rects);

    /// 通用 mpv 命令透传（sub-add / sub-remove / screenshot-to-file …）。
    Q_INVOKABLE bool command(const QStringList& args);

    /// 【665：弹幕 ASS 旁路】把弹幕生成的 ASS 内容写临时文件并挂成
    /// **次字幕轨**（`secondary-sid`）——mpv 0.37+ 支持双字幕轨，主字幕
    /// 与弹幕可同时渲染（wid 直出架构下 QML 画不进视频，ASS 是唯一
    /// 浮绘通道）。空文本 = 移除弹幕轨。
    Q_INVOKABLE void setDanmakuAss(const QString& assText);

    /// 664：QML 逻辑坐标 → 物理坐标用（与 setOverlayInsets 的换算一致，
    /// 由 main.cpp 在 attach 后注入 host 的 devicePixelRatio）。
    void setDevicePixelRatio(qreal dpr);

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

private:
    void createVideoWindow();
    void syncGeometry();
    void pumpEvents();
    void applyHdrOptions(bool hdr, bool hlg);
    void refreshOutputParams();

    /// 664：按 holes_ 重建视频窗口区域（整窗减去浮层孔）。
    void applyRegion();

    static LRESULT CALLBACK VideoWndProc(HWND hwnd, UINT msg, WPARAM wparam,
                                         LPARAM lparam);

    QWindow* host_ = nullptr;
    HWND host_hwnd_ = nullptr;
    HWND video_hwnd_ = nullptr;
    mpv_handle* mpv_ = nullptr;

    int insetTop_ = 0;
    int insetBottom_ = 0;
    int lastX_ = -1;
    int lastY_ = -1;
    int lastW_ = -1;
    int lastH_ = -1;

    QVariantList holes_;   ///< 浮层孔（窗口逻辑坐标 QRectF）
    QString holesSig_;     ///< 已应用孔签名（几何/孔都没变就不重建区域）
    qreal dpr_ = 1.0;      ///< 逻辑→物理像素换算（main.cpp 注入）
    QString danmakuFile_;  ///< 当前弹幕 ASS 临时文件
    int danmakuSubId_ = -1;  ///< 当前弹幕轨 id（次字幕轨）

    qint64 positionMs_ = 0;
    qint64 durationMs_ = 0;
    bool paused_ = true;
    bool hdrRequested_ = false;

    QString outPrimaries_;
    QString outGamma_;
    QString lastError_;

    QTimer* timer_ = nullptr;
};

#endif  // MPV_WINDOW_H
