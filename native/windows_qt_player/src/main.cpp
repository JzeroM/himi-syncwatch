#include <QCommandLineParser>
#include <QGuiApplication>
#include <QJsonObject>
#include <QJsonValue>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickWindow>
#include <QTimer>
#include <QtGlobal>   // qRound（DPI 换算用）

#include "mpv_window.h"
#include "pipe_server.h"
#include "player_state.h"

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
    QGuiApplication app(argc, argv);
    QGuiApplication::setApplicationName("HIMI Player");
    QGuiApplication::setOrganizationName("Himi");

    QCommandLineParser parser;
    parser.setApplicationDescription("HIMI Windows 播放器窗口");
    parser.addHelpOption();
    parser.addOption({"port", "IPC 监听端口（Flutter 侧传入）", "port"});
    parser.addOption({"token", "IPC 首帧认证 token", "token"});
    parser.addOption({"hdr", "是否请求 HDR 直出（1/0）", "flag", "1"});
    parser.addOption({"hlg", "内容是否为 HLG（1/0）", "flag", "0"});
    parser.process(app);

    const QString portText = parser.value("port");
    if (portText.isEmpty()) {
        qCritical("缺少 --port 参数");
        return -1;
    }
    bool portOk = false;
    const quint16 port = portText.toUShort(&portOk);
    if (!portOk || port == 0) {
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
    if (!pipe.start(port, token)) {
        qCritical("IPC 监听失败");
        return -2;
    }

    // ── QML ──
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("playerState", &state);
    engine.rootContext()->setContextProperty("pipeServer", &pipe);

    const QUrl qmlUrl(QStringLiteral("qrc:/qt/qml/HimiPlayer/Main.qml"));
    QObject::connect(
        &engine, &QQmlApplicationEngine::objectCreated, &app,
        [qmlUrl](QObject* obj, const QUrl& objUrl) {
            if (!obj && qmlUrl == objUrl) {
                qCritical("Main.qml 加载失败");
                QCoreApplication::exit(-3);
            }
        },
        Qt::QueuedConnection);
    engine.load(qmlUrl);

    if (engine.rootObjects().isEmpty()) return -3;

    auto* host = qobject_cast<QQuickWindow*>(engine.rootObjects().constFirst());
    if (host == nullptr) {
        qCritical("QML 根对象不是 Window");
        return -3;
    }

    // ── mpv ──
    MpvWindow mpv;
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
        // 顶栏 48 + 底栏 96：视频子窗口收窄，把控件区域让出来。
        // 原生子 HWND 永远画在 QML 之上（Win32 硬规则）。
        //
        // 【必须按 DPI 换算】QML 的 48/96 是**逻辑像素**，而
        // SetWindowPos 用**物理像素**。Qt 6 默认启用 HighDPI 缩放，
        // 150% 缩放下若不换算，视频窗口会少让出 24/48 像素 →
        // 控件被视频盖住一半。
        const qreal dpr = host->devicePixelRatio();
        mpv.setOverlayInsets(qRound(48 * dpr), qRound(96 * dpr));
    });

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

    // ── 控制指令：Flutter → mpv ──
    QObject::connect(&pipe, &PipeServer::commandReceived, &mpv,
                     [&](const QJsonObject& cmd) {
                         const QString type =
                             cmd.value(QLatin1String("type")).toString();
                         if (type == QLatin1String("load")) {
                             const QString url =
                                 cmd.value(QLatin1String("url")).toString();
                             const qint64 startMs = static_cast<qint64>(
                                 cmd.value(QLatin1String("startMs"))
                                     .toDouble(0));
                             if (!url.isEmpty()) {
                                 // 同一 URL 不重复 load（切集/续播才换）。
                                 // 但 startMs 仍需应用——续播位置可能变。
                                 if (url != loadedUrl) {
                                     loadedUrl = url;
                                     mpv.load(url);
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
