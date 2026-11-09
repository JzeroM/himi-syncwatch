#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QTimer>
#include <QWindow>

#include <QCommandLineParser>

#include "mpv_window.h"

/// 654：Windows 播放器窗口 spike（Qt Quick + libmpv 直出）
///
/// 【本轮唯一目的】验证一个致命假设：
///   mpv 用 `wid` 直出到 Qt 创建的 HWND 时，HDR 是否还在？
///
/// 【刻意的最小范围】
/// - 不接 Flutter、不接 IPC、不接 Agora RTM（RTM 全部留在 Flutter）
/// - 片源从命令行传入：himi_qt_win.exe "https://..."
/// - 无播放器 UI（655 才做底栏/顶栏/面板/弹幕）
///
/// 理由：如果 HDR 假设不成立，前面写的 IPC 与 QML UI 全部白费。
/// 先花最小代价排除最大风险。
///
/// 【按键】空格=暂停  F=全屏  H=切HDR  S=验证步骤  Esc=退出
int main(int argc, char* argv[]) {
    QGuiApplication app(argc, argv);
    QGuiApplication::setApplicationName("HIMI Qt Spike");
    QGuiApplication::setOrganizationName("Himi");

    QCommandLineParser parser;
    parser.setApplicationDescription(
        "HIMI Windows 播放器 spike（验证 Qt + mpv + HDR 直出）");
    parser.addHelpOption();
    parser.addPositionalArgument("url", "要播放的媒体地址（可选）");
    parser.addOption({"no-hdr", "启动时关闭 HDR 直出（用于 A/B 对比）"});
    // 【排障开关】把 mpv 放到独立顶层窗口。
    //
    // 本轮有一个只能实测的未知点：Qt 自己的 swapchain 会不会盖住 mpv 子
    // 窗口（Flutter 就栽在这里 → 灰屏）。若只做一种模式，一旦黑屏就分不清
    // 是「Qt 遮挡」还是「HDR 失败」，结论会被带偏。
    parser.addOption(
        {"video-top-level",
         "把 mpv 视频放到独立顶层窗口（排除 Qt 遮挡子窗口的可能）"});
    parser.process(app);

    const QString url = parser.positionalArguments().value(0);
    const bool hdrOn = !parser.isSet("no-hdr");
    const auto mode = parser.isSet("video-top-level")
                          ? MpvWindow::VideoMode::TopLevel
                          : MpvWindow::VideoMode::Child;

    QQmlApplicationEngine engine;
    const QUrl qmlUrl(QStringLiteral("qrc:/qt/qml/HimiWin/Main.qml"));

    QObject::connect(
        &engine, &QQmlApplicationEngine::objectCreated, &app,
        [qmlUrl](QObject* obj, const QUrl& objUrl) {
            if (!obj && qmlUrl == objUrl) {
                qCritical("Main.qml 加载失败");
                QCoreApplication::exit(-1);
            }
        },
        Qt::QueuedConnection);
    engine.load(qmlUrl);

    if (engine.rootObjects().isEmpty()) {
        qCritical("QML 根对象为空，退出");
        return -1;
    }

    auto* host = qobject_cast<QWindow*>(engine.rootObjects().constFirst());
    if (host == nullptr) {
        qCritical("QML 根对象不是 QWindow");
        return -1;
    }

    MpvWindow mpvWindow;
    // 等窗口真正显示后再建视频窗口：winId() 在 show 之前拿到的 HWND
    // 可能还没最终确定，mpv 绑上去会画到不存在的窗口。
    QTimer::singleShot(0, &app, [&]() {
        if (!mpvWindow.attach(host, url, hdrOn, mode)) {
            qCritical("mpv 初始化失败");
            QCoreApplication::exit(-2);
            return;
        }
        // 给 QML 底部提示条让出 28px（全屏时归零，提示条隐藏）。
        // 原生 HWND 会盖住 QML，不减这个高度提示条就永远看不见。
        mpvWindow.setBottomInset(host->visibility() == QWindow::FullScreen ? 0
                                                                         : 28);
        mpvWindow.printVerifySteps();
    });

    QObject::connect(host, &QWindow::visibilityChanged, &mpvWindow,
                     [&mpvWindow](QWindow::Visibility visibility) {
                         mpvWindow.setBottomInset(
                             visibility == QWindow::FullScreen ? 0 : 28);
                     });

    return app.exec();
}
