#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>

#include "rtm_engine.h"

int main(int argc, char* argv[]) {
    QGuiApplication app(argc, argv);
    QGuiApplication::setApplicationName("HimiSync");
    QGuiApplication::setOrganizationName("Himi");

    QQmlApplicationEngine engine;

    // M1: 暴露 RTM 引擎给 QML（此时仅骨架，M1 填充实现）
    RtmEngine rtmEngine;
    engine.rootContext()->setContextProperty("rtmEngine", &rtmEngine);

    const QUrl url(QStringLiteral("qrc:/qt/qml/HimiWin/Main.qml"));
    QObject::connect(
        &engine, &QQmlApplicationEngine::objectCreated, &app,
        [url](QObject* obj, const QUrl& objUrl) {
            if (!obj && url == objUrl) {
                QCoreApplication::exit(-1);
            }
        },
        Qt::QueuedConnection);
    engine.load(url);

    return app.exec();
}
