#include "key_router.h"

#include <QByteArray>
#include <QEvent>
#include <QJsonObject>
#include <QKeyEvent>
#include <QWindow>

#include "mpv_window.h"
#include "pipe_server.h"
#include "player_state.h"

namespace {

/// 文本输入焦点（TextInput/TextEdit/TextField 及子类）→ 按键放行，
/// 弹幕搜索等输入框打字（含空格）不受影响。
bool textInputFocused(const QObject* watched) {
    auto* window = qobject_cast<QWindow*>(const_cast<QObject*>(watched));
    if (window == nullptr) return false;
    const QObject* focusObject = window->focusObject();
    if (focusObject == nullptr) return false;
    const QByteArray className = focusObject->metaObject()->className();
    return className.contains("TextInput") || className.contains("TextEdit") ||
           className.contains("TextField");
}

} // namespace

KeyRouter::KeyRouter(PlayerState* state, PipeServer* pipe, MpvWindow* mpv,
                     QObject* parent)
    : QObject(parent), state_(state), pipe_(pipe), mpv_(mpv) {}

bool KeyRouter::eventFilter(QObject* watched, QEvent* event) {
    if (event->type() != QEvent::KeyPress) return false;
    auto* keyEvent = static_cast<QKeyEvent*>(event);
    const int key = keyEvent->key();
    if (key != Qt::Key_Space && key != Qt::Key_Escape) return false;
    // 文本输入中：原样放行（打字不受影响）。
    if (textInputFocused(watched)) return false;
    // 长按 auto-repeat：消费但不重复触发。
    if (keyEvent->isAutoRepeat()) return true;

    if (key == Qt::Key_Space) {
        // 677：房间观众不得键盘播放/暂停（canControl 门禁）。
        if (state_ != nullptr && !state_->canControl()) return true;
        if (mpv_ != nullptr) mpv_->togglePause();
        if (pipe_ != nullptr) {
            pipe_->sendCommand(QJsonObject{
                {QStringLiteral("type"), QStringLiteral("togglePlay")}});
        }
        return true;
    }

    // Qt::Key_Escape：语义在 QML 三层阶梯（Overlay.qml 单点连接）：
    // 收面板 → 退全屏 → requestExit（单人=关 Qt 回详情页；房间=解散/离开确认）。
    if (mpv_ != nullptr) mpv_->notifyEscapePressed();
    return true;
}
