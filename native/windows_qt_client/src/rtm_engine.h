#ifndef RTM_ENGINE_H
#define RTM_ENGINE_H

#include <QObject>
#include <QString>

// M1 目标：封装 Agora RTM C++ SDK（agora_rtm_sdk.dll），提供
//   - 登录/登出
//   - 加入/离开频道
//   - 在线人数查询
//   - 消息发布与订阅
// 当前(M0)仅骨架：暴露一个可由 QML 观察的 status，便于验证工程链路。
class RtmEngine : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString status READ status NOTIFY statusChanged)

public:
    explicit RtmEngine(QObject* parent = nullptr);

    QString status() const { return status_; }

public slots:
    void setStatus(const QString& s);

signals:
    void statusChanged(const QString& status);

private:
    QString status_;
};

#endif  // RTM_ENGINE_H
