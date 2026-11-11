#include "mpv_window.h"

#include <QDateTime>
#include <QDebug>
#include <QFile>
#include <QCoreApplication>
#include <QRectF>
#include <QStandardPaths>
#include <QTimer>
#include <QVariant>
#include <QVector>

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

void MpvWindow::load(const QString& url, const QMap<QString, QString>& headers) {
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
    const char* cmd[] = {"loadfile", u.constData(), nullptr};
    const int rc = mpv_command(mpv_, cmd);
    if (rc < 0) {
        lastError_ = QStringLiteral("loadfile 失败: %1")
                         .arg(QString::fromUtf8(mpv_error_string(rc)));
        qWarning().noquote() << "[mpv]" << lastError_;
    }
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
        restoreSid();
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
    if (host_ == nullptr) return;
    if (host_->visibility() == QWindow::FullScreen) {
        host_->showNormal();
    } else {
        host_->showFullScreen();
    }
}

bool MpvWindow::isHostFullscreen() const {
    return host_ != nullptr && host_->visibility() == QWindow::FullScreen;
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
