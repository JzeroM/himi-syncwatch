#include "danmaku_paint_item.h"

#include <QFont>
#include <QFontMetrics>
#include <QPainter>
#include <QQuickWindow>
#include <QPen>

namespace {
// 对齐安卓 DanmakuLayerView：固定弹幕驻留 4000ms（fixedMs）。
constexpr double kFixedMs = 4000.0;
}  // namespace

DanmakuPaintItem::DanmakuPaintItem(QQuickItem* parent)
    : QQuickPaintedItem(parent)
{
    refreshFontCache(); // 698 N62：字体缓存初始化
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

void DanmakuPaintItem::setPositionMs(qlonglong v)
{
    if (positionMs_ == v) return;
    positionMs_ = v;
    emit positionMsChanged();
    update();
}

void DanmakuPaintItem::setTravelMs(double v)
{
    if (qFuzzyCompare(travelMs_, v)) return;
    travelMs_ = v;
    emit travelMsChanged();
    update();
}

void DanmakuPaintItem::setContentOpacity(double v)
{
    if (qFuzzyCompare(contentOpacity_, v)) return;
    contentOpacity_ = v;
    emit contentOpacityChanged();
    update();
}

void DanmakuPaintItem::setEdgePadding(double v)
{
    if (qFuzzyCompare(edgePadding_, v)) return;
    edgePadding_ = v;
    emit edgePaddingChanged();
    update();
}

void DanmakuPaintItem::setLineHeight(double v)
{
    if (qFuzzyCompare(lineHeight_, v)) return;
    lineHeight_ = v;
    emit lineHeightChanged();
    update();
}

void DanmakuPaintItem::setPoolCap(int v)
{
    if (poolCap_ == v) return;
    poolCap_ = v;
    emit poolCapChanged();
    update();
}

void DanmakuPaintItem::setFontSize(int v)
{
    if (fontSize_ == v) return;
    fontSize_ = v;
    refreshFontCache();
    emit fontSizeChanged();
    update();
}

void DanmakuPaintItem::setOutlineWidth(double v)
{
    if (qFuzzyCompare(outlineWidth_, v)) return;
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

double DanmakuPaintItem::fixedFade(double progress)
{
    if (progress < 0.1) return progress / 0.1;
    if (progress > 0.9) return (1.0 - progress) / 0.1;
    return 1.0;
}

void DanmakuPaintItem::paint(QPainter* painter)
{
    if (items_.isEmpty()) return;
    // 698 N62：QFont 缓存（成员化，不再每帧新建）+ 高 dpr 自适应
    // （高缩放屏字体光栅已平滑，全抗锯齿是多余开销——设备卡顿差异）。
    const qreal dpr = window() ? window()->devicePixelRatio() : 1.0;
    painter->setRenderHint(QPainter::TextAntialiasing, dpr < 1.5);
    painter->setFont(cachedFont_);
    const qreal ascent = cachedAscent_;
    const qreal w = width();
    const qreal h = height();

    // 696：投影在绘制侧现算（对齐安卓 Canvas 按时钟算坐标）——items 是
    // 静态数据，每帧只进来一个 positionMs，零 QML/QVariantList 每帧转换。
    // 公式与旧 DanmakuLayer.tick() 的 out.push 逐字等价。
    int drawn = 0;
    for (const QVariant& v : items_) {
        const QVariantMap m = v.toMap();
        const QString text = m.value(QStringLiteral("text")).toString();
        if (text.isEmpty()) continue;
        const QString mode = m.value(QStringLiteral("mode")).toString();
        const bool isFixed =
            mode == QLatin1String("top") || mode == QLatin1String("bottom");
        const qint64 timeMs = m.value(QStringLiteral("timeMs")).toLongLong();
        const double life = isFixed ? kFixedMs : travelMs_;
        const double elapsed = static_cast<double>(positionMs_ - timeMs);
        if (elapsed < 0 || elapsed > life) continue;
        const double progress = elapsed / life;
        const qreal textW = m.value(QStringLiteral("textW")).toReal();
        const int lane = m.value(QStringLiteral("lane")).toInt();

        qreal x;
        if (mode == QLatin1String("scroll")) {
            x = w - progress * (w + textW);
        } else {
            x = (w - textW) / 2;
        }
        qreal y;
        if (mode == QLatin1String("bottom")) {
            y = h - edgePadding_ - (lane + 1) * lineHeight_;
        } else {
            y = edgePadding_ + lane * lineHeight_;
        }
        double alpha = contentOpacity_ * (isFixed ? fixedFade(progress) : 1.0);
        if (alpha < 0) alpha = 0;
        if (alpha > 1) alpha = 1;

        QColor fill(m.value(QStringLiteral("color")).toString());
        fill.setAlphaF(fill.alphaF() * alpha);
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

        if (++drawn >= poolCap_) break;
    }
}
