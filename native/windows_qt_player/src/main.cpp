#include <QCommandLineParser>
#include <QWinEventNotifier>
#include <QNetworkAccessManager>
#include <QNetworkDiskCache>
#include <QQmlNetworkAccessManagerFactory>
#include <QStandardPaths>
#include <QAbstractEventDispatcher>
#include <QDateTime>
#include <QDebug>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QGuiApplication>
#include <QJsonObject>
#include <QJsonValue>
#include <QKeyEvent>
#include <QObject>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickWindow>
#include <QSGRendererInterface>
#include <QStringList>
#include <QTextStream>
#include <QTimer>
#include <QtGlobal>   // qRound（DPI 换算用）

#include <cstdio>     // stderr（控制台日志）

#include "mpv_window.h"
#include "pipe_server.h"
#include "player_state.h"

namespace {

/// 【673】封面网络磁盘缓存（对齐安卓 NativeLogoLoader 磁盘 LRU）：
/// Emby 海报响应落盘 64MB LRU——重开面板/重启应用秒开，不再每次
/// 全量重新下载（真机回归「选集面板封面加载太慢」）。
class DiskCacheNamFactory : public QQmlNetworkAccessManagerFactory {
public:
    QNetworkAccessManager* create(QObject* parent) override {
        auto* nam = new QNetworkAccessManager(parent);
        auto* cache = new QNetworkDiskCache(nam);
        const QString dir = QStandardPaths::writableLocation(
                                QStandardPaths::CacheLocation) +
                            QStringLiteral("/netcache");
        QDir().mkpath(dir);
        cache->setCacheDirectory(dir);
        cache->setMaximumCacheSize(64 * 1024 * 1024);
        nam->setCache(cache);
        qInfo().noquote() << "[cache] 网络磁盘缓存:" << dir;
        return nam;
    }
};

/// 657.1：把 Qt 日志**同时**写到文件与控制台。
///
/// 【为什么需要文件】Flutter 侧用 `ProcessStartMode.detached` 启动本程序
/// （`detachedWithStdio` 的管道不读会阻塞子进程，656 真机踩过）。
/// 代价是 stdout/stderr 全丢——QML 加载失败、缺 DLL、mpv 初始化失败
/// 都**看不到任何错误**。
///
/// 【为什么还要控制台】658 首版只写文件，导致手动在 PowerShell 跑 exe
/// 时**一行输出都没有**（用户看到「立刻返回」以为没跑）。必须两者都写。
void installLogger() {
    static QFile* logFile = nullptr;
    logFile = new QFile(QCoreApplication::applicationDirPath() +
                        QStringLiteral("/himi_qt_player.log"));
    // 每次启动覆盖（不 append）：只关心本次运行，避免文件无限增长。
    const bool ok = logFile->open(QIODevice::WriteOnly | QIODevice::Truncate |
                                  QIODevice::Text);

    qInstallMessageHandler([](QtMsgType type, const QMessageLogContext&,
                              const QString& msg) {
        const char* level = "INFO";
        switch (type) {
            case QtDebugMsg: level = "DEBUG"; break;
            case QtInfoMsg: level = "INFO"; break;
            case QtWarningMsg: level = "WARN"; break;
            case QtCriticalMsg: level = "CRIT"; break;
            case QtFatalMsg: level = "FATAL"; break;
        }
        const QString line =
            QStringLiteral("%1 [%2] %3")
                .arg(QDateTime::currentDateTime().toString("HH:mm:ss.zzz"),
                     QString::fromLatin1(level), msg);

        // 控制台（手动跑 exe 时看得到）
        QTextStream(stderr) << line << "\n";

        // 文件（Flutter detached 启动时唯一能拿到的证据）
        if (logFile != nullptr && logFile->isOpen()) {
            QTextStream out(logFile);
            out << line << "\n";
            out.flush();   // 秒退也要留下（不依赖析构）
        }
    });

    if (ok) {
        qInfo().noquote() << "=== himi_qt_player 启动 ===";
        qInfo().noquote() << "exe:" << QCoreApplication::applicationDirPath();
    }
}

}  // namespace

