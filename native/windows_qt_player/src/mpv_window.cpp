#include "mpv_window.h"

#include <QDateTime>
#include <QDebug>
#include <QFile>
#include <QCoreApplication>
#include <QGuiApplication>
#include <QRectF>
#include <QScreen>
#include <QStandardPaths>
#include <QTimer>
#include <QtGlobal>   // qMax / qMin（并排布局夹紧）
#include <QVariant>
#include <QVector>

#include <dwmapi.h>

#include <mpv/client.h>

#include <cstdint>
#include <cstring>

namespace {
/// 【676】轨道类型名归一。
///
/// Dart 侧 `NativeTrack.type` 的字幕类型是 **`sub`**（安卓同源），而
/// QML/main.cpp 传下来的是 **`subtitle`**；mpv `track-list` 的类型字段
/// 也是 **`sub`**（同文件 setDanmakuAss 的 secondary-sid 过滤自证）。
/// 旧实现拿 `subtitle` 直接跟 mpv 的 `sub` 比较 → 永远不匹配 →
/// 「用户选了字幕但视频不显示字幕 / 面板打勾错位」，音轨（audio 两边
/// 一致）不受影响。单点归一，两个入口共用。
QString mpvTrackType(const QString& type) {
    return type == QLatin1String("subtitle") ? QStringLiteral("sub") : type;
}
}  // namespace


namespace {

constexpr wchar_t kVideoClass[] = L"HIMI_QT_PLAYER_VIDEO";

/// 677：房间并排的最小尺寸（逻辑像素）。
///
/// 【为什么有最小宽】视频区低于 480 时底栏会挤爆（进度条 + 音量胶囊 +
/// 右组图标），控件重叠不可用。低于此值时**保持上一有效矩形不动**
/// （不再强行撑大——撑大会越过 Flutter 窗左缘造成两窗堆叠）。
constexpr int kMinWidth = 480;

/// 高度下限：低于此值顶栏 + 底栏就占满了，视频区不可见。
constexpr int kMinHeight = 360;

/// 677：房间面板窗的最小宽度（逻辑像素）——与 Dart 侧
/// `RoomPanelLayout.minPanelWidth` 必须一致（`setMinimumSize` 用它）。
/// 低于此值「季-集」两级缩进 + 播报板就挤不下了。
constexpr int kMinPanelWidth = 320;

/// 682：进房间并排的初始尺寸上限（逻辑像素）。
///
/// 【真机回归：进房间初始窗口太大】旧实现两窗合起来铺满整个工作区
///（宽 = 工作区宽、高 = 工作区高），观感像被强行最大化。现在按工作区
/// 缩比居中，4K 屏也不会变成巨幕。
constexpr int kSplitMaxWidth = 1600;

/// 682：进房间并排初始宽度占比（相对工作区宽，且不超过 kSplitMaxWidth）。
constexpr double kSplitWidthRatio = 0.82;

/// 682：进房间并排初始高度占比（相对工作区高）。
constexpr double kSplitHeightRatio = 0.80;

/// 从 mpv 的 `video-out-params` 节点里取字符串字段。
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

}  // namespace

MpvWindow::MpvWindow(QObject* parent) : QObject(parent) {}

MpvWindow::~MpvWindow() {
    if (suspendResumeTimer_ != nullptr) {
        suspendResumeTimer_->stop();
        delete suspendResumeTimer_;
        suspendResumeTimer_ = nullptr;
    }
    if (timer_ != nullptr) {
        timer_->stop();
        delete timer_;
        timer_ = nullptr;
    }
    if (mpv_ != nullptr) {
        // 先销毁 mpv 再销毁窗口：反过来 mpv 会往已释放的 HWND 里画。
        mpv_command_string(mpv_, "quit");
        mpv_terminate_destroy(mpv_);
        mpv_ = nullptr;
    }
    if (video_hwnd_ != nullptr) {
        ::DestroyWindow(video_hwnd_);
        video_hwnd_ = nullptr;
    }
}

