#include "mpv_window.h"

#include <QDebug>
#include <QTimer>

#include <mpv/client.h>

#include <dxgi1_6.h>
#include <wrl/client.h>

#include <cstring>

namespace {

// 窗口类名必须是宽字符：WNDCLASSEX::lpszClassName 与 CreateWindowEx 的
// 第 2 参都是 LPCWSTR。写成 char[] 会直接编译失败（C2664）。
constexpr wchar_t kVideoClass[] = L"HIMI_QT_MPV_VIDEO";

/// 从 mpv 的 `video-out-params` / `video-params` 节点里取字符串字段。
///
/// 这两个属性是 MPV_FORMAT_NODE_MAP：`u.list` 里有并列的 `keys` / `values`
/// 数组。任一为空都直接返回空串（mpv 在切换片源的空窗期会下发空 map）。
QString nodeString(const mpv_node& node, const char* key) {
    if (node.format != MPV_FORMAT_NODE_MAP) return QString();
    const mpv_node_list* list = node.u.list;
    if (list == nullptr || list->keys == nullptr || list->values == nullptr) {
        return QString();
    }
    for (int i = 0; i < list->num; ++i) {
        if (std::strcmp(list->keys[i], key) != 0) continue;
        const mpv_node& value = list->values[i];
        if (value.format == MPV_FORMAT_STRING && value.u.string != nullptr) {
            return QString::fromUtf8(value.u.string);
        }
        return QString();
    }
    return QString();
}

/// 判定「实际输出」是否为 HDR（PQ/HLG + BT.2020）。
///
/// 【为什么看 video-out-params 而不是 video-params】
/// `video-params` 描述**片源**（内容本身就是 HDR 也会是 pq/bt.2020），
/// 用它判断会把「片源是 HDR 但输出被 tone map 成 SDR」误判成功。
/// `video-out-params` 才是 mpv 真正交给 swapchain 的参数：
///   - 直出成功 → gamma=pq, primaries=bt.2020
///   - 被 tone map → gamma=bt.1886, primaries=bt.709
bool isHdrOutput(const QString& gamma, const QString& primaries) {
    const QString g = gamma.toLower();
    const QString p = primaries.toLower();
    const bool hdrGamma = (g == "pq" || g == "hlg");
    const bool wideGamut = (p == "bt.2020" || p == "bt2020");
    return hdrGamma && wideGamut;
}

}  // namespace

MpvWindow::MpvWindow(QObject* parent) : QObject(parent) {}

MpvWindow::~MpvWindow() {
    if (timer_ != nullptr) {
        timer_->stop();
        delete timer_;
        timer_ = nullptr;
    }
    if (mpv_ != nullptr) {
        // 先销毁 mpv 再销毁窗口：顺序反过来 mpv 会往已销毁的 HWND 里画。
        // （`wid` 是初始化期选项，init 之后再写无效，所以不试图解绑。）
        mpv_command_string(mpv_, "quit");
        mpv_terminate_destroy(mpv_);
        mpv_ = nullptr;
    }
    if (video_hwnd_ != nullptr) {
        ::DestroyWindow(video_hwnd_);
        video_hwnd_ = nullptr;
    }
}

HWND MpvWindow::hostHwnd() const {
    if (host_ == nullptr) return nullptr;
    return reinterpret_cast<HWND>(host_->winId());
}

