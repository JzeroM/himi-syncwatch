#ifndef RTM_ENGINE_H
#define RTM_ENGINE_H

#include <QObject>
#include <QString>

#include "IAgoraRtmClient.h"
#include "IAgoraRtmPresence.h"

// 封装 Agora RTM C++ SDK(agora_rtm_sdk.dll)，在 Windows 上提供
//   - 登录/登出
//   - 订阅/退订频道(消息+presence)
//   - 发布消息 / 接收消息
//   - 在线人数查询
// RTM 事件回调运行在 SDK 内部工作线程，通过信号跨线程投递到主线程(QML)。
class RtmEngine : public QObject, public agora::rtm::IRtmEventHandler {
    Q_OBJECT
    Q_PROPERTY(QString status READ status NOTIFY statusChanged)
    Q_PROPERTY(int onlineCount READ onlineCount NOTIFY onlineCountChanged)
    Q_PROPERTY(QString log READ log NOTIFY logChanged)

public:
    explicit RtmEngine(QObject* parent = nullptr);
    ~RtmEngine() override;

    QString status() const { return status_; }
    int onlineCount() const { return onlineCount_; }
    QString log() const { return log_; }

public slots:
    void login(const QString& appId, const QString& userId, const QString& token);
    void logout();
    void subscribeChannel(const QString& channel);
    void publishMessage(const QString& text);
    void refreshOnlineCount(const QString& channel);

signals:
    void statusChanged(const QString& status);
    void onlineCountChanged(int onlineCount);
    void logChanged(const QString& log);
    // 供 QML 连接
    void messageReceived(const QString& publisher, const QString& text);

    // SDK 工作线程 → 主线程 的内部信号
    void sdkLoginDone(const QString& status, const QString& note);
    void sdkSubscribeDone(const QString& status, const QString& note);
    void sdkMessageIn(const QString& publisher, const QString& text);
    void sdkOnline(int count, const QString& note);

private:
    // agora::rtm::IRtmEventHandler
    void onLoginResult(uint64_t requestId, agora::rtm::RTM_ERROR_CODE errorCode) override;
    void onLogoutResult(uint64_t requestId, agora::rtm::RTM_ERROR_CODE errorCode) override;
    void onSubscribeResult(uint64_t requestId, const char* channelName,
                           agora::rtm::RTM_ERROR_CODE errorCode) override;
    void onPublishResult(uint64_t requestId, agora::rtm::RTM_ERROR_CODE errorCode) override;
    void onMessageEvent(const MessageEvent& event) override;
    void onPresenceEvent(const PresenceEvent& event) override;
    void onGetOnlineUsersResult(uint64_t requestId, const agora::rtm::UserState* userStateList,
                                size_t count, const char* nextPage,
                                agora::rtm::RTM_ERROR_CODE errorCode) override;
    void onConnectionStateChanged(const char* channelName, agora::rtm::RTM_CONNECTION_STATE state,
                                  agora::rtm::RTM_CONNECTION_CHANGE_REASON reason) override;

    void appendLog(const QString& line);

    // 主线程执行：由 sdk* 信号(queued)触发，更新状态并发出 Q_PROPERTY 变更信号
    Q_SLOT void applyLoginDone(const QString& st, const QString& note);
    Q_SLOT void applySubscribeDone(const QString& st, const QString& note);
    Q_SLOT void applyMessageIn(const QString& publisher, const QString& text);
    Q_SLOT void applyOnline(int count, const QString& note);

    agora::rtm::IRtmClient* client_ = nullptr;
    agora::rtm::IRtmPresence* presence_ = nullptr;
    QString status_ = QStringLiteral("disconnected");
    QString channel_;
    int onlineCount_ = 0;
    QString log_;
};

#endif  // RTM_ENGINE_H
