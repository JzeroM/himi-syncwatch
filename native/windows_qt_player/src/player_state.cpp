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

PlayerState::PlayerState(QObject* parent) : QObject(parent) {
    // 【必须启动】未 start 的 QElapsedTimer 调 nsecsElapsed() 是未定义行为
    //（Qt 文档：timer 无效时返回值无意义）。弹幕时钟全程依赖它。
    dmAnchorTimer_.start();
}

void PlayerState::setDebugText(const QString& text) {
    // 内容相同不发信号——否则 2s 定时器每次都触发 QML 重绘
    if (debugText_ == text) return;
    debugText_ = text;
    emit debugTextChanged();
}

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
    } else if (key == QLatin1String("danmakuColorMode")) {
        danmakuColorMode_ = value.toString();
    } else if (key == QLatin1String("danmakuCustomColor")) {
        danmakuCustomColor_ = value.toInt();
    } else if (key == QLatin1String("danmakuOutlineWidth")) {
        danmakuOutlineWidth_ = value.toDouble();
    } else if (key == QLatin1String("danmakuOutlineColor")) {
        danmakuOutlineColor_ = value.toInt();
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
    localKeys_.insert(key);  // 675 A：本地置顶
    danmakuClockSync();      // 本地乐观改动（seek/暂停/倍速）也要重对齐
    emit changed();
}

