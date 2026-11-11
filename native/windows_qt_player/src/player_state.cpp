#include "player_state.h"

#include <QJsonArray>
#include <QJsonValue>
#include <QVariantList>
#include <QVariantMap>

namespace {

/// 只在值真的变化时赋值并返回 true（避免无谓的 QML 重绑定）。
template <typename T>
bool assign(T& target, const T& value) {
    if (target == value) return false;
    target = value;
    return true;
}

qint64 readInt64(const QJsonObject& json, const char* key, qint64 fallback) {
    const QJsonValue v = json.value(QLatin1String(key));
    if (v.isDouble()) return static_cast<qint64>(v.toDouble());
    if (v.isString()) return v.toString().toLongLong();
    return fallback;
}

double readDouble(const QJsonObject& json, const char* key, double fallback) {
    const QJsonValue v = json.value(QLatin1String(key));
    return v.isDouble() ? v.toDouble() : fallback;
}

bool readBool(const QJsonObject& json, const char* key, bool fallback) {
    const QJsonValue v = json.value(QLatin1String(key));
    return v.isBool() ? v.toBool() : fallback;
}

QString readString(const QJsonObject& json, const char* key,
                   const QString& fallback = QString()) {
    const QJsonValue v = json.value(QLatin1String(key));
    return v.isString() ? v.toString() : fallback;
}

}  // namespace

PlayerState::PlayerState(QObject* parent) : QObject(parent) {}

void PlayerState::setControlsVisible(bool visible) {
    if (controlsVisible_ == visible) return;
    controlsVisible_ = visible;
    emit controlsVisibleChanged();
}

void PlayerState::setWindowDiag(const QString& diag) {
    if (windowDiag_ == diag) return;
    windowDiag_ = diag;
    emit windowDiagChanged();
}

void PlayerState::patchValue(const QString& key, const QVariant& value) {
    // 672：本地镜像（滑杆 moved/面板点选/恢复默认即时写）——绑定松手
    // 写回的是这些值，镜像新则永不跳位/冻结。
    if (key == QLatin1String("volume")) {
        volume_ = value.toDouble();
    } else if (key == QLatin1String("speed")) {
        speed_ = value.toDouble();
    } else if (key == QLatin1String("brightness")) {
        brightness_ = value.toDouble();
    } else if (key == QLatin1String("subtitleScale")) {
        subtitleScale_ = value.toDouble();
    } else if (key == QLatin1String("subtitleMarginY")) {
        subtitleMarginY_ = value.toInt();
    } else if (key == QLatin1String("subtitleDelayMs")) {
        subtitleDelayMs_ = value.toDouble();
    } else if (key == QLatin1String("danmakuSpeed")) {
        danmakuSpeed_ = value.toDouble();
    } else if (key == QLatin1String("danmakuFontSize")) {
        danmakuFontSize_ = value.toDouble();
    } else if (key == QLatin1String("danmakuOpacity")) {
        danmakuOpacity_ = value.toDouble();
    } else if (key == QLatin1String("decodeMode")) {
        decodeMode_ = value.toString();
    } else if (key == QLatin1String("videoFit")) {
        videoFit_ = value.toString();
    } else if (key == QLatin1String("danmakuEnabled")) {
        danmakuEnabled_ = value.toBool();
    } else if (key == QLatin1String("selectedAudioId")) {
        selectedAudioId_ = value.toInt();
    } else if (key == QLatin1String("selectedSubtitleId")) {
        selectedSubtitleId_ = value.toInt();
    } else if (key == QLatin1String("currentEpisodeIndex")) {
        currentEpisodeIndex_ = value.toInt();
    } else if (key == QLatin1String("currentVersionIndex")) {
        currentVersionIndex_ = value.toInt();
    } else if (key == QLatin1String("positionMs")) {
        positionMs_ = value.toLongLong();
    } else if (key == QLatin1String("skipPrompt")) {
        skipPrompt_ = value.toString();
    } else {
        return;
    }
    emit changed();
}