bool MpvWindow::attach(QWindow* host, const QString& url, bool hdrOn,
                       VideoMode mode) {
    if (host == nullptr) {
        lastError_ = "host window 为空";
        return false;
    }
    host_ = host;
    url_ = url;
    hdrOn_ = hdrOn;
    mode_ = mode;

    createVideoWindow();
    if (video_hwnd_ == nullptr) {
        lastError_ = "创建 mpv 视频窗口失败";
        return false;
    }

    queryDisplayHdr();

    // ---- 创建 mpv ----
    mpv_ = mpv_create();
    if (mpv_ == nullptr) {
        lastError_ = "mpv_create 失败";
        return false;
    }

    // `wid` 必须在 mpv_initialize **之前**设置，否则 vo 已经初始化完，
    // 会走 force-window 自己开一个窗口（真机表现：多出一个黑窗）。
    const QString wid = QString::number(reinterpret_cast<quintptr>(video_hwnd_));
    mpv_set_option_string(mpv_, "wid", wid.toUtf8().constData());

    // 与 Flutter 插件（buildWindowsMpvOptions）保持同一套 HDR 选项，
    // 否则两边的验证结论无法互相印证。
    mpv_set_option_string(mpv_, "vo", "gpu-next");
    mpv_set_option_string(mpv_, "vid", "auto");
    mpv_set_option_string(mpv_, "aid", "auto");
    mpv_set_option_string(mpv_, "force-window", "no");
    mpv_set_option_string(mpv_, "gpu-api", "d3d11");
    mpv_set_option_string(mpv_, "gpu-context", "d3d11");
    mpv_set_option_string(mpv_, "d3d11-output-mode", "window");
    mpv_set_option_string(mpv_, "d3d11-output-csp", "auto");
    mpv_set_option_string(mpv_, "gpu-hwdec-interop", "auto");
    mpv_set_option_string(mpv_, "hwdec", "auto-copy");
    mpv_set_option_string(mpv_, "hwdec-software-fallback", "yes");
    mpv_set_option_string(mpv_, "cache", "yes");
    mpv_set_option_string(mpv_, "osc", "no");
    mpv_set_option_string(mpv_, "osd-level", "0");
    mpv_set_option_string(mpv_, "keep-open", "yes");
    mpv_set_option_string(
        mpv_, "msg-level",
        "all=info,vo/gpu-next=v,vo/gpu-next/d3d11=debug,gpu=debug");

    applyHdrOptionsBeforeInit(hdrOn_);

    if (mpv_initialize(mpv_) < 0) {
        lastError_ = "mpv_initialize 失败";
        return false;
    }

    // 观察实际输出参数（HDR 判定的权威来源）与播放状态。
    mpv_observe_property(mpv_, 0, "video-out-params", MPV_FORMAT_NODE);
    mpv_observe_property(mpv_, 0, "video-params", MPV_FORMAT_NODE);
    mpv_observe_property(mpv_, 0, "pause", MPV_FORMAT_FLAG);

    // 不请求日志的话 MPV_EVENT_LOG_MESSAGE 永远不会来（pumpEvents 里那段
    // 过滤 HDR/swapchain 关键字的逻辑就形同虚设）。
    mpv_request_log_messages(mpv_, "info");

    if (!url_.isEmpty()) {
        load(url_);
    }

    timer_ = new QTimer(this);
    timer_->setInterval(20);
    connect(timer_, &QTimer::timeout, this, &MpvWindow::pumpEvents);
    timer_->start();

    syncGeometry();
    refreshTitle();
    return true;
}

void MpvWindow::createVideoWindow() {
    if (video_hwnd_ != nullptr) return;
    host_hwnd_ = hostHwnd();
    if (host_hwnd_ == nullptr) return;

    static bool registered = false;
    if (!registered) {
        WNDCLASSEX wc = {};
        wc.cbSize = sizeof(WNDCLASSEX);
        wc.style = CS_HREDRAW | CS_VREDRAW | CS_DBLCLKS;
        wc.lpfnWndProc = &MpvWindow::VideoWndProc;
        wc.hInstance = ::GetModuleHandle(nullptr);
        wc.lpszClassName = kVideoClass;
        wc.hCursor = ::LoadCursor(nullptr, IDC_ARROW);
        // 黑底：HDR 首帧到来前不闪白。
        wc.hbrBackground = ::CreateSolidBrush(RGB(0, 0, 0));
        ::RegisterClassEx(&wc);
        registered = true;
    }

    if (mode_ == VideoMode::Child) {
        // 子窗口：挂在 Qt 窗口客户区。这是最终架构要用的形态。
        RECT rc = {};
        ::GetClientRect(host_hwnd_, &rc);
        video_hwnd_ = ::CreateWindowEx(
            0, kVideoClass, L"", WS_CHILD | WS_VISIBLE | WS_CLIPSIBLINGS, 0, 0,
            rc.right - rc.left, rc.bottom - rc.top, host_hwnd_, nullptr,
            ::GetModuleHandle(nullptr), nullptr);
    } else if (mode_ == VideoMode::TopLevel) {
        // 顶层窗口：脱离 Qt 的合成，用来排除「Qt 遮挡子窗口」这一因素。
        // WS_EX_TOOLWINDOW：不占任务栏，看起来仍像一个播放器窗口。
        RECT host_rc = {};
        ::GetWindowRect(host_hwnd_, &host_rc);
        video_hwnd_ = ::CreateWindowEx(
            WS_EX_TOOLWINDOW, kVideoClass, L"HIMI Qt Spike (top-level video)",
            WS_POPUP | WS_VISIBLE, host_rc.left, host_rc.top,
            host_rc.right - host_rc.left, host_rc.bottom - host_rc.top, nullptr,
            nullptr, ::GetModuleHandle(nullptr), nullptr);
    }

    if (video_hwnd_ != nullptr) {
        ::SetWindowLongPtrW(video_hwnd_, GWLP_USERDATA,
                            reinterpret_cast<LONG_PTR>(this));
        ::ShowWindow(video_hwnd_, SW_SHOW);
        ::SetFocus(video_hwnd_);
    }
}