void PlayerState::applyJson(const QJsonObject& jsonIn, bool remote) {
    // 675 A：本地置顶——patchValue 写过的字段忽略远端过期推送
    //（远端只补未动过的初值；mpv 事件的本地补丁走默认 false 照常生效）。
    QJsonObject json = jsonIn;
    if (remote) {
        for (const QString& k : localKeys_) json.remove(k);
    }
    if (json.isEmpty()) return;

    bool dirty = false;

    // ── 播放 ──
    dirty |= assign(positionMs_, readInt64(json, "positionMs", positionMs_));
    dirty |= assign(durationMs_, readInt64(json, "durationMs", durationMs_));
    dirty |= assign(bufferedMs_, readInt64(json, "bufferedMs", bufferedMs_));
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
    dirty |= assign(mediaInfoJson_,
                    readString(json, "mediaInfoJson", mediaInfoJson_));
    dirty |= assign(videoFit_, readString(json, "videoFit", videoFit_));
    dirty |= assign(decodeMode_, readString(json, "decodeMode", decodeMode_));
    dirty |= assign(glassUi_, readBool(json, "glassUi", glassUi_));
    dirty |= assign(isRoom_, readBool(json, "isRoom", isRoom_));
    dirty |= assign(onlineUserCount_,
                    static_cast<int>(readInt64(json, "onlineUserCount",
                                               onlineUserCount_)));
    dirty |= assign(isHost_, readBool(json, "isHost", isHost_));
    dirty |= assign(clockFormat_, readString(json, "clockFormat", clockFormat_));
    // 677：房间观众权限（对齐安卓/鸿蒙原生 UI 的 canControl / segmentEnabled）
    dirty |= assign(canControl_, readBool(json, "canControl", canControl_));
    dirty |= assign(segmentEnabled_,
                    readBool(json, "segmentEnabled", segmentEnabled_));

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

    // ── 697：HDR/DV 调试指标（播放调试面板用）──
    dirty |= assign(videoParamsPrimaries_,
                    readString(json, "videoParamsPrimaries",
                               videoParamsPrimaries_));
    dirty |= assign(videoParamsGamma_,
                    readString(json, "videoParamsGamma", videoParamsGamma_));
    dirty |= assign(videoParamsSigPeak_,
                    readDouble(json, "videoParamsSigPeak",
                               videoParamsSigPeak_));
    dirty |= assign(videoParamsBitDepth_,
                    static_cast<int>(readInt64(json, "videoParamsBitDepth",
                                               videoParamsBitDepth_)));
    dirty |= assign(videoParamsPixelFormat_,
                    readString(json, "videoParamsPixelFormat",
                               videoParamsPixelFormat_));
    dirty |= assign(doviProfile_,
                    static_cast<int>(readInt64(json, "doviProfile",
                                               doviProfile_)));
    dirty |= assign(doviLevel_,
                    static_cast<int>(readInt64(json, "doviLevel",
                                               doviLevel_)));
    dirty |= assign(dvContent_,
                    readBool(json, "dvContent", dvContent_));
    dirty |= assign(targetPrim_,
                    readString(json, "targetPrim", targetPrim_));
    dirty |= assign(targetTrc_,
                    readString(json, "targetTrc", targetTrc_));
    dirty |= assign(toneMapping_,
                    readString(json, "toneMapping", toneMapping_));
    dirty |= assign(toneMappingMode_,
                    readString(json, "toneMappingMode", toneMappingMode_));
    dirty |= assign(hdrComputePeak_,
                    readString(json, "hdrComputePeak", hdrComputePeak_));
    dirty |= assign(currentVo_,
                    readString(json, "currentVo", currentVo_));
    dirty |= assign(gpuApi_,
                    readString(json, "gpuApi", gpuApi_));
    dirty |= assign(gpuContext_,
                    readString(json, "gpuContext", gpuContext_));
    dirty |= assign(estimatedVfFps_,
                    readDouble(json, "estimatedVfFps", estimatedVfFps_));
    dirty |= assign(frameDropCount_,
                    static_cast<int>(readInt64(json, "frameDropCount",
                                               frameDropCount_)));
    dirty |= assign(decoderFrameDropCount_,
                    static_cast<int>(readInt64(json,
                                               "decoderFrameDropCount",
                                               decoderFrameDropCount_)));
    dirty |= assign(hwdecCurrent_,
                    readString(json, "hwdecCurrent", hwdecCurrent_));
    dirty |= assign(videoFormat_,
                    readString(json, "videoFormat", videoFormat_));
    dirty |= assign(showDebug_, readBool(json, "showDebug", showDebug_));
    dirty |= assign(anime4kStatus_,
                    readString(json, "anime4kStatus", anime4kStatus_));
    dirty |= assign(anime4kEnabled_,
                    readBool(json, "anime4kEnabled", anime4kEnabled_));

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
    // 694 M3：弹幕弹窗状态
    dirty |= assign(danmakuBinding_,
                    readString(json, "danmakuBinding", danmakuBinding_));
    dirty |= assign(danmakuSearching_,
                    readBool(json, "danmakuSearching", danmakuSearching_));
    dirty |= assign(danmakuSearchError_,
                    readString(json, "danmakuSearchError",
                               danmakuSearchError_));
    const QJsonValue hits = json.value(QLatin1String("danmakuSearchResults"));
    if (hits.isArray()) setDanmakuSearchResults(hits.toArray());
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
    dirty |= assign(danmakuTotal_,
                    static_cast<int>(readInt64(json, "danmakuTotal",
                                               danmakuTotal_)));
    dirty |= assign(danmakuOnscreen_,
                    static_cast<int>(readInt64(json, "danmakuOnscreen",
                                               danmakuOnscreen_)));
    dirty |= assign(danmakuColorMode_,
                    readString(json, "danmakuColorMode", danmakuColorMode_));
    dirty |= assign(danmakuCustomColor_,
                    static_cast<int>(readInt64(json, "danmakuCustomColor",
                                               danmakuCustomColor_)));
    dirty |= assign(danmakuOutlineWidth_,
                    readDouble(json, "danmakuOutlineWidth", danmakuOutlineWidth_));
    dirty |= assign(danmakuOutlineColor_,
                    static_cast<int>(readInt64(json, "danmakuOutlineColor",
                                               danmakuOutlineColor_)));
    // 697：弹幕行数（QML 自绘层用；对齐 Flutter AppSettings）
    dirty |= assign(danmakuScrollRows_,
                    static_cast<int>(readInt64(json, "danmakuScrollRows",
                                               danmakuScrollRows_)));
    dirty |= assign(danmakuTopRows_,
                    static_cast<int>(readInt64(json, "danmakuTopRows",
                                               danmakuTopRows_)));
    dirty |= assign(danmakuBottomRows_,
                    static_cast<int>(readInt64(json, "danmakuBottomRows",
                                               danmakuBottomRows_)));

    // ── 轨道 ──
    const QJsonValue tracks = json.value(QLatin1String("tracks"));
    if (tracks.isArray()) setTracks(tracks.toArray());
    // 672：轨道选中真相（顶层 id，与安卓/鸿蒙同源）+ 跳过提示
    selectedAudioId_ = static_cast<int>(readInt64(json, "selectedAudioId", selectedAudioId_));
    selectedSubtitleId_ = static_cast<int>(readInt64(json, "selectedSubtitleId", selectedSubtitleId_));
    const QString sp = readString(json, "skipPrompt");
    // 693：**必须走 `assign` 置 dirty**。
    //
    // 【真机回归：跳过片头/片尾胶囊完全不显示】此前是裸赋值
    // `skipPrompt_ = sp`——不置 `dirty`，函数末尾的 `if (dirty) emit
    // changed()` 就不发射。QML 的 `playerState.skipPrompt` 绑定**永不
    // 重新求值**，胶囊的 `visible` 条件形同虚设。
    //
    // 这是全文件唯一漏掉 `assign` 的字段（其它都有独立 setter + emit）。
    if (json.contains(QLatin1String("skipPrompt"))) {
        dirty |= assign(skipPrompt_, sp);
    }

    if (dirty) {
        danmakuClockSync();
        emit changed();
    }
}

// ── 弹幕时钟（P1）──────────────────────────────────────────────
//
// 规则与 Dart `DanmakuClock`、安卓 `DanmakuLayerView`、鸿蒙
// `HimiMpvNativeHost.danmakuPositionNowMs()` 完全同构：
//
//   误差 ≤40ms  → 不修正（死区，避免来回微抖）
//   40~400ms   → 不改锚点，只把速率调 ±5%，让误差在 ~600ms 内消化
//   >400ms     → seek / 卡顿恢复，允许瞬移
//
// 【换速率前必须先重锚】投影是 `anchorPos + elapsed × rate`，直接改 rate
// 会把整段 elapsed 重新缩放 → 位置瞬间回退（真机表现为抽搐）。

