#ifndef PIPE_SERVER_H
#define PIPE_SERVER_H

#include <QJsonObject>
#include <QObject>
#include <QString>

class QTcpServer;
class QTcpSocket;

/// 656：与 Flutter 的通信服务端（Qt 侧）。
///
/// 【为什么不用 Windows 命名管道】最初设计用 `CreateNamedPipe`，但
/// **Dart 无法连接 Windows 命名管道**——`Socket.connect` 的
/// `InternetAddressType.unix` 只支持 Unix domain socket，命名管道必须走
/// `CreateFile`（原生 API），Dart 没有内置支持，得再写一个 Flutter 插件
/// 做桥接，复杂度不划算。
///
/// 改用 **TCP localhost**：
/// - Dart 原生 `Socket.connect(InternetAddress.loopbackIPv4, port)`
/// - Qt 原生 `QTcpServer` / `QTcpSocket`
/// - 只绑 `127.0.0.1`，不暴露到网络
/// - 带一次性 token 校验，防止同机其他进程误连
///
/// 【为什么 Qt 做服务端】Flutter 先启动，再由它 `Process.start` 拉起 Qt。
/// 若 Flutter 做服务端，Qt 必须在 Flutter 建好监听前就绪——启动竞态更难
/// 处理。反过来：Qt 启动后立即监听，Flutter 拿到端口后再连，天然没竞态。
/// 端口通过命令行 `--port` 传给 Qt（由 Flutter 先选一个空闲端口）。
///
/// 【协议】NDJSON（每帧一个 JSON + `\n`）：
///   Flutter → Qt：`{"type":"state","data":{...NativePlayerState...}}`
///   Qt → Flutter：`{"type":"command","data":{...NativePlayerCommand...}}`
class PipeServer : public QObject {
    Q_OBJECT

    /// QML 用：是否已连接（用于显示「等待主程序连接…」）。
    Q_PROPERTY(bool hasClient READ hasClient NOTIFY clientChangedValue)

public:
    explicit PipeServer(QObject* parent = nullptr);
    ~PipeServer() override;

    /// 在 `127.0.0.1:port` 上监听。`token` 用于校验首帧。
    bool start(quint16 port, const QString& token);

    bool hasClient() const { return client_ != nullptr; }

    /// 发送一条命令给 Flutter（`NativePlayerCommand` 的 JSON 形态）。
    ///
    /// 例：`sendCommand({{"type", "togglePlay"}})`
    Q_INVOKABLE void sendCommand(const QJsonObject& command);

    /// 677：回传播放态给 Flutter（`playback` 帧）。
    ///
    /// 【为什么必须有】Qt 接管后 mpv 在**本进程**，Flutter 侧的 `_player`
    /// 是一台从未起播的空闲引擎——房间心跳读到 `position=0 /
    /// playing=false`，房主的心跳/广播全是假值（观众永远停在开头）。
    /// 这里把 mpv 的真实播放态回传，Dart 侧镜像进适配器。
    void sendPlayback(const QJsonObject& playback);

    /// 677：回传窗口状态（`windowState` 帧：全屏态）。
    void sendWindowState(const QJsonObject& windowState);

    /// 677：回传并排布局（`splitLayout` 帧）。
    void sendSplitLayout(const QJsonObject& layout);

    /// 679：回传**用户**拖动/缩放后的窗口矩形（`windowMoved` 帧）。
    void sendWindowMoved(const QJsonObject& rect);

signals:
    /// 收到完整的一帧状态 JSON。
    void stateReceived(const QJsonObject& state);

    /// 收到 Flutter 发来的控制指令（`command` 帧的 data）。
    void commandReceived(const QJsonObject& command);

    /// 连接建立 / 断开。
    void clientChanged(bool connected);

    /// 专供 Q_PROPERTY 通知（Qt 要求属性通知信号签名与属性类型匹配）。
    void clientChangedValue();

private:
    void onNewConnection();
    void onReadyRead();
    void onDisconnected();
    void sendRaw(const QByteArray& payload);

    QString token_;
    QTcpServer* server_ = nullptr;
    QTcpSocket* client_ = nullptr;
    QByteArray buffer_;
    bool authed_ = false;
};

#endif  // PIPE_SERVER_H
