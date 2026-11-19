#include "danmaku_paint_item.h"

#include <QFont>
#include <QFontMetrics>
#include <QPainter>
#include <QPen>

DanmakuPaintItem::DanmakuPaintItem(QQuickItem* parent)
    : QQuickPaintedItem(parent)
{
    // 弹幕层是透明悬浮绘制（不透明填充会盖视频）。
    setOpaquePainting(false);
    setAntialiasing(true);
}

void DanmakuPaintItem::setItems(const QVariantList& items)
{
    if (items_ == items) return;
    items_ = items;
    emit itemsChanged();
    update();
}

void DanmakuPaintItem::setFontSize(int v)
{
    if (fontSize_ == v) return;
    fontSize_ = v;
    emit fontSizeChanged();
    update();
}

void DanmakuPaintItem::setOutlineWidth(double v)
{
    if (outlineWidth_ == v) return;
    outlineWidth_ = v;
    emit outlineWidthChanged();
    update();
}

void DanmakuPaintItem::setOutlineColor(const QColor& v)
{
    if (outlineColor_ == v) return;
    outlineColor_ = v;
    emit outlineColorChanged();
    update();
}

void DanmakuPaintItem::paint(QPainter* painter)
{
    if (items_.isEmpty()) return;
    painter->setRenderHint(QPainter::TextAntialiasing, true);
    QFont font(QStringLiteral("Microsoft YaHei"));
    font.setPixelSize(fontSize_);
    font.setWeight(QFont::Medium);
    painter->setFont(font);
    // QML Text 的 y 是顶边；QPainter drawText 用基线 → +ascent 对齐。
    const qreal ascent = QFontMetrics(font).ascent();

    for (const QVariant& v : items_) {
        const QVariantMap m = v.toMap();
        const QString text = m.value(QStringLiteral("text")).toString();
        if (text.isEmpty()) continue;
        QColor fill(m.value(QStringLiteral("color")).toString());
        const qreal x = m.value(QStringLiteral("x")).toReal();
        const qreal y = m.value(QStringLiteral("y")).toReal();
        const qreal alpha = m.value(QStringLiteral("alpha")).toReal();
        fill.setAlphaF(fill.alphaF() * (alpha < 0 ? 0 : (alpha > 1 ? 1 : alpha)));
        const QPointF baseline(x, y + ascent);
        // 描边（Text.Outline 等价：先描边后填充双绘）
        if (outlineWidth_ > 0) {
            QPen outline(outlineColor_);
            outline.setWidthF(outlineWidth_);
            painter->setPen(outline);
            painter->drawText(baseline, text);
        }
        painter->setPen(QPen(fill));
        painter->drawText(baseline, text);
    }
}