void PlayerState::applyJson(const QJsonObject& json) {
    if (json.isEmpty()) return;

    bool dirty = false;

    // ── 播放 ──
    dirty |= assign(positionMs_, readInt64(json, "positionMs", positionMs_));
    dirty |= assign(durationMs_, readInt64(json, "durationMs", durationMs_));
    dirty |= assign(paused_, readBool(json, "paused", paused_));
    dirty |= assign(volume_, readDouble(json, "volume", volume_));
    dirty |= assign(speed_, readDouble(json, "speed", speed_));
    dirty |= assign(buffering_, readBool(json, "buffering", buffering_));
    dirty |= assign(showLoading_, readBool(json, "showLoading", showLoading_));
    dirty |= assign(playerReady_, readBool(json, "playerReady", playerReady_));

    // ── 媒体 ──
    dirty |= assign(title_, readString(json, "title", title_));
    dirty |= assign(mediaTitle_, readString(json, "mediaTitle", mediaTitle_));

    // ── 顶栏 ──
    dirty |= assign(engineLabel_, readString(json, "engineLabel", engineLabel_));
    dirty |= assign(networkSpeedText_,
                    readString(json, "networkSpeedText", networkSpeedText_));
    dirty |= assign(videoFit_, readString(json, "videoFit", videoFit_));
    dirty |= assign(decodeMode_, readString(json, "decodeMode", decodeMode_));
    dirty |= assign(glassUi_, readBool(json, "glassUi", glassUi_));
    dirty |= assign(isRoom_, readBool(json, "isRoom", isRoom_));
    dirty |= assign(onlineUserCount_,
                    static_cast<int>(readInt64(json, "onlineUserCount",
                                               onlineUserCount_)));
    dirty |= assign(isHost_, readBool(json, "isHost", isHost_));
    dirty |= assign(clockFormat_, readString(json, "clockFormat", clockFormat_));

    // ── Logo（660）──
    dirty |= assign(logoUrl_, readString(json, "logoUrl", logoUrl_));

    // ── 亮度（660，0.0 ~ 1.0）──
    dirty |= assign(brightness_,
                    readDouble(json, "brightness", brightness_));

    // ── 弹幕 ──
    dirty |= assign(danmakuEnabled_,
                    readBool(json, "danmakuEnabled", danmakuEnabled_));

    // ── 输出诊断 ──
    dirty |= assign(hdrOutput_, readBool(json, "hdrOutput", hdrOutput_));
    dirty |= assign(videoOutputActual_,
                    readString(json, "videoOutputActual", videoOutputActual_));

    // ── 选集 ──
    const QJsonValue eps = json.value(QLatin1String("episodes"));
    if (eps.isArray()) setEpisodes(eps.toArray());

    dirty |= assign(currentEpisodeIndex_,
                    static_cast<int>(readInt64(json, "currentEpisodeIndex",
                                               currentEpisodeIndex_)));

    // ── 多版本（662）──
    const QJsonValue vers = json.value(QLatin1String("versions"));
    if (vers.isArray()) setVersions(vers.toArray());

    dirty |= assign(currentVersionIndex_,
                    static_cast<int>(readInt64(json, "currentVersionIndex",
                                               currentVersionIndex_)));

    // ── 屏幕锁定（662，Flutter toggleLock 命令回写）──
    dirty |= assign(locked_, readBool(json, "locked", locked_));

    // ── 弹幕/片段（665）──
    const QJsonValue danm = json.value(QLatin1String("danmakuItems"));
    if (danm.isArray()) setDanmakuItems(danm.toArray());
    // null = 无片段；-1 为缺省
    if (json.contains(QLatin1String("segmentIntroEndMs"))) {
        const QJsonValue v =
            json.value(QLatin1String("segmentIntroEndMs"));
        dirty |= assign(segmentIntroEndMs_,
                        v.isDouble() ? static_cast<qint64>(v.toDouble())
                                     : static_cast<qint64>(-1));
    }
    if (json.contains(QLatin1String("segmentOutroStartMs"))) {
        const QJsonValue v =
            json.value(QLatin1String("segmentOutroStartMs"));
        dirty |= assign(segmentOutroStartMs_,
                        v.isDouble() ? static_cast<qint64>(v.toDouble())
                                     : static_cast<qint64>(-1));
    }

    // ── 显示调节（662）──
    //
    // 字幕大小在协议里是 `subtitleStyle.fontSize`（16.0 = 1.0×基准），
    // 与 Flutter `_applyNativeSubtitleStyle` 的换算一致（scale = fontSize/16）。
    const QJsonValue style = json.value(QLatin1String("subtitleStyle"));
    if (style.isObject()) {
        const double fontSize =
            readDouble(style.toObject(), "fontSize", subtitleScale_ * 16.0);
        dirty |= assign(subtitleScale_, fontSize / 16.0);
    }
    dirty |= assign(subtitleMarginY_,
                    static_cast<int>(readInt64(json, "subtitleMarginY",
                                               subtitleMarginY_)));
    dirty |= assign(subtitleDelayMs_,
                    readDouble(json, "subtitleDelayMs", subtitleDelayMs_));
    dirty |= assign(danmakuSpeed_,
                    readDouble(json, "danmakuSpeed", danmakuSpeed_));
    dirty |= assign(danmakuFontSize_,
                    readDouble(json, "danmakuFontSize", danmakuFontSize_));
    dirty |= assign(danmakuOpacity_,
                    readDouble(json, "danmakuOpacity", danmakuOpacity_));

    // ── 轨道 ──
    const QJsonValue tracks = json.value(QLatin1String("tracks"));
    if (tracks.isArray()) setTracks(tracks.toArray());
    // 672：轨道选中真相（顶层 id，与安卓/鸿蒙同源）+ 跳过提示
    selectedAudioId_ = static_cast<int>(readInt64(json, "selectedAudioId", selectedAudioId_));
    selectedSubtitleId_ = static_cast<int>(readInt64(json, "selectedSubtitleId", selectedSubtitleId_));
    const QString sp = readString(json, "skipPrompt");
    if (json.contains(QLatin1String("skipPrompt"))) skipPrompt_ = sp;

    if (dirty) emit changed();
}

