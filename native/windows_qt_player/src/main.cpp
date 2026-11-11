#include <QCommandLineParser>
#include <QDateTime>
#include <QDebug>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QGuiApplication>
#include <QJsonObject>
#include <QJsonValue>
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
    parser.addOption({"selftest", "QML 加载冒烟自检后退出", "flag", "0"});
    // 【670】预热模式：窗口隐藏待命，收到首条 load 命令才弹出；
    // 管道断开自动退出（防孤儿进程）。
    parser.addOption({"prewarm", "隐藏待命模式（启动预热）", "flag", "0"});
    parser.process(app);

    const bool selftest = parser.isSet("selftest");
    const bool prewarm = parser.value("prewarm") == QLatin1String("1");
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

    // ── QML ──
    QQmlApplicationEngine engine;
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
    const auto showWindows = [host, overlay, &windowsShown]() {
        if (windowsShown) return;
        windowsShown = true;
        host->show();
        overlay->show();
        overlay->requestActivate();
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

    // ── 状态：Flutter → mpv + QML ──
    QObject::connect(&pipe, &PipeServer::stateReceived, &state,
                     [&](const QJsonObject& json) {
                         state.applyJson(json);
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
                             showWindows();
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
                         } else if (type ==
                                    QLatin1String("selectSubtitle")) {
                             const int id = static_cast<int>(
                                 cmd.value(QLatin1String("id")).toInt(-1));
                             mpv.selectTrack(QStringLiteral("subtitle"),
                                             id > 0 ? id - 1 : -1);
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

    return app.exec();
}
