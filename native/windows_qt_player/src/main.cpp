#include <QCommandLineParser>
#include <QGuiApplication>
#include <QJsonObject>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickWindow>
#include <QTimer>

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
    QTimer::singleShot(0, &app, [&]() {
        if (!mpv.attach(host, hdr, hlg)) {
            qCritical("mpv 初始化失败");
            QCoreApplication::exit(-4);
            return;
        }
        // 顶栏 48 + 底栏 96：视频子窗口收窄，把控件区域让出来。
        // 原生子 HWND 永远画在 QML 之上（Win32 硬规则）。
        mpv.setOverlayInsets(48, 96);
    });

    // ── 状态：Flutter → mpv + QML ──
    QObject::connect(&pipe, &PipeServer::stateReceived, &state,
                     [&](const QJsonObject& json) {
                         state.applyJson(json);
                         // 播放地址也由 Flutter 下发（不放在命令行，
                         // 避免 URL 泄露到任务管理器 + 规避长度限制）
                         const QString url =
                             json.value(QLatin1String("playUrl")).toString();
                         if (!url.isEmpty() &&
                             url != host->property("loadedUrl").toString()) {
                             host->setProperty("loadedUrl", url);
                             mpv.load(url);
                         }
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
                                 host->setProperty("loadedUrl", url);
                                 mpv.load(url);
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