void PlayerState::setEpisodes(const QJsonArray& arr) {
    QList<Episode> next;
    next.reserve(arr.size());
    for (const QJsonValue& v : arr) {
        if (!v.isObject()) continue;
        const QJsonObject o = v.toObject();
        Episode e;
        e.index = static_cast<int>(readInt64(o, "index", 0));
        e.title = readString(o, "title");
        e.poster = readString(o, "poster");
        e.number = static_cast<int>(readInt64(o, "number", 0));
        next.append(e);
    }
    // 列表整体替换：逐项比较代价高且收益小（剧集数通常 < 100）。
    // 但**内容相同就不要发信号**，否则 20Hz 推送会让 ListView 反复重建。
    bool same = next.size() == episodes_.size();
    if (same) {
        for (int i = 0; i < next.size(); ++i) {
            if (next[i].index != episodes_[i].index ||
                next[i].title != episodes_[i].title ||
                next[i].poster != episodes_[i].poster ||
                next[i].number != episodes_[i].number) {
                same = false;
                break;
            }
        }
    }
    if (same) return;
    episodes_ = next;
    emit episodesChanged();
}

void PlayerState::setTracks(const QJsonArray& arr) {
    QList<Track> audio;
    QList<Track> subtitle;
    for (const QJsonValue& v : arr) {
        if (!v.isObject()) continue;
        const QJsonObject o = v.toObject();
        Track t;
        t.id = static_cast<int>(readInt64(o, "id", 0));
        t.type = readString(o, "type");
        t.title = readString(o, "title");
        t.lang = readString(o, "lang");
        t.label = readString(o, "label");
        t.selected = readBool(o, "selected", false);
        if (t.type == QLatin1String("audio")) {
            audio.append(t);
        } else if (t.type == QLatin1String("subtitle")) {
            subtitle.append(t);
        }
    }

    auto sameList = [](const QList<Track>& a, const QList<Track>& b) {
        if (a.size() != b.size()) return false;
        for (int i = 0; i < a.size(); ++i) {
            if (a[i].id != b[i].id || a[i].title != b[i].title ||
                a[i].label != b[i].label || a[i].selected != b[i].selected) {
                return false;
            }
        }
        return true;
    };

    if (sameList(audio, audioTracks_) && sameList(subtitle, subtitleTracks_)) {
        return;
    }
    audioTracks_ = audio;
    subtitleTracks_ = subtitle;
    emit tracksChanged();
}

