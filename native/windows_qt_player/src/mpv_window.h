#ifndef MPV_WINDOW_H
#define MPV_WINDOW_H

#include <QObject>
#include <QString>
#include <QUrl>
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

    void setPaused(bool paused);
    void setVolume(double volume);   ///< 0.0 ~ 1.0
    void setSpeed(double speed);
    void seekTo(qint64 positionMs);

    /// 通用属性透传（HDR 切换、字幕延迟等场景）。
    void setProperty(const QString& name, const QString& value);

    /// 给 QML 控件让出的高度（顶栏 + 底栏）。视频子窗口会相应收窄。
    void setOverlayInsets(int top, int bottom);

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