void MpvWindow::syncGeometry() {
    if (video_hwnd_ == nullptr || host_hwnd_ == nullptr) return;

    int x = 0;
    int y = 0;
    int w = 0;
    int h = 0;

    if (mode_ == VideoMode::Child) {
        RECT rc = {};
        ::GetClientRect(host_hwnd_, &rc);
        w = rc.right - rc.left;
        h = rc.bottom - rc.top - bottomInset_;
        x = 0;
        y = 0;
    } else if (mode_ == VideoMode::TopLevel) {
        // 顶层：按屏幕坐标跟随 Qt 窗口客户区。
        // 同样让出底部提示条高度——排障模式下更需要看见操作指引。
        RECT rc = {};
        ::GetClientRect(host_hwnd_, &rc);
        POINT origin = {0, 0};
        ::ClientToScreen(host_hwnd_, &origin);
        x = origin.x;
        y = origin.y;
        w = rc.right - rc.left;
        h = rc.bottom - rc.top - bottomInset_;
    }

    if (w <= 0 || h <= 0) return;
    // 20ms 泵一次，几何没变就不要反复 SetWindowPos（会持续触发重绘）。
    if (x == lastX_ && y == lastY_ && w == lastW_ && h == lastH_) return;
    lastX_ = x;
    lastY_ = y;
    lastW_ = w;
    lastH_ = h;

    ::SetWindowPos(video_hwnd_, HWND_TOP, x, y, w, h,
                   SWP_NOACTIVATE | SWP_SHOWWINDOW);
}

void MpvWindow::setBottomInset(int px) {
    if (px < 0) px = 0;
    if (bottomInset_ == px) return;
    bottomInset_ = px;
    // 强制下一次 syncGeometry 生效
    lastW_ = -1;
    lastH_ = -1;
    syncGeometry();
}

void MpvWindow::load(const QString& url) {
    if (mpv_ == nullptr) return;
    url_ = url;
    const QByteArray u = url.toUtf8();
    const char* cmd[] = {"loadfile", u.constData(), nullptr};
    const int rc = mpv_command(mpv_, cmd);
    if (rc < 0) {
        lastError_ =
            QStringLiteral("loadfile 失败: %1").arg(mpv_error_string(rc));
        qWarning().noquote() << "[mpv]" << lastError_;
    } else {
        qInfo().noquote() << "[mpv] loadfile" << url;
    }
}

void MpvWindow::applyHdrOptionsBeforeInit(bool enabled) {
    if (mpv_ == nullptr) return;
    hdrOn_ = enabled;

    if (enabled) {
        // rgb10_a2：10bit swapchain，HDR 直出的前提。
        mpv_set_option_string(mpv_, "d3d11-output-format", "rgb10_a2");
        // target-colorspace-hint=yes：让 mpv 主动把 swapchain 的
        // DXGI_COLOR_SPACE 设为 HDR10（这是「直出」而非「tone map」的开关）。
        mpv_set_option_string(mpv_, "target-colorspace-hint", "yes");
        mpv_set_option_string(mpv_, "target-prim", "bt.2020");
        mpv_set_option_string(mpv_, "target-trc", "pq");
        mpv_set_option_string(mpv_, "hdr-compute-peak", "auto");
        mpv_set_option_string(mpv_, "tone-mapping", "clip");
    } else {
        mpv_set_option_string(mpv_, "d3d11-output-format", "auto");
        mpv_set_option_string(mpv_, "target-colorspace-hint", "no");
        mpv_set_option_string(mpv_, "target-prim", "auto");
        mpv_set_option_string(mpv_, "target-trc", "auto");
        mpv_set_option_string(mpv_, "tone-mapping", "auto");
    }
}

