#include "pipe_server.h"

#include <QDebug>
#include <QHostAddress>
#include <QJsonDocument>
#include <QJsonParseError>
#include <QTcpServer>
#include <QTcpSocket>

PipeServer::PipeServer(QObject* parent) : QObject(parent) {}

PipeServer::~PipeServer() {
    if (client_ != nullptr) {
        client_->disconnect(this);
        client_->deleteLater();
        client_ = nullptr;
    }
    if (server_ != nullptr) {
        server_->close();
        delete server_;
        server_ = nullptr;
    }
}

bool PipeServer::start(quint16 port, const QString& token) {
    token_ = token;

    server_ = new QTcpServer(this);
    connect(server_, &QTcpServer::newConnection, this,
            &PipeServer::onNewConnection);

    // 只绑 loopback：外部网络无法连入。
    if (!server_->listen(QHostAddress::LocalHost, port)) {
        qWarning() << "[ipc] 监听失败:" << server_->errorString();
        return false;
    }

    qInfo().noquote() << "[ipc] 监听 127.0.0.1:" << server_->serverPort();
    return true;
}

void PipeServer::onNewConnection() {
    while (server_->hasPendingConnections()) {
        QTcpSocket* socket = server_->nextPendingConnection();
        if (client_ != nullptr) {
            // 只接受一个客户端：多连的（误连/探测）直接断开。
            socket->disconnectFromHost();
            socket->deleteLater();
            continue;
        }
        client_ = socket;
        authed_ = false;
        buffer_.clear();
        connect(client_, &QTcpSocket::readyRead, this, &PipeServer::onReadyRead);
        connect(client_, &QTcpSocket::disconnected, this,
                &PipeServer::onDisconnected);
        qInfo() << "[ipc] 客户端已连接";
        emit clientChanged(true);
        emit clientChangedValue();
    }
}

void PipeServer::onReadyRead() {
    if (client_ == nullptr) return;
    buffer_.append(client_->readAll());

    int start = 0;
    while (true) {
        const int nl = buffer_.indexOf('\n', start);
        if (nl < 0) break;
        const QByteArray line = buffer_.mid(start, nl - start).trimmed();
        start = nl + 1;
        if (line.isEmpty()) continue;

        QJsonParseError err{};
        const QJsonDocument doc = QJsonDocument::fromJson(line, &err);
        if (err.error != QJsonParseError::NoError || !doc.isObject()) {
            qWarning().noquote() << "[ipc] JSON 解析失败:" << err.errorString();
            continue;
        }
        const QJsonObject obj = doc.object();
        const QString type = obj.value(QLatin1String("type")).toString();

        // 首帧必须是 auth（带 token），否则拒绝——防止同机其他进程误连。
        if (!authed_) {
            if (type != QLatin1String("auth")) {
                qWarning() << "[ipc] 首帧不是 auth，断开";
                client_->disconnectFromHost();
                return;
            }
            const QString token =
                obj.value(QLatin1String("token")).toString();
            if (token != token_) {
                qWarning() << "[ipc] token 不匹配，断开";
                client_->disconnectFromHost();
                return;
            }
            authed_ = true;
            qInfo() << "[ipc] 认证通过";
            continue;
        }

        if (type == QLatin1String("state")) {
            const QJsonValue data = obj.value(QLatin1String("data"));
            if (data.isObject()) emit stateReceived(data.toObject());
        } else if (type == QLatin1String("command")) {
            // Flutter → Qt 的控制指令（播放/暂停/seek/音量/倍速/加载）。
            const QJsonValue data = obj.value(QLatin1String("data"));
            if (data.isObject()) emit commandReceived(data.toObject());
        } else if (type == QLatin1String("ping")) {
            sendRaw(QByteArrayLiteral("{\"type\":\"pong\"}\n"));
        }
    }
    if (start > 0) buffer_.remove(0, start);
}

void PipeServer::onDisconnected() {
    if (client_ == nullptr) return;
    qInfo() << "[ipc] 客户端断开";
    client_->deleteLater();
    client_ = nullptr;
    buffer_.clear();
    authed_ = false;
    emit clientChanged(false);
    emit clientChangedValue();
}

void PipeServer::sendCommand(const QJsonObject& command) {
    if (client_ == nullptr || !authed_) return;
    QJsonObject frame;
    frame.insert(QStringLiteral("type"), QStringLiteral("command"));
    frame.insert(QStringLiteral("data"), command);
    sendRaw(QJsonDocument(frame).toJson(QJsonDocument::Compact) + '\n');
}

void PipeServer::sendPlayback(const QJsonObject& playback) {
    if (client_ == nullptr || !authed_) return;
    QJsonObject frame;
    frame.insert(QStringLiteral("type"), QStringLiteral("playback"));
    frame.insert(QStringLiteral("data"), playback);
    sendRaw(QJsonDocument(frame).toJson(QJsonDocument::Compact) + '\n');
}

void PipeServer::sendWindowState(const QJsonObject& windowState) {
    if (client_ == nullptr || !authed_) return;
    QJsonObject frame;
    frame.insert(QStringLiteral("type"), QStringLiteral("windowState"));
    frame.insert(QStringLiteral("data"), windowState);
    sendRaw(QJsonDocument(frame).toJson(QJsonDocument::Compact) + '\n');
}

void PipeServer::sendSplitLayout(const QJsonObject& layout) {
    if (client_ == nullptr || !authed_) return;
    QJsonObject frame;
    frame.insert(QStringLiteral("type"), QStringLiteral("splitLayout"));
    frame.insert(QStringLiteral("data"), layout);
    sendRaw(QJsonDocument(frame).toJson(QJsonDocument::Compact) + '\n');
}

void PipeServer::sendRaw(const QByteArray& payload) {
    if (client_ == nullptr) return;
    client_->write(payload);
    client_->flush();
}
