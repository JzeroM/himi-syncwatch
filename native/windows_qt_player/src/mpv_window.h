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

    // 【668】挖孔机制已退役：控件层移到**逐像素透明悬浮窗**（顶层窗口
    // 永远盖住子窗口 = 真合成），视频满铺直出、玻璃任意半透明、零黑底。

    /// 切换宿主窗口全屏（控件在悬浮层，全屏对象是视频宿主）。
    Q_INVOKABLE void toggleHostFullscreen();
    Q_INVOKABLE bool isHostFullscreen() const;

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
