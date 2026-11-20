#pragma once

#include <QColor>
#include <QQuickPaintedItem>
#include <QVariantList>

/// 695：弹幕自绘渲染（单画布 QPainter，对齐安卓 DanmakuLayerView.kt 的
/// Canvas.drawText 模式）——Windows 弹幕掉帧根治：
///
/// 【为什么换渲染方式】旧 QML 池化 `Text` 节点（保留模式场景图）每帧
/// N 个节点 transform/opacity 同步 + N×6 个绑定重求值 + N 个 JS 对象
/// 分配（真机：掉帧、跑一秒停顿一下）。自绘每帧**一次 paint()** 画完
/// 全部活跃弹幕，零场景图节点、零绑定求值；Qt 字形缓存自动复用。
///
/// 【696：投影也挪进来】初版自绘仍让 QML tick() 每帧把 x/y/alpha 算好
/// 打成 QVariantList 塞进来（N 个 JS 对象 + N 个 QVariantMap 每帧深转换
/// = GC 垃圾，「跑一秒停顿一下」真根因）。现 items 只存**静态数据**
/// （text/color/mode/timeMs/lane/textW，仅车道/数据变化时更新，每秒
/// 最多几次），每帧只写一个 `positionMs`，x/y/alpha/渐隐全部在 paint()
/// 内现算——与安卓「Canvas 自己按单调时钟算坐标」同构。
///
/// 【职责】数据进、画面出：投影公式与 DanmakuLayer.tick() 的历史公式
/// 逐字等价（scroll 左移 / top、bottom 居中；bottom 轨贴底；固定弹幕
/// 首尾各 10% 生命周期淡入淡出）。
class DanmakuPaintItem : public QQuickPaintedItem {
    Q_OBJECT
    /// 静态条目：{text, color, mode, timeMs, lane, textW}。
    /// mode: "scroll" | "top" | "bottom"。
    Q_PROPERTY(QVariantList items READ items WRITE setItems NOTIFY itemsChanged)
    /// 当前播放位置（ms）——每帧唯一写入；paint() 据此投影。
    Q_PROPERTY(qlonglong positionMs READ positionMs WRITE setPositionMs NOTIFY
                   positionMsChanged)
    /// 滚动穿屏时长（ms，= scrollBaseMs / speed）。
    Q_PROPERTY(double travelMs READ travelMs WRITE setTravelMs NOTIFY
                   travelMsChanged)
    /// 全局不透明度（danmakuOpacity）。
    Q_PROPERTY(double contentOpacity READ contentOpacity WRITE setContentOpacity
                   NOTIFY contentOpacityChanged)
    /// 边距（edgePadding）。
    Q_PROPERTY(double edgePadding READ edgePadding WRITE setEdgePadding NOTIFY
                   edgePaddingChanged)
    /// 行距（lineHeight = fontSize + rowGap）。
    Q_PROPERTY(double lineHeight READ lineHeight WRITE setLineHeight NOTIFY
                   lineHeightChanged)
    /// 同屏最多绘制条数（poolSize）。
    Q_PROPERTY(int poolCap READ poolCap WRITE setPoolCap NOTIFY poolCapChanged)
    Q_PROPERTY(int fontSize READ fontSize WRITE setFontSize NOTIFY
                   fontSizeChanged)
    Q_PROPERTY(double outlineWidth READ outlineWidth WRITE setOutlineWidth
                   NOTIFY outlineWidthChanged)
    Q_PROPERTY(QColor outlineColor READ outlineColor WRITE setOutlineColor
                   NOTIFY outlineColorChanged)
public:
    explicit DanmakuPaintItem(QQuickItem* parent = nullptr);

    void paint(QPainter* painter) override;

    QVariantList items() const { return items_; }
    void setItems(const QVariantList& items);

    qlonglong positionMs() const { return positionMs_; }
    void setPositionMs(qlonglong v);

    double travelMs() const { return travelMs_; }
    void setTravelMs(double v);

    double contentOpacity() const { return contentOpacity_; }
    void setContentOpacity(double v);

    double edgePadding() const { return edgePadding_; }
    void setEdgePadding(double v);

    double lineHeight() const { return lineHeight_; }
    void setLineHeight(double v);

    int poolCap() const { return poolCap_; }
    void setPoolCap(int v);

    int fontSize() const { return fontSize_; }
    void setFontSize(int v);

    double outlineWidth() const { return outlineWidth_; }
    void setOutlineWidth(double v);

    QColor outlineColor() const { return outlineColor_; }
    void setOutlineColor(const QColor& v);

signals:
    void itemsChanged();
    void positionMsChanged();
    void travelMsChanged();
    void contentOpacityChanged();
    void edgePaddingChanged();
    void lineHeightChanged();
    void poolCapChanged();
    void fontSizeChanged();
    void outlineWidthChanged();
    void outlineColorChanged();

private:
    /// 固定弹幕淡入淡出（首尾各 10% 生命周期，对齐安卓 fixedFade）。
    static double fixedFade(double progress);

    QVariantList items_;
    qlonglong positionMs_ = 0;
    double travelMs_ = 8000.0 / 0.7;  // 默认 scrollBaseMs / 默认倍速
    double contentOpacity_ = 1.0;
    double edgePadding_ = 8.0;
    double lineHeight_ = 31.0;  // 默认 fontSize 25 + rowGap 6
    int poolCap_ = 150;
    int fontSize_ = 25;
    double outlineWidth_ = 0.0;
    QColor outlineColor_ = QColor(0, 0, 0);
};