bool MpvWindow::attach(QWindow* host, bool hdr, bool hlg) {
    if (host == nullptr) return false;
    host_ = host;
    host_hwnd_ = reinterpret_cast<HWND>(host->winId());

    // 679：用户拖动/缩放 → 回传（程序性移动由 applyingProgrammaticGeometry_
    // 屏蔽，不会走到这里）。用几何变化的**去重**再压一层：同一矩形不重复发。
    connect(host, &QWindow::xChanged, this, [this]() {
        if (applyingProgrammaticGeometry_ || host_ == nullptr) return;
        // 680：用户拖动中 → 续期挂起（停手 400ms 才恢复跟随）
        if (suspendResumeTimer_ != nullptr && suspendResumeTimer_->isActive()) {
            suspendResumeTimer_->start(400);
        }
        const QRect g = host_->geometry();
        if (g == lastUserRect_) return;
        lastUserRect_ = g;
        emit userWindowMoved(g.x(), g.y(), g.width(), g.height());
    });
    connect(host, &QWindow::yChanged, this, [this]() {
        if (applyingProgrammaticGeometry_ || host_ == nullptr) return;
        if (suspendResumeTimer_ != nullptr && suspendResumeTimer_->isActive()) {
            suspendResumeTimer_->start(400);
        }
        const QRect g = host_->geometry();
        if (g == lastUserRect_) return;
        lastUserRect_ = g;
        emit userWindowMoved(g.x(), g.y(), g.width(), g.height());
    });
    connect(host, &QWindow::widthChanged, this, [this]() {
        if (applyingProgrammaticGeometry_ || host_ == nullptr) return;
        if (suspendResumeTimer_ != nullptr && suspendResumeTimer_->isActive()) {
            suspendResumeTimer_->start(400);
        }
        const QRect g = host_->geometry();
        if (g == lastUserRect_) return;
        lastUserRect_ = g;
        emit userWindowMoved(g.x(), g.y(), g.width(), g.height());
    });
    connect(host, &QWindow::heightChanged, this, [this]() {
        if (applyingProgrammaticGeometry_ || host_ == nullptr) return;
        if (suspendResumeTimer_ != nullptr && suspendResumeTimer_->isActive()) {
            suspendResumeTimer_->start(400);
        }
        const QRect g = host_->geometry();
        if (g == lastUserRect_) return;
        lastUserRect_ = g;
        emit userWindowMoved(g.x(), g.y(), g.width(), g.height());
    });
    // 683：本窗被激活 → 通知 Dart 把面板一起抬上来（两窗同层）。
    //
    // 【为什么用 activeChanged 而不是轮询 z-order】`QWindow::activeChanged`
    // 是系统焦点变化的直接信号，零延迟、零轮询开销。用户点 Qt 视频窗时
    // 立刻联动，点面板窗时由 Dart 侧对称处理。
    connect(host, &QWindow::activeChanged, this, [this]() {
        if (host_ == nullptr) return;
        // 只在房间并排联动模式（topmost_ 复用为该开关）下生效。
        if (!topmost_) return;
        if (!host_->isActive()) return;  // 失活不处理（让用户正常切走）
        emit raisedToFront();
    });
    if (host_hwnd_ == nullptr) return false;

    hdrRequested_ = hdr;
    createVideoWindow();
    if (video_hwnd_ == nullptr) {
        lastError_ = QStringLiteral("创建视频窗口失败");
        return false;
    }

    mpv_ = mpv_create();
    if (mpv_ == nullptr) {
        lastError_ = QStringLiteral("mpv_create 失败");
        return false;
    }

    // `wid` 必须在 mpv_initialize **之前**设置，否则 vo 已初始化完，
    // 会走 force-window 自己开一个窗口。
    const QString wid = QString::number(reinterpret_cast<quintptr>(video_hwnd_));
    mpv_set_option_string(mpv_, "wid", wid.toUtf8().constData());

    // 与 Flutter 插件 buildWindowsMpvOptions 保持一致，保证两处行为相同。
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
    mpv_set_option_string(mpv_, "cache-on-disk", "no");
    mpv_set_option_string(mpv_, "sub-ass", "yes");
    mpv_set_option_string(mpv_, "sub-visibility", "yes");
    // 【676】字幕调节全类型生效（对齐安卓）：mpv 默认 `scale`，但显式
    // 置位防上游改默认——ASS/SSA 样式字幕也吃 `sub-scale`（字体大小）；
    // `sub-pos`（位置，%）、`sub-delay`（延迟，秒）本就对文本/位图全类型
    // 生效（mpv 手册）。注意**不设** `sub-ass-force-margins`：它会把
    // ASS 强制塞进黑边，反而压过用户的位置调节。
    mpv_set_option_string(mpv_, "sub-ass-override", "scale");
    // 【676】次字幕轨（弹幕 ASS 走 secondary-sid）**不得剥样式**：
    // mpv 的 `--secondary-sub-ass-override` 默认值是 `strip`（"radically
    // strip all ASS tags and styles"）→ 弹幕的颜色/\pos/\move/\alpha
    // 全被吃掉：所有弹幕挤在同一行、速度/透明度调节永远"没反应"。
    // 我们生成的 ASS 自带完整版式，这里要的是 "no"（按脚本渲染）。
    mpv_set_option_string(mpv_, "secondary-sub-ass-override", "no");
    mpv_set_option_string(mpv_, "osd-level", "0");
    mpv_set_option_string(mpv_, "osc", "no");
    mpv_set_option_string(mpv_, "keep-open", "yes");
    mpv_set_option_string(mpv_, "demuxer-max-bytes",
                          "268435456");  // 256MB
    mpv_set_option_string(mpv_, "demuxer-max-back-bytes",
                          "134217728");  // 128MB
    mpv_set_option_string(
        mpv_, "msg-level",
        "all=warn,vo/gpu-next=info,vo/gpu-next/d3d11=debug");

    applyHdrOptions(hdr, hlg);

    if (mpv_initialize(mpv_) < 0) {
        lastError_ = QStringLiteral("mpv_initialize 失败");
        return false;
    }
    initialized_ = true;

    mpv_observe_property(mpv_, 0, "video-out-params", MPV_FORMAT_NODE);
    mpv_observe_property(mpv_, 0, "pause", MPV_FORMAT_FLAG);
    mpv_observe_property(mpv_, 0, "time-pos", MPV_FORMAT_DOUBLE);
    mpv_observe_property(mpv_, 0, "duration", MPV_FORMAT_DOUBLE);

    timer_ = new QTimer(this);
    timer_->setInterval(20);
    connect(timer_, &QTimer::timeout, this, &MpvWindow::pumpEvents);
    timer_->start();

    syncGeometry();
    return true;
}

void MpvWindow::createVideoWindow() {
    if (video_hwnd_ != nullptr) return;

    static bool registered = false;
    if (!registered) {
        WNDCLASSEX wc = {};
        wc.cbSize = sizeof(WNDCLASSEX);
        wc.style = CS_HREDRAW | CS_VREDRAW | CS_DBLCLKS;
        wc.lpfnWndProc = &MpvWindow::VideoWndProc;
        wc.hInstance = ::GetModuleHandle(nullptr);
        wc.lpszClassName = kVideoClass;
        wc.hCursor = ::LoadCursor(nullptr, IDC_ARROW);
        wc.hbrBackground = ::CreateSolidBrush(RGB(0, 0, 0));
        ::RegisterClassEx(&wc);
        registered = true;
    }

    RECT rc = {};
    ::GetClientRect(host_hwnd_, &rc);
    video_hwnd_ = ::CreateWindowEx(
        // 665：WS_EX_TRANSPARENT = 点击穿透——鼠标事件穿过视频窗口
        // 落给下层 QML（单击收面板/双击播放/拖动手势全靠它；视频渲染
        // 不受影响，孔仅用于可见性）。
        WS_EX_TRANSPARENT, kVideoClass, L"",
        WS_CHILD | WS_VISIBLE | WS_CLIPSIBLINGS, 0,
        insetTop_, rc.right - rc.left,
        rc.bottom - rc.top - insetTop_ - insetBottom_, host_hwnd_, nullptr,
        ::GetModuleHandle(nullptr), nullptr);

    if (video_hwnd_ != nullptr) {
        ::SetWindowLongPtrW(video_hwnd_, GWLP_USERDATA,
                            reinterpret_cast<LONG_PTR>(this));
        ::ShowWindow(video_hwnd_, SW_SHOW);
    }
}

void MpvWindow::syncGeometry() {
    if (video_hwnd_ == nullptr || host_hwnd_ == nullptr) return;
    RECT rc = {};
    ::GetClientRect(host_hwnd_, &rc);
    const int x = 0;
    const int y = insetTop_;
    const int w = rc.right - rc.left;
    const int h = rc.bottom - rc.top - insetTop_ - insetBottom_;
    if (w <= 0 || h <= 0) return;
    // 20ms 泵一次，几何没变就不要反复 SetWindowPos（会持续触发重绘）。
    if (x == lastX_ && y == lastY_ && w == lastW_ && h == lastH_) return;
    lastX_ = x;
    lastY_ = y;
    lastW_ = w;
    lastH_ = h;
    ::SetWindowPos(video_hwnd_, nullptr, x, y, w, h,
                   SWP_NOACTIVATE | SWP_NOZORDER | SWP_SHOWWINDOW);
}

void MpvWindow::setOverlayInsets(int top, int bottom) {
    if (top < 0) top = 0;
    if (bottom < 0) bottom = 0;
    if (insetTop_ == top && insetBottom_ == bottom) return;
    insetTop_ = top;
    insetBottom_ = bottom;
    lastW_ = -1;
    lastH_ = -1;
    syncGeometry();
}