void MpvWindow::setHdrEnabled(bool enabled) {
    if (mpv_ == nullptr) return;
    if (hdrOn_ == enabled) return;

    // 运行时改这两个属性需要重建 vo，mpv 会自动处理（会有一次短暂黑屏）。
    hdrOn_ = enabled;
    mpv_set_property_string(mpv_, "target-colorspace-hint",
                            enabled ? "yes" : "no");
    mpv_set_property_string(mpv_, "target-prim", enabled ? "bt.2020" : "auto");
    mpv_set_property_string(mpv_, "target-trc", enabled ? "pq" : "auto");

    qInfo().noquote() << "[mpv] HDR 切换为" << (enabled ? "开" : "关");
    refreshTitle();
}

void MpvWindow::queryDisplayHdr() {
    displayHdr_ = false;
    displayName_.clear();

    Microsoft::WRL::ComPtr<IDXGIFactory1> factory;
    if (FAILED(CreateDXGIFactory1(IID_PPV_ARGS(&factory)))) return;

    // 找到窗口所在的显示器，只查那一台（多屏时别把别的屏的 HDR 算进来）。
    HMONITOR target_monitor = nullptr;
    if (host_hwnd_ != nullptr) {
        target_monitor =
            ::MonitorFromWindow(host_hwnd_, MONITOR_DEFAULTTOPRIMARY);
    }

    Microsoft::WRL::ComPtr<IDXGIAdapter1> adapter;
    for (UINT i = 0; factory->EnumAdapters1(i, &adapter) != DXGI_ERROR_NOT_FOUND;
         ++i) {
        Microsoft::WRL::ComPtr<IDXGIOutput> output;
        for (UINT j = 0; adapter->EnumOutputs(j, &output) != DXGI_ERROR_NOT_FOUND;
             ++j) {
            Microsoft::WRL::ComPtr<IDXGIOutput6> output6;
            if (SUCCEEDED(output.As(&output6))) {
                DXGI_OUTPUT_DESC1 desc = {};
                if (SUCCEEDED(output6->GetDesc1(&desc))) {
                    const bool same =
                        target_monitor == nullptr || desc.Monitor == target_monitor;
                    if (same) {
                        displayHdr_ =
                            desc.ColorSpace ==
                            DXGI_COLOR_SPACE_RGB_FULL_G2084_NONE_P2020;
                        displayName_ = QString::fromWCharArray(desc.DeviceName);
                        qInfo().noquote()
                            << "[hdr] 显示器" << displayName_
                            << (displayHdr_ ? "HDR 已开启" : "HDR 未开启")
                            << QStringLiteral("(maxLum=%1nits)")
                                   .arg(desc.MaxLuminance, 0, 'f', 1);
                        return;
                    }
                }
            }
            output.Reset();
        }
        adapter.Reset();
    }
}

