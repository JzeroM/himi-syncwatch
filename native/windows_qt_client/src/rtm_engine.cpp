#include "rtm_engine.h"

#include <QDebug>
#include <QTime>

using namespace agora::rtm;

namespace {
const char* kErrOk = "ok";
const char* kErrPrefix = "错误码 ";

QString errText(RTM_ERROR_CODE code) {
    if (code == RTM_ERROR_OK) {
        return QString::fromLatin1(kErrOk);
    }
    const char* reason = getErrorReason(code);
    return QStringLiteral("%1%2").arg(QString::fromLatin1(kErrPrefix)).arg(QString::fromLatin1(reason ? reason : "unknown"));
}
}  // namespace

RtmEngine::RtmEngine(QObject* parent) : QObject(parent), client_(nullptr), presence_(nullptr) {
    connect(this, &RtmEngine::sdkLoginDone, this, &RtmEngine::applyLoginDone, Qt::QueuedConnection);
    connect(this, &RtmEngine::sdkSubscribeDone, this, &RtmEngine::applySubscribeDone, Qt::QueuedConnection);
    connect(this, &RtmEngine::sdkMessageIn, this, &RtmEngine::applyMessageIn, Qt::QueuedConnection);
    connect(this, &RtmEngine::sdkOnline, this, &RtmEngine::applyOnline, Qt::QueuedConnection);
}

RtmEngine::~RtmEngine() {
    if (client_) {
        client_->release();
        client_ = nullptr;
        presence_ = nullptr;
    }
}

void RtmEngine::appendLog(const QString& line) {
    log_.append(QStringLiteral("[%1] %2\n").arg(QTime::currentTime().toString("HH:mm:ss")).arg(line));
    // 限制日志长度
    if (log_.size() > 8000) {
        log_ = log_.right(6000);
    }
    emit logChanged(log_);
}

// ---------- 主线程操作入口 ----------

void RtmEngine::login(const QString& appId, const QString& userId, const QString& token) {
    if (client_) {
        client_->release();
        client_ = nullptr;
        presence_ = nullptr;
    }

    RtmConfig cfg;
    QByteArray appIdBa = appId.toUtf8();
    QByteArray userIdBa = userId.toUtf8();
    cfg.appId = appIdBa.constData();
    cfg.userId = userIdBa.constData();
    cfg.useStringUserId = true;
    cfg.eventHandler = this;

    int errorCode = 0;
    client_ = createAgoraRtmClient(cfg, errorCode);
    if (!client_) {
        appendLog(QStringLiteral("创建 RTM 客户端失败, errorCode=%1").arg(errorCode));
        status_ = QStringLiteral("error");
        emit statusChanged(status_);
        return;
    }
    presence_ = client_->getPresence();

    QByteArray tokenBa = token.toUtf8();
    uint64_t requestId = 0;
    client_->login(token.isEmpty() ? "" : tokenBa.constData(), requestId);
    appendLog(QStringLiteral("请求登录..."));
}

void RtmEngine::logout() {
    if (!client_) {
        return;
    }
    uint64_t requestId = 0;
    client_->logout(requestId);
}

void RtmEngine::subscribeChannel(const QString& channel) {
    if (!client_) {
        appendLog(QStringLiteral("请先登录"));
        return;
    }
    channel_ = channel;
    QByteArray channelBa = channel.toUtf8();
    SubscribeOptions opts;  // 默认含 message + presence
    uint64_t requestId = 0;
    client_->subscribe(channelBa.constData(), opts, requestId);
    appendLog(QStringLiteral("请求订阅频道 %1...").arg(channel));
}

void RtmEngine::publishMessage(const QString& text) {
    if (!client_ || channel_.isEmpty()) {
        appendLog(QStringLiteral("请先订阅频道"));
        return;
    }
    QByteArray textBa = text.toUtf8();
    QByteArray channelBa = channel_.toUtf8();
    PublishOptions opts;
    uint64_t requestId = 0;
    client_->publish(channelBa.constData(), textBa.constData(), static_cast<size_t>(textBa.size()), opts, requestId);
    appendLog(QStringLiteral("已发布: %1").arg(text));
}

void RtmEngine::refreshOnlineCount(const QString& channel) {
    if (!presence_ || channel.isEmpty()) {
        return;
    }
    QByteArray channelBa = channel.toUtf8();
    GetOnlineUsersOptions opts;
    uint64_t requestId = 0;
    presence_->getOnlineUsers(channelBa.constData(), RTM_CHANNEL_TYPE_MESSAGE, opts, requestId);
}