void MpvWindow::applyHdrOptions(bool hdr, bool hlg) {
    if (mpv_ == nullptr) return;
    if (hdr) {
        setMpvString("d3d11-output-format", QStringLiteral("rgb10_a2"));
        setMpvString("target-colorspace-hint", QStringLiteral("yes"));
        setMpvString("target-prim", QStringLiteral("bt.2020"));
        setMpvString("target-trc", hlg ? QStringLiteral("hlg")
                                      : QStringLiteral("pq"));
        setMpvString("hdr-compute-peak", QStringLiteral("auto"));
        setMpvString("tone-mapping", QStringLiteral("clip"));
    } else {
        setMpvString("d3d11-output-format", QStringLiteral("auto"));
        setMpvString("target-colorspace-hint", QStringLiteral("no"));
    }
}

void MpvWindow::setMpvString(const char* name, const QString& value) {
    if (mpv_ == nullptr) return;
    const QByteArray utf8 = value.toUtf8();
    // mpv 规则：mpv_initialize 之前用 option，之后必须用 property
    //（option 在初始化后写入会被拒绝 → 运行时 HDR 切换静默失效）。
    const int rc = initialized_
            ? mpv_set_property_string(mpv_, name, utf8.constData())
            : mpv_set_option_string(mpv_, name, utf8.constData());
    if (rc < 0) {
        qWarning().noquote() << "[hdr] 设置失败" << name << "=" << value
                             << "rc=" << rc;
    }
}

void MpvWindow::setHdrMode(bool hdr, bool hlg) {
    qInfo().noquote() << "[hdr] setHdrMode hdr=" << hdr << "hlg=" << hlg;
    hdrRequested_ = hdr;
    applyHdrOptions(hdr, hlg);
}

int MpvWindow::activeTrackIndex(const QString& type) {
    if (mpv_ == nullptr) return -1;
    const QString typeName = mpvTrackType(type);
    mpv_node items[2];
    items[0].format = MPV_FORMAT_STRING;
    items[0].u.string = const_cast<char*>("get_property");
    items[1].format = MPV_FORMAT_STRING;
    items[1].u.string = const_cast<char*>("track-list");
    mpv_node_list cmdList{};
    cmdList.num = 2;
    cmdList.values = items;
    cmdList.keys = nullptr;
    mpv_node cmd;
    cmd.format = MPV_FORMAT_NODE_ARRAY;
    cmd.u.list = &cmdList;
    mpv_node result;
    if (mpv_command_node(mpv_, &cmd, &result) < 0) return -1;
    int ordinal = -1;
    int idx = -1;
    if (result.format == MPV_FORMAT_NODE_ARRAY && result.u.list != nullptr) {
        for (int i = 0; i < result.u.list->num; ++i) {
            // mpv_node 联合体没有 map 成员——NODE_MAP 与 NODE_ARRAY 同用
            // u.list（mpv_node_list，map 靠 keys 字段区分）。
            const mpv_node t = result.u.list->values[i];
            if (t.format != MPV_FORMAT_NODE_MAP || t.u.list == nullptr) continue;
            QString trackType;
            QString trackFile;
            bool selected = false;
            for (int j = 0; j < t.u.list->num; ++j) {
                const char* k = t.u.list->keys[j];
                const mpv_node v = t.u.list->values[j];
                if (strcmp(k, "type") == 0 && v.format == MPV_FORMAT_STRING) {
                    trackType = QString::fromUtf8(v.u.string);
                } else if (strcmp(k, "selected") == 0 &&
                           v.format == MPV_FORMAT_FLAG) {
                    selected = v.u.flag != 0;
                } else if (strcmp(k, "external-filename") == 0 &&
                           v.format == MPV_FORMAT_STRING) {
                    trackFile = QString::fromUtf8(v.u.string);
                }
            }
            if (!danmakuFile_.isEmpty() && trackFile == danmakuFile_) continue;
            if (trackType == typeName) {
                ++idx;
                if (selected) ordinal = idx;
            }
        }
    }
    mpv_free_node_contents(&result);
    return ordinal;
}

/// 680：卸载当前媒体（删除「正在播放的资源」时调用）。
///
/// 【为什么用 stop 而不是只清画面】`stop` 会真正结束 playlist、释放解码器
/// 与缓冲；只 pause 的话画面停在最后一帧，用户会以为「删了但还在播」。
/// 同时清空进度/时长，让 QML 进度条归零。
void MpvWindow::stopPlayback() {
    if (mpv_ == nullptr) return;
    mpv_command_string(mpv_, "stop");
    positionMs_ = 0;
    durationMs_ = 0;
    // 682：**必须同时把 mpv 的 `pause` 属性写成 yes**。
    //
    // 【真机回归：删除在播资源 → 再播其他资源 → 播放/暂停失效】
    // 旧实现只改本地镜像 `paused_ = true`，mpv 的 `pause` 属性还是 `no`。
    // 下一次 `load` 起播后 mpv 在放，QML 读到的 `playerState.paused`
    //（镜像）却是「暂停」→ `togglePause()` 取反 = 又设 `pause=yes`
    // → 用户点一下画面反而停住/点了没反应。
    // 这里把两侧对齐，保证「stop 后 = 真暂停」这个不变量成立。
    mpv_set_property_string(mpv_, "pause", "yes");
    paused_ = true;
    hasMedia_ = false;
    // 弹幕轨随媒体一起清掉（否则残留在次字幕轨上）
    setDanmakuAss(QString());
    emit positionChanged(0, 0);
    emit pausedChanged(true);
    qInfo() << "[mpv] stop：媒体已卸载（删除在播资源）";
}

void MpvWindow::load(const QString& url,
                     const QMap<QString, QString>& headers,
                     int startMs) {
    if (mpv_ == nullptr || url.isEmpty()) return;

    // Emby 鉴权：mpv 支持 http-header-fields，但真机验证过 header 传递
    // 不可靠（v1.2.77），所以优先用 URL 里的 api_key 参数。这里两者都给，
    // 由 Flutter 侧决定 URL 是否已带 api_key。
    if (!headers.isEmpty()) {
        QStringList fields;
        for (auto it = headers.constBegin(); it != headers.constEnd(); ++it) {
            fields << QStringLiteral("%1: %2").arg(it.key(), it.value());
        }
        mpv_set_option_string(mpv_, "http-header-fields",
                              fields.join(QLatin1String(",")).toUtf8().constData());
    }

    const QByteArray u = url.toUtf8();
    // 691：**回到最简 loadfile**。
    //
    // 【真机回归：点继续观看一直黑屏】690 试图用 `loadfile` 的
    // `start=12.345` 字符串选项传起点——但 `mpv_command` **不接受选项
    // 字符串**（options 必须走 `mpv_command_node` 的 NODE_MAP），命令
    // 失败 → 无媒体 → 黑屏。
    //
    // 现在改为：load 保持最简形式，起点在 `FILE_LOADED` 事件里补 seek
    //（那时媒体已就绪，seek 一定生效）。
    const char* cmd[] = {"loadfile", u.constData(), nullptr};
    const int rc = mpv_command(mpv_, cmd);
    if (rc < 0) {
        lastError_ = QStringLiteral("loadfile 失败: %1")
                         .arg(QString::fromUtf8(mpv_error_string(rc)));
        qWarning().noquote() << "[mpv]" << lastError_;
        return;
    }

    // 691：记下起点，`FILE_LOADED` 时补 seek。
    pendingStartMs_ = startMs > 0 ? startMs : 0;

    // 682：**新资源必须显式起播**。
    //
    // 【为什么】mpv 的 `pause` 属性是**跨 loadfile 保持**的——上一条媒体被
    // `stopPlayback()` 置成 `pause=yes` 后，下一次 `loadfile` 会**继承
    // 暂停态**（画面停在首帧、进度不走）。Dart 侧 `prepare()` 语义是
    // 「加载即播放」，所以这里必须把两侧同时拉回 playing。
    hasMedia_ = true;
    mpv_set_property_string(mpv_, "pause", "no");
    if (paused_) {
        paused_ = false;
        emit pausedChanged(false);
    }
    qInfo().noquote() << "[mpv] load：新媒体已起播"
                      << (startMs > 0 ? QStringLiteral(" start=%1ms").arg(startMs)
                                      : QString());
}