void MpvWindow::pumpEvents() {
    if (mpv_ == nullptr) return;

    // 窗口被拖动/缩放后视频窗口要跟上（Qt 的 resize 信号在原生子窗口下
    // 不可靠，直接按节奏对齐几何最省事）。
    syncGeometry();

    bool dirty = false;
    while (true) {
        mpv_event* event = mpv_wait_event(mpv_, 0);
        if (event->event_id == MPV_EVENT_NONE) break;

        switch (event->event_id) {
            case MPV_EVENT_PROPERTY_CHANGE: {
                auto* prop = static_cast<mpv_event_property*>(event->data);
                if (prop == nullptr || prop->name == nullptr) break;
                const QString name = QString::fromUtf8(prop->name);

                if (prop->format == MPV_FORMAT_NODE) {
                    auto* node = static_cast<mpv_node*>(prop->data);
                    if (node == nullptr) break;
                    if (name == "video-out-params") {
                        outPrimaries_ = nodeString(*node, "primaries");
                        outGamma_ = nodeString(*node, "gamma");
                        qInfo().noquote()
                            << QStringLiteral(
                                   "[hdr] 实际输出 primaries=%1 gamma=%2 → %3")
                                   .arg(outPrimaries_.isEmpty() ? "?"
                                                                : outPrimaries_)
                                   .arg(outGamma_.isEmpty() ? "?" : outGamma_)
                                   .arg(isHdrOutput(outGamma_, outPrimaries_)
                                            ? "HDR 直出"
                                            : "SDR（tone map）");
                        dirty = true;
                    } else if (name == "video-params") {
                        contentPrimaries_ = nodeString(*node, "primaries");
                        contentGamma_ = nodeString(*node, "gamma");
                        qInfo().noquote()
                            << QStringLiteral("[hdr] 片源 primaries=%1 gamma=%2")
                                   .arg(contentPrimaries_, contentGamma_);
                        dirty = true;
                    }
                } else if (prop->format == MPV_FORMAT_FLAG) {
                    if (name == "pause" && prop->data != nullptr) {
                        paused_ = *static_cast<int*>(prop->data) != 0;
                        dirty = true;
                    }
                }
                break;
            }
            case MPV_EVENT_END_FILE: {
                auto* end = static_cast<mpv_event_end_file*>(event->data);
                if (end != nullptr && end->reason == MPV_END_FILE_REASON_ERROR) {
                    lastError_ = QString::fromUtf8(mpv_error_string(end->error));
                    qWarning().noquote() << "[mpv] 播放失败:" << lastError_;
                    dirty = true;
                }
                break;
            }
            case MPV_EVENT_LOG_MESSAGE: {
                auto* msg = static_cast<mpv_event_log_message*>(event->data);
                // mpv 文档未保证 text/prefix 非空，先判空再 fromUtf8
                // （fromUtf8(nullptr) 在部分 Qt 版本上是未定义行为）。
                if (msg != nullptr && msg->text != nullptr) {
                    // 只放行与 HDR/swapchain 相关的行，避免刷屏。
                    const QString text = QString::fromUtf8(msg->text).trimmed();
                    const QString prefix =
                        msg->prefix != nullptr ? QString::fromUtf8(msg->prefix)
                                               : QString();
                    if (text.contains("color", Qt::CaseInsensitive) ||
                        text.contains("swapchain", Qt::CaseInsensitive) ||
                        text.contains("HDR", Qt::CaseInsensitive) ||
                        text.contains("colorspace", Qt::CaseInsensitive)) {
                        qInfo().noquote()
                            << QStringLiteral("[%1] %2").arg(prefix, text);
                    }
                }
                break;
            }
            default:
                break;
        }
    }

    if (dirty) refreshTitle();
}

QString MpvWindow::statusLine() const {
    const bool outHdr = isHdrOutput(outGamma_, outPrimaries_);

    QString state;
    if (!lastError_.isEmpty()) {
        state = QStringLiteral("错误: %1").arg(lastError_);
    } else if (outGamma_.isEmpty()) {
        state = QStringLiteral("等待首帧…");
    } else {
        state = outHdr ? QStringLiteral("HDR10 ✓ (BT.2020/PQ)")
                       : QStringLiteral("SDR ✗ (BT.709)");
    }

    QString content = QStringLiteral("片源 ?");
    if (!contentGamma_.isEmpty()) {
        content =
            QStringLiteral("片源 %1/%2").arg(contentPrimaries_, contentGamma_);
    }

    const QString display = displayHdr_ ? QStringLiteral("显示器 HDR 开")
                                        : QStringLiteral("显示器 HDR 关");
    const QString videoMode = mode_ == VideoMode::Child
                                  ? QStringLiteral("子窗")
                                  : QStringLiteral("顶层");

    return QStringLiteral(
               "HIMI Qt Spike — %1 | %2 | %3 | %4 | HDR请求:%5 | %6")
        .arg(state, content, display, videoMode, hdrOn_ ? "开" : "关",
             paused_ ? "暂停" : "播放");
}

