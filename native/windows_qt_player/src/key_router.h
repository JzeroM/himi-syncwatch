#pragma once

#include <QObject>

class MpvWindow;
class PipeServer;
class PlayerState;
class QEvent;

/// 695：窗口级键盘路由（Space / Esc）——QML `Shortcut` 的替代。
///
/// 【为什么不用 QML Shortcut】真机回归：`Shortcut { sequence: "Space" }`
/// 在播放窗实际使用中完全无效（「空格暂停/播放现状无效」）——焦点落在
/// 视频区/控件时按键被 shortcut-override 吞掉，双窗激活链路下 Shortcut
/// 的窗口作用域也不稳。窗口事件过滤器在 QQuickWindow 分发**之前**拿到
/// 按键，确定性生效（677 的 EscapeFilter 即此模式，已被真机验证可收到键）。
///
/// 【门禁】
/// - 文本输入焦点（弹幕搜索等）→ 放行，打字不受影响；
/// - Space：`canControl` 门禁（677：房间观众禁用）→ togglePause +
///   `togglePlay` 记账（房间同步），长按 auto-repeat 不重复切换；
/// - Esc：不在 C++ 定语义，`escapePressed` 信号转发 QML 三层阶梯
///   （收面板 → 退全屏 → requestExit），信号**单点**连接在 Overlay.qml
///   （mpvWindow 为两窗共用上下文属性，双连接会双重触发）。
///
/// 其余按键（←/→/↑/↓/F/F11）仍走 `PlayerShortcuts.qml` 的 QML Shortcut
///（它们不与焦点控件的 shortcut-override 冲突，现状有效）。
class KeyRouter : public QObject {
    Q_OBJECT
public:
    KeyRouter(PlayerState* state, PipeServer* pipe, MpvWindow* mpv,
              QObject* parent = nullptr);

protected:
    bool eventFilter(QObject* watched, QEvent* event) override;

private:
    PlayerState* state_ = nullptr;
    PipeServer* pipe_ = nullptr;
    MpvWindow* mpv_ = nullptr;
};