void MpvWindow::setPaused(bool paused) {
    if (mpv_ == nullptr) return;
    mpv_set_property_string(mpv_, "pause", paused ? "yes" : "no");
}

void MpvWindow::togglePause() {
    setPaused(!paused_);
}

void MpvWindow::selectTrack(const QString& type, int index) {
    if (mpv_ == nullptr) return;
    // 664：切轨此前两头都断（QML→Flutter→适配器发回的 selectAudio/
    // selectSubtitle 命令无人处理）。现在 QML 直驱本地 mpv：
    // 序号 = NativePlayerState 轨道列表序号（Emby id-1）→ 按 `track-list`
    // 同类型第 index 项映射到 mpv 轨道 id。
    const QString typeName = mpvTrackType(type);
    const char* prop = typeName == QLatin1String("sub") ? "sid" : "aid";
    if (index < 0) {
        mpv_set_property_string(mpv_, prop, "no");
        return;
    }
    mpv_node node{};
    if (mpv_get_property(mpv_, "track-list", MPV_FORMAT_NODE, &node) < 0) {
        return;
    }
    int nth = -1;
    int targetId = -1;
    if (node.format == MPV_FORMAT_NODE_ARRAY && node.u.list != nullptr) {
        for (int i = 0; i < node.u.list->num; ++i) {
            const mpv_node& item = node.u.list->values[i];
            if (item.format != MPV_FORMAT_NODE_MAP || item.u.list == nullptr) {
                continue;
            }
            QString itemType;
            QString itemFile;
            int id = -1;
            for (int j = 0; j < item.u.list->num; ++j) {
                const char* k = item.u.list->keys[j];
                const mpv_node& v = item.u.list->values[j];
                if (qstrcmp(k, "type") == 0 && v.format == MPV_FORMAT_STRING) {
                    itemType = QString::fromUtf8(v.u.string);
                } else if (qstrcmp(k, "id") == 0 &&
                           v.format == MPV_FORMAT_INT64) {
                    id = static_cast<int>(v.u.int64);
                } else if (qstrcmp(k, "external-filename") == 0 &&
                           v.format == MPV_FORMAT_STRING) {
                    itemFile = QString::fromUtf8(v.u.string);
                }
            }
            if (itemType != typeName) continue;
            // 676：弹幕轨是 sub-add 进来的外部字幕，**不计入**面板序号
            //（否则序号整体错位，选到的不是用户点的字幕）
            if (!danmakuFile_.isEmpty() && itemFile == danmakuFile_) continue;
            ++nth;
            if (nth == index) {
                targetId = id;
                break;
            }
        }
    }
    mpv_free_node_contents(&node);
    if (targetId > 0) {
        mpv_set_property_string(mpv_, prop,
                                QByteArray::number(targetId).constData());
    } else {
        qWarning() << "[mpv] selectTrack 未找到" << type << "#" << index;
    }
}

void MpvWindow::toggleHostFullscreen() {
    setHostFullscreen(!isHostFullscreen());
}

bool MpvWindow::isHostFullscreen() const {
    return host_ != nullptr && host_->visibility() == QWindow::FullScreen;
}

void MpvWindow::setHostFullscreen(bool fullscreen) {
    if (host_ == nullptr) return;
    const bool wasFull = isHostFullscreen();
    if (fullscreen == wasFull) return;

    if (fullscreen) {
        // 【677】进全屏前记住并排矩形：退全屏要显式回到这里，
        // `showNormal()` 恢复的是 Qt 内部记忆的 normalGeometry
        //（房间并排是外部改的几何，Qt 并不知道）→ 会与 Flutter
        // 面板重叠/错位（用户明确要求「房间模式全屏别出问题」）。
        //
        // 取**当前几何**而不是上次下发的矩形：用户可能手动拖过窗口，
        // 当前几何才是视觉上「刚才那个并排位置」。所以每次进全屏都
        // 重新记录（不是只在首次）。
        splitRect_ = host_->geometry();
        hasSplitRect_ = !splitRect_.isEmpty();
        host_->showFullScreen();
    } else {
        host_->showNormal();
        // 显式回到并排矩形（覆盖 showNormal 的恢复值）。
        if (hasSplitRect_ && !splitRect_.isEmpty()) {
            // 679：程序性移动——屏蔽 geometryChanged 回传（防双向死循环）
            applyingProgrammaticGeometry_ = true;
            host_->setGeometry(splitRect_);
            applyingProgrammaticGeometry_ = false;
            // 677：同步跟随缓存——否则下一拍 followParentOnce 会认为
            // 「矩形变了」再设一次（视觉无差异，但会多一次重绘/闪烁）。
            lastFollowRect_ = splitRect_;
        }
    }
    emit hostFullscreenChanged();
}

void MpvWindow::setWindowRect(int x, int y, int w, int h) {
    if (host_ == nullptr) return;
    if (w <= 0 || h <= 0) return;
    const QRect next(x, y, w, h);
    // 【677】相同矩形直接忽略——Dart 面板刷新会重发摆位命令，
    // 不去重会导致「面板一刷新就把全屏顶掉」（用户选了自动退全屏，
    // 但那只应发生在**布局真的变了**的时候）。
    if (hasSplitRect_ && splitRect_ == next) {
        // 全屏中收到相同矩形：保持全屏，只更新记录。
        splitRect_ = next;
        return;
    }
    // 全屏中收到**不同**矩形 → 自动退全屏再应用（用户明确要求）。
    if (isHostFullscreen()) {
        qInfo().noquote() << "[window] 全屏中收到新摆位 → 自动退全屏"
                          << next;
        host_->showNormal();
        emit hostFullscreenChanged();
    }
    splitRect_ = next;
    hasSplitRect_ = true;
    lastFollowRect_ = QRect();  // 让跟随逻辑重新应用一次
    // 679/681：程序性移动——不回传 windowMoved。
    //
    // 【为什么记录 lastUserRect_ 而不是只靠标志位】`setGeometry` 后
    // Qt 的 xChanged/yChanged 可能是**异步投递**的（事件循环），那时
    // applyingProgrammaticGeometry_ 已复位 → 会误判成用户操作回传一次，
    // 触发 Dart 再移面板 → 抖动。把目标矩形记进 lastUserRect_ 后，
    // 几何回调里的 `if (g == lastUserRect_) return;` 会把它过滤掉。
    lastUserRect_ = next;
    applyingProgrammaticGeometry_ = true;
    host_->setGeometry(next);
    applyingProgrammaticGeometry_ = false;
}