void MpvWindow::refreshTitle() {
    if (host_ != nullptr) {
        host_->setTitle(statusLine());
    }
}

void MpvWindow::printVerifySteps() const {
    // 注意：下面文本里 `%2` 出现两次（「视频模式」与「本次视频模式」）。
    // QString::arg 会替换**所有**同编号占位符，所以两次都会拿到同一个
    // 模式字符串——这是刻意的，不是笔误。
    // 【raw string 分隔符必须是 HIMI 而不是默认空串】
    // 文本里含 `"HDR10 ✓ (BT.2020/PQ)"`，其中的 `)"` 会被默认终止符
    // 误判为结束 → raw string 提前截断 → 编译失败（C2001/C2143）。
    qInfo().noquote() << QStringLiteral(R"himi(
================ HDR 验证步骤 ================
当前状态: %1
视频模式: %2

【第一步】确认系统 HDR 已开
   Windows 设置 → 系统 → 显示 → HDR
   高级显示设置里应显示: 10-bit + HDR 色彩空间
   本程序已自动检测: %3

【第二步】看窗口标题栏
   "HDR10 ✓ (BT.2020/PQ)" → 直出成功
   "SDR ✗ (BT.709)"       → 被 tone map 成 SDR
   "等待首帧…"            → 视频没出画面，先解决这个（见下方排障）

【第三步】截图法（最可靠，不需要工具）
   按 Win+Shift+S 截取当前画面，再和屏幕实际画面对比:
     截图明显过曝/发白 → HDR 直出（屏幕 1000nit 被压到 100nit）
     截图与屏幕一致     → 已降为 SDR

【第四步】按 H 做 A/B 对比
   切换后画面若明显变暗/发闷 → 原状态是 HDR 直出
   若几乎无变化             → 一直在 SDR

【第五步】按 F 全屏
   窗口模式下部分驱动会降级，全屏结论更可信

【看不到画面时的排障】
   本次视频模式 = %2
   若「子窗」模式黑屏，用顶层模式重跑一次:
     himi_qt_win.exe --video-top-level "你的地址"
   判读:
     子窗有画面              → 最终架构可行
     子窗黑屏 / 顶层有画面   → Qt 遮挡子窗口，655 改用覆盖层方案
     两种都黑屏              → mpv 侧问题，与 Qt 无关

按键: 空格=暂停  F=全屏  H=切HDR  S=本帮助  Esc=退出
=============================================
)himi")
                           .arg(statusLine(),
                                mode_ == VideoMode::Child ? "子窗（最终架构）"
                                                          : "顶层（排障用）",
                                displayHdr_ ? "HDR 已开启" : "HDR 未开启");
}

void MpvWindow::handleKey(int vk) {
    switch (vk) {
        case VK_SPACE:
            if (mpv_ != nullptr) mpv_command_string(mpv_, "cycle pause");
            break;
        case 'F':
            if (host_ != nullptr) {
                if (host_->visibility() == QWindow::FullScreen) {
                    host_->showNormal();
                } else {
                    host_->showFullScreen();
                }
            }
            break;
        case 'H':
            setHdrEnabled(!hdrOn_);
            break;
        case 'S':
            printVerifySteps();
            break;
        case VK_ESCAPE:
            if (host_ != nullptr) {
                if (host_->visibility() == QWindow::FullScreen) {
                    host_->showNormal();
                } else {
                    host_->close();
                }
            }
            break;
        default:
            break;
    }
}

LRESULT CALLBACK MpvWindow::VideoWndProc(HWND hwnd, UINT msg, WPARAM wparam,
                                         LPARAM lparam) {
    auto* self =
        reinterpret_cast<MpvWindow*>(::GetWindowLongPtrW(hwnd, GWLP_USERDATA));

    switch (msg) {
        case WM_KEYDOWN:
            if (self != nullptr) {
                self->handleKey(static_cast<int>(wparam));
                return 0;
            }
            break;
        case WM_LBUTTONDBLCLK:
            if (self != nullptr) self->handleKey('F');
            return 0;
        default:
            break;
    }
    return ::DefWindowProcW(hwnd, msg, wparam, lparam);
}
