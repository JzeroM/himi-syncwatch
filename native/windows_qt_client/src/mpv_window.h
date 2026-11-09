#ifndef MPV_WINDOW_H
#define MPV_WINDOW_H

// windows.h 默认会定义 min/max 宏，破坏 Qt 与 STL 的 std::min/std::max
// （报错形如 "macro 'min' requires 2 arguments"）。必须在任何 windows.h
// 之前定义 NOMINMAX。
#ifndef NOMINMAX
#define NOMINMAX
#endif
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif

#include <QObject>
#include <QString>
#include <QWindow>

#include <windows.h>

struct mpv_handle;
class QTimer;

/// 654：mpv 直出窗口（spike）。
///
/// 【为什么是原生 HWND 而不是把视频画进 QML】
/// 想让 QML 覆盖视频，就得把 mpv 渲染进 QML 场景（`mpv_render_context`）。
/// 但 libmpv 的 render API **只有 OpenGL 与软件后端，没有 D3D11**：
/// 走 OpenGL FBO 意味着 mpv 先把画面转成 SDR RGBA 再交给 Qt，
/// **HDR 直出必然丢失**。
///
/// 所以路线 A（保 HDR）的做法是：mpv 自己拥有一个 HWND（`wid`），
/// 用 `vo=gpu-next` + `d3d11-output-mode=window` 直出到 DWM，
/// HDR 由 mpv 直接和显示器协商，Qt 完全不参与视频像素路径。
/// UI 后续（655+）用**独立透明窗口**叠加在上面，不碰这条链路。
///
/// 【两种挂载模式，用来隔离两类失败】
/// 本轮有一个无法从源码推断、只能实测的未知点：**Qt 自己的 swapchain
/// 会不会盖住 mpv 子窗口**。Flutter 就栽在这里（子 HWND 被
/// DirectComposition 遮挡 → 灰屏）。若只做一种模式，一旦黑屏就分不清是
/// 「Qt 遮挡」还是「HDR 失败」，会把结论带偏。
///
///   child（默认）    mpv 子窗口挂在 Qt 窗口下 —— 最终架构要用的形态
///   topLevel         mpv 独立顶层窗口，跟随 Qt 窗口几何 —— 排除遮挡因素
///
/// 判读方式：
///   child 有画面           → 最终架构可行，直接看 HDR 结论
///   child 黑屏但 topLevel 有 → Qt 遮挡，需改用覆盖层方案（655 处理）
///   两种都黑屏             → mpv 侧问题（片源/解码），与 Qt 无关
class MpvWindow : public QObject {
    Q_OBJECT
public:
    enum class VideoMode {
        Child,     ///< mpv 子窗口挂在 Qt 窗口客户区（最终架构形态）
        TopLevel,  ///< mpv 独立顶层窗口，跟随 Qt 窗口几何
    };

    explicit MpvWindow(QObject* parent = nullptr);
    ~MpvWindow() override;

    /// 绑定到 Qt 窗口并创建 mpv 会话。
    /// @param host      Qt 主窗口（取 winId() 当父 HWND）
    /// @param url       视频地址；空则只建窗口不播放
    /// @param hdrOn     初始是否请求 HDR 直出
    /// @param mode      挂载模式（见类注释）
    bool attach(QWindow* host, const QString& url, bool hdrOn, VideoMode mode);

    /// 加载/切换片源。
    void load(const QString& url);

    /// 开关 HDR（运行时切换，用于 A/B 对比）。
    void setHdrEnabled(bool enabled);
    bool hdrEnabled() const { return hdrOn_; }

    /// 底部为 QML 让出的像素高度（全屏时传 0）。两种模式都生效。
    void setBottomInset(int px);

    /// 当前状态的一行摘要（窗口标题用）。
    QString statusLine() const;

    /// 打印验证步骤到控制台。
    void printVerifySteps() const;

    VideoMode mode() const { return mode_; }

private:
    void createVideoWindow();
    void syncGeometry();
    void pumpEvents();
    void applyHdrOptionsBeforeInit(bool enabled);
    void queryDisplayHdr();
    void refreshTitle();
    void handleKey(int vk);
    HWND hostHwnd() const;

    static LRESULT CALLBACK VideoWndProc(HWND hwnd, UINT msg, WPARAM wparam,
                                         LPARAM lparam);

    QWindow* host_ = nullptr;
    HWND host_hwnd_ = nullptr;
    HWND video_hwnd_ = nullptr;
    mpv_handle* mpv_ = nullptr;
    VideoMode mode_ = VideoMode::Child;

    bool hdrOn_ = true;
    bool paused_ = false;
    int bottomInset_ = 0;

    // 上一次同步的几何，避免每帧都 SetWindowPos（20ms 一次会很浪费）。
    int lastX_ = -1;
    int lastY_ = -1;
    int lastW_ = -1;
    int lastH_ = -1;

    // 内容（片源）色彩参数
    QString contentPrimaries_;
    QString contentGamma_;

    // 实际输出色彩参数 —— 判定 HDR 直出的**唯一权威依据**
    QString outPrimaries_;
    QString outGamma_;

    // 显示器 HDR 能力
    bool displayHdr_ = false;
    QString displayName_;

    QString url_;
    QString lastError_;

    QTimer* timer_ = nullptr;
};

#endif  // MPV_WINDOW_H