void MpvWindow::setFollowParent(bool enabled) {
    followParent_ = enabled;
    if (!enabled) {
        parentHwnd_ = nullptr;
        lastFollowRect_ = QRect();
        return;
    }
    // 开关打开时立即对齐一次（不等 50ms 节拍）。
    followParentOnce();
}

void MpvWindow::requestSplitLayout(int panelWidth, int minVideoWidth) {
    // 用本窗所在屏的工作区（多屏/DPI 权威值）。
    QScreen* screen = nullptr;
    if (host_ != nullptr) screen = host_->screen();
    if (screen == nullptr) screen = QGuiApplication::primaryScreen();
    if (screen == nullptr) {
        emit splitLayoutReady(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, false);
        return;
    }
    const QRect work = screen->availableGeometry();
    if (panelWidth <= 0) panelWidth = 380;
    if (minVideoWidth <= 0) minVideoWidth = 480;

    // 682：**进房间不铺满整屏**（真机回归「初始窗口太大」）。
    //
    // 旧实现 videoW + panel = 工作区全宽、高度 = 工作区全高 → 一进房
    // 整块屏幕被两窗吃满，观感像被强行最大化。改为按工作区缩比居中：
    //   - 总宽 = min(工作区宽, kSplitMaxWidth)，再乘 kSplitWidthRatio
    //   - 总高 = 工作区高 × kSplitHeightRatio
    // 上限 kSplitMaxWidth 保证 4K 屏上不会变成巨幕。
    const int capW = qMin(work.width(), kSplitMaxWidth);
    int totalW = qMax(qRound(capW * kSplitWidthRatio),
                      panelWidth + minVideoWidth);
    totalW = qMin(totalW, work.width());
    int totalH = qRound(work.height() * kSplitHeightRatio);
    totalH = qMax(totalH, kMinHeight);
    totalH = qMin(totalH, work.height());
    const int originX = work.left() + (work.width() - totalW) / 2;
    const int originY = work.top() + (work.height() - totalH) / 2;

    int panel = panelWidth;
    // 总宽不超屏：放不下就压缩面板（下限 320 = Dart 侧 setMinimumSize），
    // 仍放不下则放弃并排。
    if (panel + minVideoWidth > totalW) {
        panel = totalW - minVideoWidth;
    }
    const int videoW = totalW - panel;
    if (panel < kMinPanelWidth || videoW < minVideoWidth) {
        qWarning().noquote() << "[split] 工作区放不下双窗:" << work;
        emit splitLayoutReady(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, false);
        return;
    }
    const int videoX = originX;
    const int panelX = originX + videoW;
    // 主窗最大宽度 = 工作区宽 - Qt 最小宽（连最大化按钮一起受限）
    const int maxPanelW = qMax(panel, work.width() - minVideoWidth);
    qInfo().noquote() << "[split] 并排布局 work=" << work
                      << "origin=" << originX << "," << originY
                      << "totalW=" << totalW << "totalH=" << totalH
                      << "panelW=" << panel << "videoW=" << videoW;
    emit splitLayoutReady(panelX, originY, panel, totalH, videoX, originY,
                          videoW, totalH, maxPanelW, work.height(), true);
}

void MpvWindow::raiseToFront() {
    if (host_ == nullptr) return;
    const HWND h = reinterpret_cast<HWND>(host_->winId());
    if (h == nullptr) return;
    // 683：**只用 HWND_TOP，绝不 HWND_TOPMOST**。
    // `HWND_TOP` 把窗口放到「非置顶层」最前——正常压住别的软件一次，
    // 但用户切走后就自然被盖住（用户要的「灵活」）。置顶会永久压住
    // 别人，已被明确否掉。
    ::SetWindowPos(h, HWND_TOP, 0, 0, 0, 0,
                   SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW);
    ::SetForegroundWindow(h);
    host_->requestActivate();
}

/// 687：按房间态切换窗口边框。
///
/// 【单人】恢复标准可缩放窗口：标题栏 + 最小化/最大化/关闭三钮。
/// 【房间】去掉标题栏与三钮（退出统一走 Flutter 面板窗的确认流程）。
///
/// 只改 `GWL_STYLE` 位，不重建窗口——播放不中断、`wid` 绑定不变。
void MpvWindow::setRoomChrome(bool room) {
    if (host_ == nullptr) return;
    const HWND h = reinterpret_cast<HWND>(host_->winId());
    if (h == nullptr) return;

    const LONG_PTR kCaption = WS_CAPTION | WS_SYSMENU | WS_THICKFRAME |
                              WS_MINIMIZEBOX | WS_MAXIMIZEBOX;
    LONG_PTR style = ::GetWindowLongPtrW(h, GWL_STYLE);
    const LONG_PTR next = room ? (style & ~kCaption) : (style | kCaption);
    if (next == style) return;  // 幂等：无变化不折腾

    ::SetWindowLongPtrW(h, GWL_STYLE, next);
    // 【必须发 FRAMECHANGED】改完 style 后非客户区不会自动重绘——
    // 三钮要等下次窗口显隐才出现（真机观感「改了没生效」）。
    ::SetWindowPos(h, nullptr, 0, 0, 0, 0,
                   SWP_FRAMECHANGED | SWP_NOMOVE | SWP_NOSIZE |
                       SWP_NOZORDER | SWP_NOACTIVATE);
    qInfo().noquote() << "[window] 边框:" << (room ? "无边框（房间）"
                                                   : "标准窗口（单人）");
}