/// 656：HIMI Windows 播放器窗口（Qt Quick + libmpv）
///
/// 【定位】Flutter 是唯一逻辑权威。本程序只做：
///   1. mpv 渲染（`wid` 直出，HDR）
///   2. QML 控件（顶栏/底栏/面板）
///   3. 通过 TCP localhost 接收状态、发送命令
///
/// 【启动方式】由 Flutter 的 `Process.start` 拉起，参数：
///   --port   <port>     Flutter 选好的空闲端口
///   --token  <token>    首帧认证用的一次性 token
///   --hdr    1|0
///   --hlg    1|0
///
/// 【不接收 URL 参数】播放地址由 Flutter 通过 IPC 下发（`playUrl` 字段），
/// 因为 Emby 的 URL 可能很长（含 token/MediaSourceId），命令行有长度限制，
/// 且 URL 出现在进程命令行里不安全（任务管理器可见）。
int main(int argc, char* argv[]) {
    // 【669：透明渲染保障】Windows 上逐像素透明的 QQuickWindow 只有
    // D3D11 / 软件 RHI 后端可靠（GL 后端的 alpha 合成时灵时不灵，
    // 真机现象：控件层整窗不可见 = 「没见到控件」）。
    QQuickWindow::setGraphicsApi(QSGRendererInterface::Direct3D11);

    QGuiApplication app(argc, argv);
    QGuiApplication::setApplicationName("HIMI Player");
    QGuiApplication::setOrganizationName("Himi");

    // 必须尽早装：后面任何 qWarning/qCritical 都要落盘。
    installLogger();

    QCommandLineParser parser;
    parser.setApplicationDescription("HIMI Windows 播放器窗口");
    parser.addHelpOption();
    parser.addOption({"port", "IPC 监听端口（Flutter 侧传入）", "port"});
    parser.addOption({"token", "IPC 首帧认证 token", "token"});
    parser.addOption({"hdr", "是否请求 HDR 直出（1/0）", "flag", "1"});
    parser.addOption({"hlg", "内容是否为 HLG（1/0）", "flag", "0"});
    // 【670】CI 冒烟自检：只加载 QML 验证类型/导入正确性即退出 0
    //（抓「ApplicationWindow 不是一种类型」这类运行时加载错误）。
    // 注意：纯开关（无 valueName）——照抄 --hdr 的三参会变成带值选项，
    // 裸 `--selftest` 会 "Missing value" 直接 exit(1)（670 CI 踩过）。
    parser.addOption({"selftest", "QML 加载冒烟自检后退出"});
    // 【670】预热模式：窗口隐藏待命，收到首条 load 命令才弹出；
    // 管道断开自动退出（防孤儿进程）。
    parser.addOption({"prewarm", "隐藏待命模式（启动预热）"});
    // 【676】父进程（Flutter）pid：父进程退出/崩溃/被杀 → 本进程跟随退出
    //（detached 启动不会被父进程带走，缺这个守卫会留孤儿播放窗）。
    parser.addOption({"parent-pid", "父进程 pid（生命周期守卫）", "pid"});
    parser.process(app);

    // ── 676：父进程存活守卫（Qt 进程由 Flutter detached 拉起）──
    // 用 SYNCHRONIZE 句柄 + QWinEventNotifier：父进程一退出立即触发
    //（不轮询、不占 CPU）。正常关闭路径另有一层 Dart 主动 kill。
    qint64 parentPidForFollow = 0;
    {
        bool pidOk = false;
        const qint64 parentPid = parser.value("parent-pid").toLongLong(&pidOk);
        if (pidOk && parentPid > 0) {
            // 677：同一个 pid 也是「房间并排跟随」定位 Flutter 主窗的依据。
            parentPidForFollow = parentPid;
            HANDLE parent = ::OpenProcess(
                SYNCHRONIZE, FALSE, static_cast<DWORD>(parentPid));
            if (parent != nullptr) {
                auto* watcher = new QWinEventNotifier(parent, &app);
                QObject::connect(watcher, &QWinEventNotifier::activated,
                                 &app, []() {
                                     qInfo() << "[lifecycle] 父进程已退出 →"
                                                " Qt 播放器跟随关闭";
                                     QCoreApplication::quit();
                                 });
                qInfo() << "[lifecycle] 父进程守卫已安装 pid=" << parentPid;
            } else {
                qWarning() << "[lifecycle] 父进程守卫安装失败 pid="
                           << parentPid;
            }
        }
    }

    const bool selftest = parser.isSet("selftest");
    const bool prewarm = parser.isSet("prewarm");
    const QString portText = parser.value("port");
    if (!selftest && portText.isEmpty()) {
        qCritical("缺少 --port 参数");
        return -1;
    }
    bool portOk = false;
    const quint16 port = portText.toUShort(&portOk);
    if (!selftest && (!portOk || port == 0)) {
        qCritical("--port 非法");
        return -1;
    }
    const QString token = parser.value("token");
    const bool hdr = parser.value("hdr") != QLatin1String("0");
    const bool hlg = parser.value("hlg") == QLatin1String("1");

    // ── 状态模型 ──
    PlayerState state;

    // ── IPC 服务端 ──
    PipeServer pipe;
    if (!selftest && !pipe.start(port, token)) {
        qCritical("IPC 监听失败");
        return -2;
    }

    // ── mpv 窗口（664：声明提前到 QML load 之前——mpvWindow 上下文
    // 属性必须在 engine.load 前注册，否则 QML 解析不到）──
    MpvWindow mpv;
    // 677：房间并排跟随要定位 Flutter 主窗，pid 必须在 QML 注册前注入。
    if (parentPidForFollow > 0) mpv.setParentPid(parentPidForFollow);

    // ── QML ──
    QQmlApplicationEngine engine;
    // 【673】封面磁盘缓存必须在 load 前装上（Image 网络源走 NAM）
    static DiskCacheNamFactory namFactory;
    engine.setNetworkAccessManagerFactory(&namFactory);
    engine.rootContext()->setContextProperty("playerState", &state);
    engine.rootContext()->setContextProperty("pipeServer", &pipe);
    // 664：QML 直驱本地 mpv（控件本地化 + 视频挖孔）。
    engine.rootContext()->setContextProperty("mpvWindow", &mpv);

    const QUrl qmlUrl(QStringLiteral("qrc:/qt/qml/HimiPlayer/Main.qml"));
    qInfo().noquote() << "[qml] 加载" << qmlUrl.toString();
    // 启动时把 qrc 里实际存在的 QML 列出来：万一别名失效，
    // 一眼就能看出「注册的路径」与「加载的路径」差在哪。
    // 诊断：把 qrc 里实际存在的 QML 列出来。
    //
    // 【为什么探测两个前缀】`RESOURCE_PREFIX` 默认是 `/`，若忘记显式设置
    // 会变成 `qrc:/HimiPlayer/...`，与代码里的 `qrc:/qt/qml/HimiPlayer/...`
    // 不一致（658 真机退出码 -3 就是这么来的）。同时列出两边，一眼能看出
    // 实际用的是哪个。
    {
        for (const char* prefix : {":/qt/qml/HimiPlayer", ":/HimiPlayer"}) {
            QDirIterator it(QString::fromLatin1(prefix),
                            QStringList{QStringLiteral("*.qml")}, QDir::Files,
                            QDirIterator::Subdirectories);
            QStringList found;
            while (it.hasNext()) found << it.next();
            qInfo().noquote()
                << QStringLiteral("[qml] %1 → %2 个文件%3")
                       .arg(QString::fromLatin1(prefix))
                       .arg(found.size())
                       .arg(found.isEmpty()
                                ? QString()
                                : QStringLiteral(": ") +
                                      found.join(QLatin1String(", ")));
        }
    }

    QObject::connect(
        &engine, &QQmlApplicationEngine::objectCreated, &app,
        [qmlUrl](QObject* obj, const QUrl& objUrl) {
            if (!obj && qmlUrl == objUrl) {
                qCritical().noquote()
                    << "[qml] Main.qml 加载失败:" << objUrl.toString()
                    << "—— 检查 CMakeLists 的 QT_RESOURCE_ALIAS 是否生效";
                QCoreApplication::exit(-3);
            }
        },
        Qt::QueuedConnection);
    engine.load(qmlUrl);

    if (engine.rootObjects().isEmpty()) {
        qCritical("[qml] rootObjects 为空，退出");
        return -3;
    }

    auto* host = qobject_cast<QQuickWindow*>(engine.rootObjects().constFirst());
    if (host == nullptr) {
        qCritical("QML 根对象不是 Window");
        return -3;
    }

    // ── mpv ──
    // （MpvWindow 已提前声明在 QML 段之前：mpvWindow 上下文属性需要）
    // 当前已加载的 URL（去重：同一 URL 不重复 loadfile）。
    // 用局部变量而不是 host->property("loadedUrl")——后者会往 QQuickWindow
    // 上挂动态属性，语义不清且 QML 侧也能改到。
    QString loadedUrl;
    QTimer::singleShot(0, &app, [&]() {
        if (!mpv.attach(host, hdr, hlg)) {
            qCritical("mpv 初始化失败");
            QCoreApplication::exit(-4);
            return;
        }
        // 668：视频满铺宿主客户区；控件层在**逐像素透明悬浮窗**
        // （Overlay.qml）——顶层窗口永远盖住子窗口 = 真合成，
        // 玻璃任意半透明、零黑底，HDR 直出路径不变。
        mpv.setOverlayInsets(0, 0);
    });

    // ── 控件悬浮层（668：液态玻璃控件层）──
    //
    // 透明顶层工具窗盖在视频宿主客户区之上；QQuickWindow 默认
    // alphaBuffer 才能得到逐像素透明（Windows 分层窗口合成）。
    QQuickWindow::setDefaultAlphaBuffer(true);
    engine.load(QUrl(QStringLiteral("qrc:/qt/qml/HimiPlayer/Overlay.qml")));
    if (engine.rootObjects().size() < 2) {
        qCritical("[qml] Overlay.qml 加载失败");
        return -5;
    }
    auto* overlay =
        qobject_cast<QQuickWindow*>(engine.rootObjects().constLast());
    if (overlay == nullptr) {
        qCritical("[qml] Overlay 根对象不是 Window");
        return -5;
    }

    // 【669 A1：owned 窗根治 z-order】Win32 规则：owned 窗永远盖在
    // owner 之上、随 owner 一起抬升——控件层结构性压住视频子窗口，
    // 不再赌 50ms 轮询 raise 的时序（真机现象：控件被视频盖住
    // = 「没见到控件 + 点击没反应」）。双保险：
    //   ① setTransientParent（Qt 原生 = 设 owner）
    //   ② GWLP_HWNDPARENT（Win32 直设 owner，幂等）
    overlay->setTransientParent(host);
    overlay->setFlags(Qt::Tool | Qt::FramelessWindowHint);
    overlay->setColor(Qt::transparent);
    ::SetWindowLongPtrW(reinterpret_cast<HWND>(overlay->winId()),
                        GWLP_HWNDPARENT,
                        reinterpret_cast<LONG_PTR>(
                            reinterpret_cast<HWND>(host->winId())));

    // 位置同步：悬浮层恒贴住宿主客户区（拖动/缩放/最小化/全屏）。
    // 50ms 轮询 + 变化才动（无抖动），宿主活跃时 raise 双保险。
    const auto syncOverlayGeometry = [host, overlay]() {
        HWND h = reinterpret_cast<HWND>(host->winId());
        RECT rc = {};
        ::GetClientRect(h, &rc);
        ::MapWindowPoints(h, nullptr, reinterpret_cast<POINT*>(&rc), 2);
        const QRect g(rc.left, rc.top, rc.right - rc.left,
                      rc.bottom - rc.top);
        if (overlay->geometry() != g) overlay->setGeometry(g);
    };
    syncOverlayGeometry();

    // 【669 A4 / 670：自检日志 + 自动降级】窗口/几何/alpha 落日志文件；
    // alphaBuffer 未生效 = 透明合成必失败（控件不可见）→ 自动切
    // SAFE 深底模式（保证控件可见）+ 标题栏诊断码（截图即诊断）。
    const int alphaBits = overlay->format().alphaBufferSize();
    qInfo().noquote() << "[overlay] 创建完成"
                      << "winId=" << Qt::hex << overlay->winId() << Qt::dec
                      << "geometry=" << overlay->geometry()
                      << "alphaBuffer=" << alphaBits
                      << "rhi=" << QSGRendererInterface::Direct3D11;
    if (alphaBits <= 0) {
        qWarning("[overlay] alphaBuffer 未生效 → SAFE 深底降级（保证控件可见）");
        overlay->setProperty("safeMode", true);
        state.setWindowDiag(QStringLiteral("SAFE:alpha0"));
    } else {
        state.setWindowDiag(QStringLiteral("GLASS"));
    }

    // 【670：--selftest】Main + Overlay 两棵 QML 树都创建成功即通过。
    if (selftest) {
        qInfo("[selftest] QML 加载通过（Main + Overlay）");
        return 0;
    }

    // 配置全部就绪后再显示（隐藏创建→配置→显示：防 flags 重建丢 alpha）。
    // 【670】预热模式窗口隐藏待命，收到首条 load 命令再弹出（秒出窗）。
    bool windowsShown = false;
    const auto forceForeground = [host]() {
        // 【671 A2】Windows 前台规则会把新弹出的窗放在 Flutter 窗口
        // 后面（真机回归：「Qt 窗口出现在详情页后面」）——
        // AttachThreadInput 组合拳 + HWND_TOP 强制到最前。
        HWND h = reinterpret_cast<HWND>(host->winId());
        ::SetWindowPos(h, HWND_TOP, 0, 0, 0, 0,
                       SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW);
        const DWORD fgThread =
            ::GetWindowThreadProcessId(::GetForegroundWindow(), nullptr);
        const DWORD myThread = ::GetCurrentThreadId();
        const BOOL attached = (fgThread != myThread)
                && ::AttachThreadInput(fgThread, myThread, TRUE);
        ::SetForegroundWindow(h);
        ::BringWindowToTop(h);
        if (attached) ::AttachThreadInput(fgThread, myThread, FALSE);
        host->requestActivate();
    };
    // 【680：两个窗口都要在任务栏】Qt 播放窗是 `WS_POPUP`（无边框），
    // Win32 默认不给它任务栏图标。三步强制：
    //   ① 清 owner —— 有 owner 的窗口任务栏不显示
    //   ② 加 WS_EX_APPWINDOW —— 让 WS_POPUP 也能进任务栏
    //   ③ SWP_FRAMECHANGED —— 改 exstyle 后必须发这个，任务栏才会立即重算
    //      （不发的话要等下次显隐才更新）
    //
    // 【为什么只对 host 做】控件层 overlay 是 `Qt::Tool`，Win32 本就不给
    // Tool 窗口任务栏图标（它应随宿主走）。Flutter 面板窗是标准 runner
    // 窗口（WS_OVERLAPPEDWINDOW），本来就有图标。
    const auto ensureTaskbarEntry = [host]() {
        if (host == nullptr) return;
        HWND h = reinterpret_cast<HWND>(host->winId());
        if (h == nullptr) return;
        ::SetWindowLongPtrW(h, GWLP_HWNDPARENT, 0);
        const LONG_PTR ex = ::GetWindowLongPtrW(h, GWL_EXSTYLE);
        const LONG_PTR wanted =
            ex | static_cast<LONG_PTR>(WS_EX_APPWINDOW);
        if (wanted != ex) {
            ::SetWindowLongPtrW(h, GWL_EXSTYLE, wanted);
        }
        ::SetWindowPos(h, nullptr, 0, 0, 0, 0,
                       SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER |
                           SWP_NOACTIVATE | SWP_FRAMECHANGED);
        qInfo().noquote() << "[taskbar] Qt 播放窗已加入任务栏 ex="
                          << Qt::hex << wanted << Qt::dec;
    };

    const auto showWindows = [host, overlay, &windowsShown, forceForeground,
                              ensureTaskbarEntry]() {
        if (windowsShown) return;
        windowsShown = true;
        host->show();
        overlay->show();
        // 680：必须在 show() **之后**——窗口创建后 exstyle 才稳定，
        // Qt 在 show 期间可能重置过一次。
        ensureTaskbarEntry();
        overlay->requestActivate();
        forceForeground();
        overlay->raise();
    };
    if (!prewarm) showWindows();

    auto* syncTimer = new QTimer(&app);
    QObject::connect(syncTimer, &QTimer::timeout, &app,
                     [host, overlay, syncOverlayGeometry]() {
        if (host == nullptr || overlay == nullptr) return;
        // QQuickWindow（QWindow）没有 isMinimized()，用 visibility 判定
        const bool show = host->isVisible()
                && host->visibility() != QWindow::Minimized;
        if (overlay->isVisible() != show) {
            qInfo() << "[overlay] 跟随宿主显隐 ->" << show;
            overlay->setVisible(show);
        }
        if (!show) return;
        syncOverlayGeometry();
        if (host->isActive()) overlay->raise();
    });
    syncTimer->start(50);

    // ── 677：Escape 统一拦截（两窗共用一份三层语义）──
    //
    // 【真凶】旧实现两窗各挂一份 `Shortcut { sequence: "Escape" }`：
    // Overlay 有「收面板→退全屏→退出」三层，Main.qml 只有
    // `requestExit + Qt.quit()`。焦点落在宿主窗（点标题栏/视频区）时按
    // Esc，**全屏状态下会直接关掉播放器**（用户要求「房间模式全屏别出
    // 问题」，这条必须先堵）。C++ 拦截后只剩一份语义，且 QML 两处
    // Shortcut 一并删除（防重复触发）。
    struct EscapeFilter : QObject {
        MpvWindow* mpv = nullptr;
        explicit EscapeFilter(MpvWindow* m, QObject* parent)
            : QObject(parent), mpv(m) {}
        bool eventFilter(QObject* obj, QEvent* ev) override {
            Q_UNUSED(obj)
            if (ev->type() != QEvent::KeyPress) return false;
            auto* key = static_cast<QKeyEvent*>(ev);
            if (key->key() != Qt::Key_Escape) return false;
            // 交给 QML 的三层语义（收面板 → 退全屏 → requestExit）。
            mpv->notifyEscape();
            return true;  // 吞掉，防 Qt 默认行为（关窗）
        }
    };
    // parent = &app：随事件循环一起析构，不留悬挂过滤器。
    auto* escapeFilter = new EscapeFilter(&mpv, &app);
    app.installEventFilter(escapeFilter);

    // ── 状态：Flutter → mpv + QML ──
    QObject::connect(&pipe, &PipeServer::stateReceived, &state,
                     [&](const QJsonObject& json) {
                         // 【671 A4】播放镜像字段以本进程 mpv 事件为准：
                         // Flutter 快照（200ms 节流/切集模板）里的
                         // paused/position/duration 是过期值，直接覆盖
                         // 本地补丁会让播放/暂停图标与真实状态失配
                         //（真机回归）。弹幕/轨道/面板数据照常应用。
                         QJsonObject filtered = json;
                         filtered.remove(QStringLiteral("paused"));
                         filtered.remove(QStringLiteral("positionMs"));
                         filtered.remove(QStringLiteral("durationMs"));
                         // remote=true：本地置顶字段（patchValue 写过）
                         // 不被过期快照覆盖（675 A）
                         state.applyJson(filtered, true);
                         // 【不做 loadfile】播放地址只由 `command` 帧的
                         // `load` 指令驱动（单一入口）。
                         //
                         // 曾经这里也读 `playUrl` 直接 load，但那样有两个
                         // 入口：state 推送（20Hz）与 load 命令会竞争，虽然
                         // 有 loadedUrl 去重，但两者时序不共享——state 先到
                         // 时 loadedUrl 已置位，随后 load 命令的 seek(startMs)
                         // 会被当成「同一个 URL」跳过，导致续播位置丢失。
                     });

    // 【670】预热模式：管道断开（Flutter 退出/崩溃）→ 宽限 2 秒未
    // 恢复即退出，防孤儿进程驻留。
    QObject::connect(&pipe, &PipeServer::clientChanged, &app,
                     [&pipe, &app, prewarm](bool connected) {
        if (connected || !prewarm) return;
        QTimer::singleShot(2000, &app, [&pipe, &app]() {
            if (!pipe.hasClient()) {
                qInfo("[prewarm] 管道断开且未恢复，退出");
                QCoreApplication::exit(0);
            }
        });
    });

    // ── 控制指令：Flutter → mpv ──
    QObject::connect(&pipe, &PipeServer::commandReceived, &mpv,
                     [&](const QJsonObject& cmd) {
                         const QString type =
                             cmd.value(QLatin1String("type")).toString();
                         if (type == QLatin1String("load")) {
                             // 【670】首条 load = 媒体就绪 → 预热窗口
                             // 结束待命、弹出（起播窗口秒出的落点）。
                             // 【671】每次 load 都拉前台（换资源/切集后
                             // 窗口不再被 Flutter 盖住）。
                             showWindows();
                             forceForeground();
                             const QString url =
                                 cmd.value(QLatin1String("url")).toString();
                             const qint64 startMs = static_cast<qint64>(
                                 cmd.value(QLatin1String("startMs"))
                                     .toDouble(0));
                             // 【664 真机回归：播不了/黑屏】headers 此前被
                             // 整个丢弃——Emby 流 URL 不带 api_key，鉴权全靠
                             // X-Emby-Token 头（getStreamUrl 实证），mpv 裸
                             // 请求 401 → 永远黑屏 00:00。
                             QMap<QString, QString> headers;
                             const QJsonObject hobj =
                                 cmd.value(QLatin1String("headers"))
                                     .toObject();
                             for (auto it = hobj.constBegin();
                                  it != hobj.constEnd(); ++it) {
                                 headers.insert(it.key(),
                                                it.value().toString());
                             }
                             if (!url.isEmpty()) {
                                 // 同一 URL 不重复 load（切集/续播才换）。
                                 // 但 startMs 仍需应用——续播位置可能变。
                                 if (url != loadedUrl) {
                                     loadedUrl = url;
                                     mpv.load(url, headers);
                                 }
                                 if (startMs > 0) mpv.seekTo(startMs);
                             }
                             // 672：mpv 自选默认轨 → 回填面板默认勾
                             //（延迟等 track-list 就绪）
                             QTimer::singleShot(800, &app,
                                                [&mpv, &state]() {
                                 QJsonObject patch;
                                 patch.insert(
                                     QStringLiteral("selectedAudioId"),
                                     mpv.activeTrackIndex(
                                         QStringLiteral("audio")) + 1);
                                 patch.insert(
                                     QStringLiteral("selectedSubtitleId"),
                                     mpv.activeTrackIndex(
                                         QStringLiteral("subtitle")) + 1);
                                 state.applyJson(patch);
                             });
                         } else if (type == QLatin1String("setPaused")) {
                             mpv.setPaused(
                                 cmd.value(QLatin1String("paused")).toBool());
                         } else if (type == QLatin1String("seekTo")) {
                             mpv.seekTo(static_cast<qint64>(
                                 cmd.value(QLatin1String("positionMs"))
                                     .toDouble(0)));
                         } else if (type == QLatin1String("setVolume")) {
                             mpv.setVolume(
                                 cmd.value(QLatin1String("volume")).toDouble(1.0));
                         } else if (type == QLatin1String("setSpeed")) {
                             mpv.setSpeed(
                                 cmd.value(QLatin1String("speed")).toDouble(1.0));
                         } else if (type == QLatin1String("setProperty")) {
                             // 通用属性透传（HDR 切换等场景）
                             const QString name =
                                 cmd.value(QLatin1String("name")).toString();
                             const QString value =
                                 cmd.value(QLatin1String("value")).toString();
                             if (!name.isEmpty()) {
                                 mpv.setProperty(name, value);
                             }
                         } else if (type == QLatin1String("setHdrMode")) {
                             // 669：HDR 晚绑定——进程提前拉起（起播直接
                             // 弹窗），媒体信息解析完先切 HDR 档再 load。
                             mpv.setHdrMode(
                                 cmd.value(QLatin1String("hdr")).toBool(),
                                 cmd.value(QLatin1String("hlg")).toBool());
                         } else if (type == QLatin1String("selectAudio")) {
                             // 664：切轨命令此前无人处理（两头都断）。
                             // id = Emby 索引 + 1（与 SelectAudio 约定一致），
                             // <=0 关闭。
                             const int id = static_cast<int>(
                                 cmd.value(QLatin1String("id")).toInt(-1));
                             mpv.selectTrack(QStringLiteral("audio"),
                                             id > 0 ? id - 1 : -1);
                             // 672：回填选中真相（面板勾选即时正确）
                             QJsonObject patch;
                             patch.insert(QStringLiteral("selectedAudioId"),
                                          id > 0 ? id : 0);
                             state.applyJson(patch);
                         } else if (type == QLatin1String("selectSubtitle")) {
                             const int id = static_cast<int>(
                                 cmd.value(QLatin1String("id")).toInt(-1));
                             mpv.selectTrack(QStringLiteral("subtitle"),
                                             id > 0 ? id - 1 : -1);
                             // 672：回填选中真相（0 = 关闭字幕）
                             QJsonObject patch;
                             patch.insert(QStringLiteral("selectedSubtitleId"),
                                          id > 0 ? id : 0);
                             state.applyJson(patch);
                         } else if (type ==
                                    QLatin1String("setWindowRect")) {
                             // 677：房间并排摆位（Dart 算矩形、Qt 应用）。
                             // 全屏中收到**不同**矩形 → 自动退全屏；
                             // 相同则忽略（防面板刷新重发误退）。
                             mpv.setWindowRect(
                                 static_cast<int>(cmd.value(QLatin1String("x"))
                                                      .toInt(0)),
                                 static_cast<int>(cmd.value(QLatin1String("y"))
                                                      .toInt(0)),
                                 static_cast<int>(cmd.value(QLatin1String("w"))
                                                      .toInt(0)),
                                 static_cast<int>(cmd.value(QLatin1String("h"))
                                                      .toInt(0)));
                         } else if (type ==
                                    QLatin1String("setFollowParent")) {
                             // 677：房间并排跟随（Qt 自己读 Flutter 主窗
                             // 矩形，拖动/缩放/移动/跨屏/DPI 全自动）。
                             mpv.setFollowParent(
                                 cmd.value(QLatin1String("enabled"))
                                     .toBool(false));
                         } else if (type ==
                                    QLatin1String("requestSplitLayout")) {
                             // 677：房间并排——Qt 用 QScreen 算矩形回传
                             //（多屏/DPI 权威），Dart 应用面板侧。
                             mpv.requestSplitLayout(
                                 static_cast<int>(
                                     cmd.value(QLatin1String("panelWidth"))
                                         .toInt(380)),
                                 static_cast<int>(
                                     cmd.value(QLatin1String("minVideoWidth"))
                                         .toInt(480)));
                         } else if (type == QLatin1String("focus")) {
                             // 677：把播放窗拉回最前（Dart 取消退房时用）。
                             mpv.raiseToFront();
                         } else if (type ==
                                    QLatin1String("setWindowVisible")) {
                             // 678：房间弹窗期间让位（分享/搜索/确认框
                             // 会被顶层 Qt 窗盖住）。
                             mpv.setWindowVisible(
                                 cmd.value(QLatin1String("visible"))
                                     .toBool(true));
                         } else if (type == QLatin1String("stop")) {
                             // 680：删除「正在播放的资源」→ 卸载媒体
                             //（只 pause 会让画面停在最后一帧）
                             mpv.stopPlayback();
                             loadedUrl.clear();
                         } else if (type == QLatin1String("startSystemMove")) {
                             // 679：无边框窗口拖动（顶栏拖拽区）
                             mpv.startSystemMove();                         } else if (type ==
                                    QLatin1String("startSystemResize")) {
                             // 679：无边框窗口边缘拉伸（1=左 2=上 4=右 8=下）
                             mpv.startSystemResize(
                                 static_cast<int>(
                                     cmd.value(QLatin1String("edges"))
                                         .toInt(0)));
                         } else if (type ==
                                    QLatin1String("setHostFullscreen")) {
                             // 677：全屏态可由 Dart 显式驱动（房间并排
                             // 与全屏互斥，摆位时先退全屏）。
                             mpv.setHostFullscreen(
                                 cmd.value(QLatin1String("fullscreen"))
                                     .toBool(false));
                         }
                     });

    // ── 状态：mpv → QML ──
    QObject::connect(&mpv, &MpvWindow::positionChanged, &state,
                     [&](qint64 pos, qint64 dur) {
                         QJsonObject patch;
                         patch.insert(QStringLiteral("positionMs"), pos);
                         patch.insert(QStringLiteral("durationMs"), dur);
                         state.applyJson(patch);
                     });
    QObject::connect(&mpv, &MpvWindow::pausedChanged, &state,
                     [&](bool paused) {
                         QJsonObject patch;
                         patch.insert(QStringLiteral("paused"), paused);
                         state.applyJson(patch);
                     });

    // ── 677：播放态回传 Flutter（`playback` 帧）──
    //
    // 【为什么必须有】Qt 接管后 mpv 在**本进程**，Flutter 侧的 `_player`
    // 是一台从未起播的空闲引擎 → 房间心跳读到 position=0/playing=false，
    // 房主广播全是假值（观众永远停在开头）。这里把真实播放态回传。
    //
    // 节流 200ms + 边沿立即 flush：位置是高频量（20Hz 事件），全量转发
    // 会白烧带宽；但播放/暂停/seek/倍速这类**边沿**必须立刻发，否则
    // 观众要等最多 200ms 才知道房主暂停了。
    auto* playbackTimer = new QTimer(&app);
    playbackTimer->setSingleShot(true);
    playbackTimer->setInterval(200);
    QObject::connect(playbackTimer, &QTimer::timeout, &app, [&]() {
        QJsonObject pb;
        pb.insert(QStringLiteral("positionMs"), state.positionMs());
        pb.insert(QStringLiteral("durationMs"), state.durationMs());
        pb.insert(QStringLiteral("paused"), state.paused());
        pb.insert(QStringLiteral("rate"), state.speed());
        pb.insert(QStringLiteral("buffering"), state.buffering());
        pipe.sendPlayback(pb);
    });
    const auto flushPlaybackSoon = [playbackTimer]() {
        if (!playbackTimer->isActive()) playbackTimer->start();
    };
    QObject::connect(&mpv, &MpvWindow::positionChanged, &app,
                     [flushPlaybackSoon](qint64, qint64) {
                         flushPlaybackSoon();
                     });

    // 边沿（暂停/播放）立即发，不等节流。
    QObject::connect(&mpv, &MpvWindow::pausedChanged, &app,
                     [&pipe, &state](bool paused) {
                         QJsonObject pb;
                         pb.insert(QStringLiteral("positionMs"),
                                   state.positionMs());
                         pb.insert(QStringLiteral("durationMs"),
                                   state.durationMs());
                         pb.insert(QStringLiteral("paused"), paused);
                         pb.insert(QStringLiteral("rate"), state.speed());
                         pb.insert(QStringLiteral("buffering"),
                                   state.buffering());
                         pipe.sendPlayback(pb);
                     });

    // ── 677：全屏态回传（房间并排与全屏互斥，Dart 需要知道）──
    QObject::connect(&mpv, &MpvWindow::hostFullscreenChanged, &app, [&]() {
        QJsonObject ws;
        ws.insert(QStringLiteral("fullscreen"), mpv.isHostFullscreen());
        pipe.sendWindowState(ws);
        // 全屏切换后**立即**重贴悬浮层 + 抬到最前：50ms 轮询只在本窗
        // 活跃时才 raise，全屏瞬间可能还没激活 → 控件层被视频盖住
        //（真机观感「全屏后控件消失」）。
        QTimer::singleShot(0, &app, [host, overlay, syncOverlayGeometry]() {
            if (host == nullptr || overlay == nullptr) return;
            syncOverlayGeometry();
            overlay->raise();
        });
        state.setControlsVisible(true);
    });

    // ── 681：**删除** 50ms 跟随轮询 ──
    //
    // 【真机回归：拖 Qt 窗后面板不跟随 / 调高度面板不跟】旧实现在这里每
    // 50ms 调 `followParentOnce()`，而它写死 `left = work.left()` ——
    // 用户把 Qt 窗拖到 x=500 后，400ms 挂起一结束就被拽回 x=0，
    // 面板也跟着弹回去（观感「拖了没用」）。
    //
    // 现在改为**纯事件驱动**：
    //   - 拖/缩 Qt 窗 → `userWindowMoved` → Dart 把面板平移过去（见下）
    //   - 拖/缩面板   → Dart 的 WindowListener → `setWindowRect` 驱动 Qt
    // 谁被拖动，谁就是锚点，另一方跟随。

    // ── 679：用户拖动/缩放 Qt 窗 → 回传新矩形（`windowMoved` 帧）──
    //
    // 【双向跟随】Flutter 面板窗要跟着 Qt 窗走（用户要求「拖任意一个
    // 另一个都跟随」）。程序性 setGeometry（跟随时）已在 MpvWindow 里
    // 用 applyingProgrammaticGeometry_ 屏蔽 → 不发 userWindowMoved →
    // 无死循环。
    //
    // 节流 80ms：拖动中每像素发一帧太密（Dart 侧要 setBounds，代价高）。
    auto* movedTimer = new QTimer(&app);
    movedTimer->setSingleShot(true);
    movedTimer->setInterval(80);
    QObject::connect(movedTimer, &QTimer::timeout, &app, [&mpv, &pipe, host]() {
        if (host == nullptr) return;
        const QRect g = host->geometry();
        QJsonObject data;
        data.insert(QStringLiteral("x"), g.x());
        data.insert(QStringLiteral("y"), g.y());
        data.insert(QStringLiteral("w"), g.width());
        data.insert(QStringLiteral("h"), g.height());
        pipe.sendWindowMoved(data);
        qInfo().noquote() << "[window] 用户移动/缩放 →" << g;
    });
    QObject::connect(&mpv, &MpvWindow::userWindowMoved, &app,
                     [movedTimer](int, int, int, int) {
                         if (!movedTimer->isActive()) movedTimer->start();
                     });

    // ── 677：并排布局回传（Qt 算 → Dart 应用面板侧）──
    QObject::connect(
        &mpv, &MpvWindow::splitLayoutReady, &app,
        [&pipe](int px, int py, int pw, int ph, int vx, int vy, int vw,
                int vh, int maxW, int maxH, bool ok) {
            QJsonObject panel;
            panel.insert(QStringLiteral("x"), px);
            panel.insert(QStringLiteral("y"), py);
            panel.insert(QStringLiteral("w"), pw);
            panel.insert(QStringLiteral("h"), ph);
            QJsonObject video;
            video.insert(QStringLiteral("x"), vx);
            video.insert(QStringLiteral("y"), vy);
            video.insert(QStringLiteral("w"), vw);
            video.insert(QStringLiteral("h"), vh);
            QJsonObject data;
            data.insert(QStringLiteral("ok"), ok);
            data.insert(QStringLiteral("panel"), panel);
            data.insert(QStringLiteral("video"), video);
            data.insert(QStringLiteral("maxPanelW"), maxW);
            data.insert(QStringLiteral("maxPanelH"), maxH);
            pipe.sendSplitLayout(data);
        });

    return app.exec();
}
