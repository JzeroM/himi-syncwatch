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
/// 【职责】只画不算：items 由 DanmakuLayer.tick() 预计算（x/y/alpha/
/// textW 等），本类逐条 drawText（描边双绘 = Text.Outline 等价）。
class DanmakuPaintItem : public QQuickPaintedItem {
    Q_OBJECT
    Q_PROPERTY(QVariantList items READ items WRITE setItems NOTIFY itemsChanged)
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

    int fontSize() const { return fontSize_; }
    void setFontSize(int v);

    double outlineWidth() const { return outlineWidth_; }
    void setOutlineWidth(double v);

    QColor outlineColor() const { return outlineColor_; }
    void setOutlineColor(const QColor& v);

signals:
    void itemsChanged();
    void fontSizeChanged();
    void outlineWidthChanged();
    void outlineColorChanged();

private:
    QVariantList items_;
    int fontSize_ = 25;
    double outlineWidth_ = 0.0;
    QColor outlineColor_ = QColor(0, 0, 0);
};