void PlayerState::setVersions(const QJsonArray& arr) {
    QList<Version> next;
    next.reserve(arr.size());
    for (const QJsonValue& v : arr) {
        if (!v.isObject()) continue;
        const QJsonObject o = v.toObject();
        Version ver;
        ver.index = static_cast<int>(readInt64(o, "index", 0));
        ver.title = readString(o, "title");
        next.append(ver);
    }
    // 与 setEpisodes 同策略：内容相同不发信号（20Hz 推送防重建）。
    bool same = next.size() == versions_.size();
    if (same) {
        for (int i = 0; i < next.size(); ++i) {
            if (next[i].index != versions_[i].index ||
                next[i].title != versions_[i].title) {
                same = false;
                break;
            }
        }
    }
    if (same) return;
    versions_ = next;
    emit versionsChanged();
}

void PlayerState::setDanmakuItems(const QJsonArray& arr) {
    QList<Danmaku> next;
    next.reserve(arr.size());
    for (const QJsonValue& v : arr) {
        if (!v.isObject()) continue;
        const QJsonObject o = v.toObject();
        Danmaku d;
        d.timeMs = static_cast<qint64>(readInt64(o, "timeMs", 0));
        d.text = readString(o, "text");
        d.mode = readString(o, "mode", QStringLiteral("scroll"));
        d.color = readString(o, "color", QStringLiteral("#FFFFFF"));
        if (!d.text.isEmpty()) next.append(d);
    }
    bool same = next.size() == danmakuItems_.size();
    if (same) {
        for (int i = 0; i < next.size(); ++i) {
            if (next[i].timeMs != danmakuItems_[i].timeMs ||
                next[i].text != danmakuItems_[i].text ||
                next[i].mode != danmakuItems_[i].mode ||
                next[i].color != danmakuItems_[i].color) {
                same = false;
                break;
            }
        }
    }
    if (same) return;
    danmakuItems_ = next;
    emit danmakuChanged();
}

QVariantList PlayerState::danmakuItemsVariant() const {
    QVariantList out;
    out.reserve(danmakuItems_.size());
    for (const Danmaku& d : danmakuItems_) {
        QVariantMap m;
        m.insert(QStringLiteral("timeMs"),
                 static_cast<qlonglong>(d.timeMs));
        m.insert(QStringLiteral("text"), d.text);
        m.insert(QStringLiteral("mode"), d.mode);
        m.insert(QStringLiteral("color"), d.color);
        out.append(m);
    }
    return out;
}

QVariantList PlayerState::versionsVariant() const {
    QVariantList out;
    out.reserve(versions_.size());
    for (const Version& v : versions_) {
        QVariantMap m;
        m.insert(QStringLiteral("index"), v.index);
        m.insert(QStringLiteral("title"), v.title);
        out.append(m);
    }
    return out;
}

QVariantList PlayerState::episodesVariant() const {
    QVariantList out;
    out.reserve(episodes_.size());
    for (const Episode& e : episodes_) {
        QVariantMap m;
        m.insert(QStringLiteral("index"), e.index);
        m.insert(QStringLiteral("title"), e.title);
        m.insert(QStringLiteral("poster"), e.poster);
        m.insert(QStringLiteral("number"), e.number);
        out.append(m);
    }
    return out;
}

QVariantList PlayerState::audioTracksVariant() const {
    QVariantList out;
    out.reserve(audioTracks_.size());
    for (const Track& t : audioTracks_) {
        QVariantMap m;
        m.insert(QStringLiteral("id"), t.id);
        m.insert(QStringLiteral("type"), t.type);
        m.insert(QStringLiteral("title"), t.title);
        m.insert(QStringLiteral("lang"), t.lang);
        m.insert(QStringLiteral("label"), t.label);
        m.insert(QStringLiteral("selected"), t.selected);
        out.append(m);
    }
    return out;
}

QVariantList PlayerState::subtitleTracksVariant() const {
    QVariantList out;
    out.reserve(subtitleTracks_.size());
    for (const Track& t : subtitleTracks_) {
        QVariantMap m;
        m.insert(QStringLiteral("id"), t.id);
        m.insert(QStringLiteral("type"), t.type);
        m.insert(QStringLiteral("title"), t.title);
        m.insert(QStringLiteral("lang"), t.lang);
        m.insert(QStringLiteral("label"), t.label);
        m.insert(QStringLiteral("selected"), t.selected);
        out.append(m);
    }
    return out;
}