/// 683：与 Flutter 面板窗**联动抬升**（房间并排，两窗同层）。
///
/// 【与 682 置顶的区别】
///   - 682：`HWND_TOPMOST` → 永久压在所有软件之上（用户否掉）
///   - 683：`HWND_TOP`    → 只在被点击/激活时抬到非置顶层最前，
///                          用户切到别的软件时两窗一起被正常盖住
///
/// 关键在「一起」：本窗抬升后发 `userWindowMoved`-同级信号让 Dart 把
/// 面板也抬上来，于是两窗在 z-order 里始终相邻，不会出现「一个在前面
/// 一个在后面」的割裂观感。
void MpvWindow::raiseTogether() {
    if (host_ == nullptr) return;
    const HWND h = reinterpret_cast<HWND>(host_->winId());
    if (h == nullptr) return;
    ::SetWindowPos(h, HWND_TOP, 0, 0, 0, 0,
                   SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
    // 通知 Dart：Qt 窗被抬升 → 面板也跟着抬（两窗同层）。
    emit raisedToFront();
}

/// 682→683：置顶开关已废弃。
///
/// 【为什么保留】旧版 Dart 仍可能发 `setTopmost` 命令；保留为**只记
/// 状态、不改层级**的 no-op，避免旧包与新 Qt 混用时出现未知命令。
/// 真正的层级控制改走 [raiseTogether]。
void MpvWindow::setTopmost(bool topmost) {
    // 只记录「是否处于并排联动模式」，绝不改窗口 z-order 属性。
    topmost_ = topmost;
    qInfo().noquote() << "[window] 并排联动模式:" << (topmost ? "on" : "off");
}

void MpvWindow::setWindowVisible(bool visible) {
    if (host_ == nullptr) return;
    // 【678】只 hide/show 宿主窗：mpv 子窗口随父窗显隐，解码状态不中断
    //（最小化会触发 mpv 停渲染，恢复时黑屏一瞬）。
    host_->setVisible(visible);
    if (visible) {
        host_->requestActivate();
        raiseToFront();
    }
}

// ── 679：无边框窗口的拖动 / 拉伸 ─────────────────────────────

void MpvWindow::startSystemMove() {
    if (host_ == nullptr) return;
    // 680：拖动期间挂起「跟随 Flutter 窗」的托管——否则 50ms 后就被拽回
    // 原位，用户根本拖不动（真机回归「拖 Qt 窗面板不跟随」的根因）。
    suspendFollowForUserGesture();
    // Qt 6.5+ 的 QWindow::startSystemMove：交给系统做原生拖动
    //（带 DWM 吸附、半屏贴靠），比自算 mouseMove 稳。
    host_->startSystemMove();
}

void MpvWindow::startSystemResize(int edges) {
    if (host_ == nullptr) return;
    Qt::Edges e;
    if (edges & 1) e |= Qt::LeftEdge;
    if (edges & 2) e |= Qt::TopEdge;
    if (edges & 4) e |= Qt::RightEdge;
    if (edges & 8) e |= Qt::BottomEdge;
    if (e == Qt::Edges()) return;
    suspendFollowForUserGesture();
    host_->startSystemResize(e);
}

/// 680：用户开始拖动/拉伸 → 挂起跟随，并在停手 400ms 后自动恢复。
///
/// 【为什么 400ms】系统拖动没有「结束」事件（`QWindow` 不提供），只能靠
/// 几何变化停止来判定。拖动中每次几何变化都会续期，真正停手后 400ms
/// 才恢复——足够覆盖 DWM 吸附/半屏贴靠的延迟。
void MpvWindow::suspendFollowForUserGesture() {
    followParentSuspended_ = true;
    if (suspendResumeTimer_ == nullptr) {
        suspendResumeTimer_ = new QTimer(this);
        suspendResumeTimer_->setSingleShot(true);
        connect(suspendResumeTimer_, &QTimer::timeout, this, [this]() {
            followParentSuspended_ = false;
            qInfo() << "[follow] 用户操作结束 → 恢复跟随托管";
            // 【680 真机回归：拖完 Qt 窗后 Flutter 面板没跟过来】
            // 这里**不能**调 `followParentOnce()` —— 那是「Qt 跟随
            // Flutter」，会把用户刚拖走的 Qt 窗拽回 Flutter 窗左侧
            //（方向反了，观感就是「拖了没用」）。
            //
            // 正确做法：把**当前**几何回传一次，让 Dart 侧把 Flutter
            // 面板窗贴到 Qt 的右侧并等高（双向跟随的另一半）。
            if (host_ != nullptr) {
                const QRect g = host_->geometry();
                lastUserRect_ = g;
                emit userWindowMoved(g.x(), g.y(), g.width(), g.height());
            }
        });
    }
    suspendResumeTimer_->start(400);
}

/// 677：定位 Flutter 主窗。
///
/// 【判据三件套】同进程（`--parent-pid`）+ 类名
/// `FLUTTER_RUNNER_WIN32_WINDOW`（`windows/runner/win32_window.cpp` 的
/// 注册名）+ 顶层可见。只认类名会误伤其它 Flutter 应用，只认 pid 会
/// 在 pid 复用后认错窗口，三者组合才唯一。
HWND MpvWindow::findParentWindow() {
    if (parentPid_ <= 0) return nullptr;
    if (parentHwnd_ != nullptr && ::IsWindow(parentHwnd_)) {
        return parentHwnd_;
    }
    parentHwnd_ = nullptr;
    struct Ctx {
        DWORD pid;
        HWND found;
    } ctx{static_cast<DWORD>(parentPid_), nullptr};

    ::EnumWindows(
        [](HWND hwnd, LPARAM lp) -> BOOL {
            auto* c = reinterpret_cast<Ctx*>(lp);
            DWORD pid = 0;
            ::GetWindowThreadProcessId(hwnd, &pid);
            if (pid != c->pid) return TRUE;
            if (!::IsWindowVisible(hwnd)) return TRUE;
            wchar_t cls[128] = {};
            ::GetClassNameW(hwnd, cls, 128);
            if (QString::fromWCharArray(cls) !=
                QLatin1String("FLUTTER_RUNNER_WIN32_WINDOW")) {
                return TRUE;
            }
            // 只认「有尺寸的顶层窗」（跳过 Flutter 的隐藏辅助窗）。
            RECT rc = {};
            ::GetWindowRect(hwnd, &rc);
            if (rc.right - rc.left <= 0 || rc.bottom - rc.top <= 0) {
                return TRUE;
            }
            c->found = hwnd;
            return FALSE;  // 找到即停
        },
        reinterpret_cast<LPARAM>(&ctx));

    parentHwnd_ = ctx.found;
    if (parentHwnd_ != nullptr) {
        qInfo().noquote() << "[follow] 已定位 Flutter 主窗 hwnd="
                          << reinterpret_cast<quintptr>(parentHwnd_);
    }
    return parentHwnd_;
}

/// 677：房间并排跟随——本窗占满「Flutter 主窗左侧剩余区域」。
///
/// 【为什么由 Qt 自己做】拖动/缩放/移动/最大化/跨屏/DPI 变化全部自动
/// 覆盖，零 IPC 流量、无需节流。Dart 只管把自己的窗缩到右侧固定宽，
/// Qt 只看 Flutter 窗的左边缘。
void MpvWindow::followParentOnce() {
    if (!followParent_ || host_ == nullptr) return;
    // 680：用户正在拖动/拉伸 → 暂停托管（否则会把他拖走的窗口拽回来）
    if (followParentSuspended_) return;
    // 全屏时覆盖 Flutter 窗（用户明确例外），不跟随。
    if (isHostFullscreen()) return;

    const HWND parent = findParentWindow();
    if (parent == nullptr) return;
    if (::IsIconic(parent)) return;  // 最小化：保持上一有效矩形

    // DwmGetWindowAttribute 取**真实可见边界**：GetWindowRect 含 Win10/11
    // 的不可见边框与阴影（左右各多出 7~8px），两窗会重叠一条缝。
    RECT frame = {};
    if (FAILED(::DwmGetWindowAttribute(parent, DWMWA_EXTENDED_FRAME_BOUNDS,
                                       &frame, sizeof(frame)))) {
        ::GetWindowRect(parent, &frame);
    }

    // 物理像素 → 逻辑像素：Qt 6 的 QScreen 几何是逻辑像素，
    // GetWindowRect 是物理像素；不换算在 150%/200% 缩放下会偏出一截。
    const QRect parentPhysical(frame.left, frame.top,
                               frame.right - frame.left,
                               frame.bottom - frame.top);
    QScreen* screen = QGuiApplication::screenAt(parentPhysical.center());
    if (screen == nullptr) screen = QGuiApplication::primaryScreen();
    if (screen == nullptr) return;
    const qreal dpr = screen->devicePixelRatio();
    if (dpr <= 0) return;

    const QRect parentLogical(
        qRound(parentPhysical.x() / dpr), qRound(parentPhysical.y() / dpr),
        qRound(parentPhysical.width() / dpr),
        qRound(parentPhysical.height() / dpr));
    const QRect work = screen->availableGeometry();

    // ── 677：高度**跟随 Flutter 窗**（不再固定工作区全高）──
    //
    // 【真机回归】旧实现纵向恒取 `work.top()/work.height()`，而 Flutter
    // 面板窗是自身高度 → 用户缩放面板高度时两窗下缘不齐（截图：Qt 比
    // 面板矮一截 / 高出一截）。现在取 Flutter 窗的 top/bottom，再夹紧到
    // 工作区内（面板贴边时不会越出任务栏）。
    const int top = qMax(parentLogical.top(), work.top());
    const int bottom = qMin(parentLogical.bottom(), work.bottom());
    const int h = bottom - top;
    if (h < kMinHeight) return;  // 太矮：保持上一有效矩形（不闪不叠）

    // ── 677：宽度**不撑大**（撑大会越过 Flutter 窗左缘 → 两窗堆叠）──
    //
    // 【真机回归】旧实现把 w 强行撑到最小宽：用户把面板窗左缘拖到 335
    // 时，w=335 < 480 被撑到 480，而面板从 335 开始 → **重叠 145px**
    //（截图：面板压在视频上）。
    // 现在：不足最小宽就**保持上一有效矩形不动**，等用户拖回来。
    const int left = work.left();
    const int right = qMin(parentLogical.left(), work.right());
    const int w = right - left;
    if (w < kMinWidth) return;
    if (w <= 0) return;

    const QRect next(left, top, w, h);
    if (next == lastFollowRect_) return;  // 变化才动（零抖动）
    lastFollowRect_ = next;
    splitRect_ = next;
    hasSplitRect_ = true;
    // 679：跟随是程序性移动——不回传 windowMoved（否则死循环）
    applyingProgrammaticGeometry_ = true;
    host_->setGeometry(next);
    applyingProgrammaticGeometry_ = false;
}

bool MpvWindow::command(const QStringList& args) {
    if (mpv_ == nullptr || args.isEmpty()) return false;
    QVector<QByteArray> storage;
    storage.reserve(args.size() + 1);
    for (const QString& s : args) storage.append(s.toUtf8());
    QVector<const char*> argv;
    argv.reserve(storage.size() + 1);
    for (const QByteArray& b : storage) argv.append(b.constData());
    argv.append(nullptr);
    // 注意用 data()（非 const）：mpv_command 签名是 const char**，
    // constData() 的 const char* const* 在 MSVC 下转换不过去。
    const int rc = mpv_command(mpv_, argv.data());
    if (rc < 0) {
        qWarning().noquote() << "[mpv] command 失败:"
                             << QString::fromUtf8(mpv_error_string(rc));
    }
    return rc >= 0;
}

void MpvWindow::setDanmakuAss(const QString& assText) {
    if (mpv_ == nullptr) return;
    // 移除旧弹幕轨（次字幕轨）
    if (danmakuSubId_ > 0) {
        command({QStringLiteral("sub-remove"),
                 QString::number(danmakuSubId_)});
        danmakuSubId_ = -1;
    }
    if (assText.isEmpty()) return;

    // 写临时 ASS（每次新文件：mpv 不重载同路径文件）
    const QString dir =
        QStandardPaths::writableLocation(QStandardPaths::TempLocation);
    static int seq = 0;
    danmakuFile_ = dir + QStringLiteral("/himi_danmaku_%1_%2.ass")
                           .arg(QCoreApplication::applicationPid())
                           .arg(++seq);
    QFile f(danmakuFile_);
    if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        qWarning() << "[mpv] 弹幕 ASS 写入失败" << danmakuFile_;
        return;
    }
    f.write(assText.toUtf8());
    f.close();

    // 【676】记录用户当前主字幕轨，加轨后恢复。
    //
    // 旧实现 `sub-add <file> select` 会把**主字幕**切到弹幕轨——弹幕
    // 每次重建（新弹幕到达 / 调节滑杆）都重来一遍，用户选的字幕就
    // 反复"消失"（真机回归「字幕选中没显示字幕」的第二层根因）。
    int64_t sidBefore = -1;
    mpv_get_property(mpv_, "sid", MPV_FORMAT_INT64, &sidBefore);
    const auto restoreSid = [this, sidBefore]() {
        mpv_set_property_string(mpv_, "sid",
                                sidBefore >= 0
                                    ? QByteArray::number(sidBefore).constData()
                                    : "no");
    };
    // 不带 select：新轨只加入 track-list，不改变 sid
    if (!command({QStringLiteral("sub-add"), danmakuFile_})) {
        return;
    }
    // 新轨挂为**次字幕轨**（secondary-sid）：主字幕与弹幕同时渲染
    // （mpv 0.37+ 双字幕轨；wid 直出下 ASS 是唯一浮绘通道）。
    mpv_node node{};
    if (mpv_get_property(mpv_, "track-list", MPV_FORMAT_NODE, &node) < 0) {
        // 676：拿不到 track-list 也要把用户主字幕还回去
        restoreSid();
        return;
    }
    if (node.format == MPV_FORMAT_NODE_ARRAY && node.u.list != nullptr) {
        for (int i = 0; i < node.u.list->num; ++i) {
            const mpv_node& item = node.u.list->values[i];
            if (item.format != MPV_FORMAT_NODE_MAP || item.u.list == nullptr) {
                continue;
            }
            QString type, file;
            int id = -1;
            for (int j = 0; j < item.u.list->num; ++j) {
                const char* k = item.u.list->keys[j];
                const mpv_node& v = item.u.list->values[j];
                if (v.format != MPV_FORMAT_STRING && qstrcmp(k, "id") != 0) {
                    continue;
                }
                if (qstrcmp(k, "type") == 0) {
                    type = QString::fromUtf8(v.u.string);
                } else if (qstrcmp(k, "id") == 0 &&
                           v.format == MPV_FORMAT_INT64) {
                    id = static_cast<int>(v.u.int64);
                } else if (qstrcmp(k, "external-filename") == 0) {
                    file = QString::fromUtf8(v.u.string);
                }
            }
            if (type == QLatin1String("sub") && file == danmakuFile_) {
                danmakuSubId_ = id;
                break;
            }
        }
    }
    mpv_free_node_contents(&node);
    if (danmakuSubId_ > 0) {
        mpv_set_property_string(mpv_, "secondary-sid",
                                QByteArray::number(danmakuSubId_)
                                    .constData());
    }
    // 恢复用户主字幕选中（sid），弹幕只走次字幕轨
    restoreSid();
}