// ---------- 事件回调(SDK 工作线程) ----------

void RtmEngine::onLoginResult(uint64_t /*requestId*/, RTM_ERROR_CODE errorCode) {
    const bool ok = (errorCode == RTM_ERROR_OK);
    emit sdkLoginDone(ok ? QStringLiteral("connected") : QStringLiteral("error"),
                      errText(errorCode));
}

void RtmEngine::onLogoutResult(uint64_t /*requestId*/, RTM_ERROR_CODE errorCode) {
    appendLog(QStringLiteral("登出: %1").arg(errText(errorCode)));
    status_ = QStringLiteral("disconnected");
    emit statusChanged(status_);
}

void RtmEngine::onSubscribeResult(uint64_t /*requestId*/, const char* /*channelName*/,
                                  RTM_ERROR_CODE errorCode) {
    const bool ok = (errorCode == RTM_ERROR_OK);
    emit sdkSubscribeDone(ok ? QStringLiteral("subscribed") : QStringLiteral("subscribe_error"),
                          errText(errorCode));
    if (ok) {
        emit sdkOnline(-1, QString());  // 订阅成功后主动刷一次在线人数
    }
}

void RtmEngine::onPublishResult(uint64_t /*requestId*/, RTM_ERROR_CODE errorCode) {
    if (errorCode != RTM_ERROR_OK) {
        appendLog(QStringLiteral("发布失败: %1").arg(errText(errorCode)));
    }
}

void RtmEngine::onMessageEvent(const MessageEvent& event) {
    if (!event.publisher || !event.message) {
        return;
    }
    const QString publisher = QString::fromUtf8(event.publisher);
    const QString text = QString::fromUtf8(event.message, static_cast<int>(event.messageLength));
    emit sdkMessageIn(publisher, text);
}

void RtmEngine::onPresenceEvent(const PresenceEvent& event) {
    Q_UNUSED(event);
    // presence 变化 → 刷新在线人数
    emit sdkOnline(-1, QString());
}

void RtmEngine::onGetOnlineUsersResult(uint64_t /*requestId*/, const UserState* /*userStateList*/,
                                       size_t count, const char* /*nextPage*/,
                                       RTM_ERROR_CODE errorCode) {
    if (errorCode == RTM_ERROR_OK) {
        emit sdkOnline(static_cast<int>(count), QString());
    } else {
        emit sdkOnline(-1, errText(errorCode));
    }
}

void RtmEngine::onConnectionStateChanged(const char* /*channelName*/, RTM_CONNECTION_STATE state,
                                         RTM_CONNECTION_CHANGE_REASON /*reason*/) {
    QString st;
    switch (state) {
        case RTM_CONNECTION_STATE_DISCONNECTED: st = QStringLiteral("disconnected"); break;
        case RTM_CONNECTION_STATE_CONNECTING:   st = QStringLiteral("connecting"); break;
        case RTM_CONNECTION_STATE_CONNECTED:    st = QStringLiteral("connected"); break;
        case RTM_CONNECTION_STATE_RECONNECTING: st = QStringLiteral("reconnecting"); break;
        case RTM_CONNECTION_STATE_FAILED:       st = QStringLiteral("failed"); break;
        default: st = QStringLiteral("unknown"); break;
    }
    status_ = st;
    emit statusChanged(status_);
}

// ---------- 主线程应用回调(Q_PROPERTY 更新) ----------

void RtmEngine::applyLoginDone(const QString& st, const QString& note) {
    status_ = st;
    emit statusChanged(status_);
    appendLog(QStringLiteral("登录结果: %1").arg(note));
}

void RtmEngine::applySubscribeDone(const QString& st, const QString& note) {
    appendLog(QStringLiteral("订阅结果: %1").arg(note));
    if (st == QStringLiteral("subscribed")) {
        refreshOnlineCount(channel_);
    }
}

void RtmEngine::applyMessageIn(const QString& publisher, const QString& text) {
    appendLog(QStringLiteral("收到(%1): %2").arg(publisher).arg(text));
    emit messageReceived(publisher, text);
}

void RtmEngine::applyOnline(int count, const QString& note) {
    if (count >= 0) {
        onlineCount_ = count;
        emit onlineCountChanged(onlineCount_);
    } else {
        appendLog(QStringLiteral("在线人数查询: %1").arg(note));
    }
}