qint64 PlayerState::danmakuPositionMs() const
{
    if (dmPaused_ || dmEffRate_ <= 0.0) return dmAnchorPosMs_;
    if (dmDurationMs_ <= 0) return dmAnchorPosMs_;
    // 防御：计时器未启动时 nsecsElapsed() 无意义，直接返回锚点。
    if (!dmAnchorTimer_.isValid()) return dmAnchorPosMs_;
    const double elapsedMs =
        static_cast<double>(dmAnchorTimer_.nsecsElapsed()) / 1e6;
    qint64 projected = dmAnchorPosMs_ +
        static_cast<qint64>(elapsedMs * dmEffRate_);
    if (dmDurationMs_ > 0 && projected > dmDurationMs_) projected = dmDurationMs_;
    return projected < 0 ? 0 : projected;
}

void PlayerState::danmakuClockHardResync()
{
    // 【buffering 不算暂停】缓冲时播放位置仍在推进（mpv 只是解码等待），
    // 把 buffering 当暂停会让弹幕时钟永久冻在锚点 → 时间窗全被判为
    // 「超前过多」而丢弃 → 一条都画不出来（真机：面板有在屏数、画面空白）。
    const bool paused = paused_ || speed_ <= 0.0;
    const double rate = speed_ > 0.0 ? speed_ : 1.0;
    dmAnchorPosMs_ = positionMs_ < 0 ? 0 : positionMs_;
    dmAnchorTimer_.restart();
    dmPaused_ = paused;
    dmBaseRate_ = rate;
    dmEffRate_ = paused ? 0.0 : rate;
    if (durationMs_ > 0) dmDurationMs_ = durationMs_;
    dmErrorMs_ = 0;
    ++dmHardResyncs_;
}

void PlayerState::danmakuClockSync()
{
    // 同 hardResync：buffering 不冻结弹幕时钟。
    const bool paused = paused_ || speed_ <= 0.0;
    const double rate = speed_ > 0.0 ? speed_ : 1.0;
    if (durationMs_ > 0) dmDurationMs_ = durationMs_;

    // 语义变化（暂停/恢复、倍速）：直接重锚。
    if (paused || paused != dmPaused_ || rate != dmBaseRate_) {
        danmakuClockHardResync();
        return;
    }

    const qint64 err = positionMs_ - danmakuPositionMs();
    dmErrorMs_ = static_cast<int>(err);
    if (err > 400 || err < -400) {
        danmakuClockHardResync();
        return;
    }

    // 先重锚保证位置连续，再改斜率。
    dmAnchorPosMs_ = danmakuPositionMs();
    dmAnchorTimer_.restart();
    dmBaseRate_ = rate;
    if (err > 40 || err < -40) {
        double adj = static_cast<double>(err) / 600.0;
        if (adj > 0.05) adj = 0.05;
        if (adj < -0.05) adj = -0.05;
        dmEffRate_ = rate + adj;
    } else {
        dmEffRate_ = rate;
    }
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
        } else if (t.type == QLatin1String("subtitle") ||
                   // 675 C：Dart 侧 NativeTrack 字幕类型是 'sub'（安卓
                   // 同源）——只认 'subtitle' 会把全部字幕轨丢弃
                   //（真机回归「已有字幕未显示」）。
                   t.type == QLatin1String("sub")) {
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

// 694 M3：弹幕弹窗搜索结果（episodeId/animeTitle/episodeTitle）。
void PlayerState::setDanmakuSearchResults(const QJsonArray& arr) {
    QList<SearchHit> next;
    next.reserve(arr.size());
    for (const QJsonValue& v : arr) {
        if (!v.isObject()) continue;
        const QJsonObject o = v.toObject();
        SearchHit h;
        h.episodeId = static_cast<int>(readInt64(o, "episodeId", 0));
        h.animeTitle = readString(o, "animeTitle");
        h.episodeTitle = readString(o, "episodeTitle");
        next.append(h);
    }
    bool same = next.size() == danmakuSearchResults_.size();
    if (same) {
        for (int i = 0; i < next.size(); ++i) {
            if (next[i].episodeId != danmakuSearchResults_[i].episodeId ||
                next[i].animeTitle != danmakuSearchResults_[i].animeTitle ||
                next[i].episodeTitle !=
                    danmakuSearchResults_[i].episodeTitle) {
                same = false;
                break;
            }
        }
    }
    if (same) return;
    danmakuSearchResults_ = next;
    emit danmakuChanged();
}

QVariantList PlayerState::danmakuSearchResultsVariant() const {
    QVariantList out;
    out.reserve(danmakuSearchResults_.size());
    for (const SearchHit& h : danmakuSearchResults_) {
        QVariantMap m;
        m.insert(QStringLiteral("episodeId"), h.episodeId);
        m.insert(QStringLiteral("animeTitle"), h.animeTitle);
        m.insert(QStringLiteral("episodeTitle"), h.episodeTitle);
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