void MpvWindow::setVolume(double volume) {
    if (mpv_ == nullptr) return;
    const double clamped = qBound(0.0, volume, 1.0);
    mpv_set_property_string(
        mpv_, "volume",
        QByteArray::number(static_cast<int>(clamped * 100.0)).constData());
}

void MpvWindow::setSpeed(double speed) {
    if (mpv_ == nullptr) return;
    mpv_set_property_string(mpv_, "speed",
                            QByteArray::number(speed, 'f', 3).constData());
}

void MpvWindow::seekTo(qint64 positionMs) {
    if (mpv_ == nullptr) return;
    const double seconds = positionMs / 1000.0;
    mpv_set_property_string(mpv_, "time-pos",
                            QByteArray::number(seconds, 'f', 3).constData());
}

void MpvWindow::setProperty(const QString& name, const QString& value) {
    if (mpv_ == nullptr || name.isEmpty()) return;
    const int rc = mpv_set_property_string(mpv_, name.toUtf8().constData(),
                                           value.toUtf8().constData());
    if (rc < 0) {
        qWarning().noquote()
            << "[mpv] setProperty 失败:" << name << value
            << QString::fromUtf8(mpv_error_string(rc));
    } else if (name.startsWith(QLatin1String("sub-")) &&
               name != QLatin1String("sub-add") &&
               name != QLatin1String("sub-remove")) {
        // 676：字幕三键成功落值日志（限流 500ms）——复测时一眼确认
        // 「滑杆 → Dart → IPC → mpv」整条链是否打通。
        static qint64 lastLogMs = 0;
        const qint64 now = QDateTime::currentMSecsSinceEpoch();
        if (now - lastLogMs >= 500) {
            lastLogMs = now;
            qInfo().noquote() << "[mpv] 字幕属性" << name << "=" << value;
        }
    }
}

bool MpvWindow::hdrOutput() const {
    const QString g = outGamma_.toLower();
    const QString p = outPrimaries_.toLower();
    return (g == QLatin1String("pq") || g == QLatin1String("hlg")) &&
           (p == QLatin1String("bt.2020") || p == QLatin1String("bt2020"));
}

QString MpvWindow::videoOutputActual() const {
    if (outGamma_.isEmpty()) return QStringLiteral("未知");
    return hdrOutput() ? QStringLiteral("HDR 直出 (%1/%2)")
                             .arg(outPrimaries_, outGamma_)
                       : QStringLiteral("SDR (%1/%2)")
                             .arg(outPrimaries_, outGamma_);
}

void MpvWindow::pumpEvents() {
    if (mpv_ == nullptr) return;
    syncGeometry();

    bool positionDirty = false;
    bool pausedDirty = false;

    while (true) {
        mpv_event* event = mpv_wait_event(mpv_, 0);
        if (event->event_id == MPV_EVENT_NONE) break;

        switch (event->event_id) {
            case MPV_EVENT_PROPERTY_CHANGE: {
                auto* prop = static_cast<mpv_event_property*>(event->data);
                if (prop == nullptr || prop->name == nullptr) break;
                const QString name = QString::fromUtf8(prop->name);

                if (name == QLatin1String("video-out-params") &&
                    prop->format == MPV_FORMAT_NODE && prop->data != nullptr) {
                    auto* node = static_cast<mpv_node*>(prop->data);
                    outPrimaries_ = nodeString(*node, "primaries");
                    outGamma_ = nodeString(*node, "gamma");
                    qInfo().noquote()
                        << QStringLiteral("[hdr] 实际输出 %1").arg(
                               videoOutputActual());
                    emit firstFrameRendered();
                } else if (name == QLatin1String("pause") &&
                           prop->format == MPV_FORMAT_FLAG &&
                           prop->data != nullptr) {
                    paused_ = *static_cast<int*>(prop->data) != 0;
                    pausedDirty = true;
                } else if (name == QLatin1String("time-pos") &&
                           prop->format == MPV_FORMAT_DOUBLE &&
                           prop->data != nullptr) {
                    positionMs_ =
                        static_cast<qint64>(*static_cast<double*>(prop->data) *
                                            1000.0);
                    positionDirty = true;
                } else if (name == QLatin1String("duration") &&
                           prop->format == MPV_FORMAT_DOUBLE &&
                           prop->data != nullptr) {
                    durationMs_ =
                        static_cast<qint64>(*static_cast<double*>(prop->data) *
                                            1000.0);
                    positionDirty = true;
                }
                break;
            }
            case MPV_EVENT_FILE_LOADED: {
                // 691：续播定位——**无条件** seek 到目标位置。
                //
                // 【为什么去掉 1.5s 阈值】那是 690 的兜底逻辑（防 `start`
                // 选项已生效时重复跳转）。现在不再传 `start` 选项，这里
                // 是**唯一**的定位点，必须执行——否则偏差小时不补 seek
                // → 从头播。
                if (pendingStartMs_ > 0) {
                    const qint64 target = pendingStartMs_;
                    pendingStartMs_ = 0;
                    seekTo(target);
                    qInfo().noquote() << "[mpv] FILE_LOADED → seek"
                                      << target << "ms";
                }
                break;
            }
            case MPV_EVENT_END_FILE: {
                auto* end = static_cast<mpv_event_end_file*>(event->data);
                if (end != nullptr && end->reason == MPV_END_FILE_REASON_EOF) {
                    emit playbackEnded();
                } else if (end != nullptr &&
                           end->reason == MPV_END_FILE_REASON_ERROR) {
                    lastError_ = QString::fromUtf8(mpv_error_string(end->error));
                    qWarning().noquote() << "[mpv] 播放失败:" << lastError_;
                }
                break;
            }
            default:
                break;
        }
    }

    if (pausedDirty) emit pausedChanged(paused_);
    if (positionDirty) emit positionChanged(positionMs_, durationMs_);
}

LRESULT CALLBACK MpvWindow::VideoWndProc(HWND hwnd, UINT msg, WPARAM wparam,
                                         LPARAM lparam) {
    // 视频窗口不处理输入——控件都在 QML 层（父窗口）。
    // 但双击要能切全屏，所以透传给父窗口处理。
    switch (msg) {
        case WM_LBUTTONDBLCLK:
        case WM_LBUTTONDOWN:
        case WM_LBUTTONUP: {
            HWND parent = ::GetParent(hwnd);
            if (parent != nullptr) {
                ::PostMessageW(parent, msg, wparam, lparam);
                return 0;
            }
            break;
        }
        default:
            break;
    }
    return ::DefWindowProcW(hwnd, msg, wparam, lparam);
}
