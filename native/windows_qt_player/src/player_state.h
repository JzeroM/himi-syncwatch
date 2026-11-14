#ifndef PLAYER_STATE_H
#define PLAYER_STATE_H

#include <QJsonObject>
#include <QList>
#include <QSet>
#include <QObject>
#include <QString>
#include <QVariantList>

/// 656：Flutter 推送的播放器状态（只取 UI 需要的字段）。
///
/// 【协议来源】`lib/services/player/native/native_player_state.dart` 的
/// `NativePlayerState.toJson()`，共 87 个字段。安卓（Compose）与鸿蒙
/// （ArkUI）原生 UI 消费的是**同一份**，所以三端观感天然一致。
///
/// 【为什么不解析全部 87 个】Qt 只做「播放器窗口 + 控件」，不需要
/// `debugLines` / `resourceGroups` / `segmentIntroEndMs` 这些房间与
/// 调试专用字段。按需取用能显著降低 QML 侧复杂度，也避免 Flutter 端
/// 加字段时被迫同步改 C++。
class PlayerState : public QObject {
    Q_OBJECT

    // ── 播放 ──
    Q_PROPERTY(qint64 positionMs READ positionMs NOTIFY changed)
    Q_PROPERTY(qint64 durationMs READ durationMs NOTIFY changed)
    /// 697：已缓冲毫秒数（调试面板显示）。
    Q_PROPERTY(qint64 bufferedMs READ bufferedMs NOTIFY changed)
    Q_PROPERTY(bool paused READ paused NOTIFY changed)
    Q_PROPERTY(double volume READ volume NOTIFY changed)
    Q_PROPERTY(double speed READ speed NOTIFY changed)
    Q_PROPERTY(bool buffering READ buffering NOTIFY changed)
    Q_PROPERTY(bool showLoading READ showLoading NOTIFY changed)
    Q_PROPERTY(bool playerReady READ playerReady NOTIFY changed)

    // ── 媒体 ──
    Q_PROPERTY(QString title READ title NOTIFY changed)
    Q_PROPERTY(QString mediaTitle READ mediaTitle NOTIFY changed)

    // ── 顶栏 ──
    Q_PROPERTY(QString engineLabel READ engineLabel NOTIFY changed)
    Q_PROPERTY(QString networkSpeedText READ networkSpeedText NOTIFY changed)
    Q_PROPERTY(QString videoFit READ videoFit NOTIFY changed)
    Q_PROPERTY(QString decodeMode READ decodeMode NOTIFY changed)
    Q_PROPERTY(bool glassUi READ glassUi NOTIFY changed)
    Q_PROPERTY(bool isRoom READ isRoom NOTIFY changed)
    Q_PROPERTY(int onlineUserCount READ onlineUserCount NOTIFY changed)
    Q_PROPERTY(bool isHost READ isHost NOTIFY changed)
    Q_PROPERTY(QString clockFormat READ clockFormat NOTIFY changed)

    // ── 剧集 Logo（660，照 Flutter）──
    Q_PROPERTY(QString logoUrl READ logoUrl NOTIFY changed)

    // ── 亮度（660，照 Flutter 播放页亮度滑杆）──
    Q_PROPERTY(double brightness READ brightness NOTIFY changed)

    // ── 多版本（662，照 Flutter 底栏「多版本」按钮）──
    Q_PROPERTY(QVariantList versions READ versionsVariant NOTIFY versionsChanged)
    Q_PROPERTY(int versionCount READ versionCount NOTIFY versionsChanged)
    Q_PROPERTY(int currentVersionIndex READ currentVersionIndex NOTIFY changed)

    // ── 显示调节回读（662，照 Flutter「显示调节」面板六滑杆）──
    Q_PROPERTY(double subtitleScale READ subtitleScale NOTIFY changed)
    Q_PROPERTY(int subtitleMarginY READ subtitleMarginY NOTIFY changed)
    Q_PROPERTY(double subtitleDelayMs READ subtitleDelayMs NOTIFY changed)
    Q_PROPERTY(double danmakuSpeed READ danmakuSpeed NOTIFY changed)
    Q_PROPERTY(double danmakuFontSize READ danmakuFontSize NOTIFY changed)
    Q_PROPERTY(double danmakuOpacity READ danmakuOpacity NOTIFY changed)

    // ── 弹幕行数（697，QML 自绘层用；对齐 Flutter AppSettings）──
    Q_PROPERTY(int danmakuScrollRows READ danmakuScrollRows NOTIFY changed)
    Q_PROPERTY(int danmakuTopRows READ danmakuTopRows NOTIFY changed)
    Q_PROPERTY(int danmakuBottomRows READ danmakuBottomRows NOTIFY changed)

    // ── 屏幕锁定（662，照 Flutter 左缘锁钮）──
    Q_PROPERTY(bool locked READ locked NOTIFY changed)

    // ── 弹幕渲染（665，ASS 旁路喂 mpv）──
    Q_PROPERTY(QVariantList danmakuItems READ danmakuItemsVariant NOTIFY danmakuChanged)

    // ── 片段标记（665，跳过片头/片尾胶囊；-1 = 无片段）──
    Q_PROPERTY(qint64 segmentIntroEndMs READ segmentIntroEndMs NOTIFY changed)
    Q_PROPERTY(qint64 segmentOutroStartMs READ segmentOutroStartMs NOTIFY changed)

    // ── 弹幕 ──
    Q_PROPERTY(bool danmakuEnabled READ danmakuEnabled NOTIFY changed)

    // 轨道/剧集计数（QML 底栏角标用）
    Q_PROPERTY(int audioCount READ audioCount NOTIFY tracksChanged)
    Q_PROPERTY(int subtitleCount READ subtitleCount NOTIFY tracksChanged)
    Q_PROPERTY(int episodeCount READ episodeCount NOTIFY episodesChanged)

    /// QML 列表用（ListView model）。QVariantList 里是 QVariantMap，
    /// 字段名与 Flutter 的 JSON 一致（index/title/poster/number）。
    Q_PROPERTY(QVariantList episodes READ episodesVariant NOTIFY episodesChanged)
    Q_PROPERTY(int currentEpisodeIndex READ currentEpisodeIndex NOTIFY changed)
    Q_PROPERTY(QVariantList audioTracks READ audioTracksVariant NOTIFY tracksChanged)
    Q_PROPERTY(QVariantList subtitleTracks READ subtitleTracksVariant NOTIFY tracksChanged)

    // ── 输出诊断（调试面板用）──
    Q_PROPERTY(bool hdrOutput READ hdrOutput NOTIFY changed)
    Q_PROPERTY(QString videoOutputActual READ videoOutputActual NOTIFY changed)

    // ── 697：HDR/DV 调试指标（播放调试面板用）──
    //
    // 这些是 mpv 的**实时属性**（Dart 侧 1s 轮询直读后下发），
    // 排查 HDR/DV 问题的关键三元组：
    //   输入（videoParams*）→ 决策（dvContent/hdrContent）→ 输出（target*）
    Q_PROPERTY(QString videoParamsPrimaries READ videoParamsPrimaries
                   NOTIFY changed)
    Q_PROPERTY(QString videoParamsGamma READ videoParamsGamma NOTIFY changed)
    Q_PROPERTY(double videoParamsSigPeak READ videoParamsSigPeak NOTIFY changed)
    Q_PROPERTY(int videoParamsBitDepth READ videoParamsBitDepth NOTIFY changed)
    Q_PROPERTY(QString videoParamsPixelFormat READ videoParamsPixelFormat
                   NOTIFY changed)
    Q_PROPERTY(int doviProfile READ doviProfile NOTIFY changed)
    Q_PROPERTY(int doviLevel READ doviLevel NOTIFY changed)
    Q_PROPERTY(bool dvContent READ dvContent NOTIFY changed)
    Q_PROPERTY(QString targetPrim READ targetPrim NOTIFY changed)
    Q_PROPERTY(QString targetTrc READ targetTrc NOTIFY changed)
    Q_PROPERTY(QString toneMapping READ toneMapping NOTIFY changed)
    Q_PROPERTY(QString toneMappingMode READ toneMappingMode NOTIFY changed)
    Q_PROPERTY(QString hdrComputePeak READ hdrComputePeak NOTIFY changed)
    Q_PROPERTY(QString currentVo READ currentVo NOTIFY changed)
    Q_PROPERTY(QString gpuApi READ gpuApi NOTIFY changed)
    Q_PROPERTY(QString gpuContext READ gpuContext NOTIFY changed)
    Q_PROPERTY(double estimatedVfFps READ estimatedVfFps NOTIFY changed)
    Q_PROPERTY(int frameDropCount READ frameDropCount NOTIFY changed)
    Q_PROPERTY(int decoderFrameDropCount READ decoderFrameDropCount
                   NOTIFY changed)
    Q_PROPERTY(QString hwdecCurrent READ hwdecCurrent NOTIFY changed)
    Q_PROPERTY(QString videoFormat READ videoFormat NOTIFY changed)
    /// 697：调试面板开关（设置页「播放调试面板」）。
    Q_PROPERTY(bool showDebug READ showDebug NOTIFY changed)

    /// 697：调试文本（左上角多行小字叠加）。
    ///
    /// 由 `main.cpp` 的定时器从 `MpvWindow::debugText()` 拉取后写入。
    /// 【为什么不是 Flutter 下发】Qt 模式下 mpv 在独立进程里，Dart 读不到
    /// 真实属性（其 `_player` 是空闲引擎）——数据只能由 Qt 侧自己读。
    Q_PROPERTY(QString debugText READ debugText NOTIFY debugTextChanged)

    // ── 669：控件层显隐共享态（悬浮层渲染绑定 + 双窗手势共写）──
    // 纯 UI 本地状态，不参与 Flutter 状态同步（applyJson 不含此键）。
    // 控件悬浮层与宿主窗口的 VideoGestures 实例都能写——点击唤出在
    // 任何 z-order 状态下都有效。
    Q_PROPERTY(bool controlsVisible READ controlsVisible
                   WRITE setControlsVisible NOTIFY controlsVisibleChanged)

    // ── 670：窗口诊断码（标题栏显示，截图即诊断）──
    // "GLASS" = 透明合成正常；"SAFE:alpha0" = 已深底降级；其余=异常。
    Q_PROPERTY(QString windowDiag READ windowDiag NOTIFY windowDiagChanged)

    // ── 672：轨道选中真相（与安卓/鸿蒙同源：顶层 id，非每轨 selected）──
    // 面板勾选用这两个 id 判定（每轨 selected 在 Qt 模式下可能恒 false）。
    Q_PROPERTY(int selectedAudioId READ selectedAudioId NOTIFY changed)
    Q_PROPERTY(int selectedSubtitleId READ selectedSubtitleId NOTIFY changed)

    // ── 672：跳过片头/片尾提示（'' 隐藏 / 'intro' / 'outro'）──
    // 与安卓/鸿蒙原生底栏同驱动字段（skipPrompt）。
    Q_PROPERTY(QString skipPrompt READ skipPrompt NOTIFY changed)

    // ── 677：房间观众权限（对齐安卓/鸿蒙原生 UI）──
    //
    // 【为什么 Qt 必须有这两个字段】Dart 的 `NativePlayerState.toJson()`
    // 早就在发 `canControl` / `segmentEnabled`，但 Qt 侧此前**从未解析**
    // → QML 无门可依，房间观众能点播放/拖进度/右键标记片头片尾
    //（真机回归：观众把房主的节奏拖乱了）。
    //
    // `canControl`：非房主为 false → 隐藏传输组、禁用进度条/双击/快捷键。
    // `segmentEnabled`：片头片尾标记开关（Dart `_segmentFeatureEnabled`
    // 已含 `_canControlPlayback`，观众恒 false）→ 右键菜单门控。
    Q_PROPERTY(bool canControl READ canControl NOTIFY changed)
    Q_PROPERTY(bool segmentEnabled READ segmentEnabled NOTIFY changed)

public:
    explicit PlayerState(QObject* parent = nullptr);

    /// 672：滑杆/面板**本地镜像**——moved/点选/恢复默认即时写入本状态，
    /// 根治「绑定松手写回过期值 → 滑杆跳位 / 勾选冻结」（真机回归）。
    /// 【674 真凶】必须在 public 区：Qt 6.8 QML 引擎只暴露公开
    /// Q_INVOKABLE，私有声明调不到（「patchValue is not a function」
    /// → 全部控件处理器中断，真机回归「所有控件几乎都失效」）。
    Q_INVOKABLE void patchValue(const QString& key, const QVariant& value);

    /// 应用 Flutter 推来的完整状态 JSON。
    ///
    /// 只在**字段真的变化**时发 changed 信号——QML 的属性绑定会因此
    /// 避免无谓重建（20Hz 推送下这一点很关键）。
    ///
    /// [remote] 为 true（管道推送）时跳过**本地置顶字段**——patchValue
    /// 写过的字段以本地为准（真机回归：过期快照把倍速/音量/字幕选中
    /// 写回旧值 → 勾选冻结/标签不变）。mpv 事件的本地补丁走默认
    /// false 照常生效。
    void applyJson(const QJsonObject& json, bool remote = false);

    qint64 positionMs() const { return positionMs_; }
    qint64 durationMs() const { return durationMs_; }
    qint64 bufferedMs() const { return bufferedMs_; }
    bool paused() const { return paused_; }
    double volume() const { return volume_; }
    double speed() const { return speed_; }
    bool buffering() const { return buffering_; }
    bool showLoading() const { return showLoading_; }
    bool playerReady() const { return playerReady_; }

    QString title() const { return title_; }
    QString mediaTitle() const { return mediaTitle_; }

    QString engineLabel() const { return engineLabel_; }
    QString networkSpeedText() const { return networkSpeedText_; }
    QString videoFit() const { return videoFit_; }
    QString decodeMode() const { return decodeMode_; }
    bool glassUi() const { return glassUi_; }
    bool isRoom() const { return isRoom_; }
    int onlineUserCount() const { return onlineUserCount_; }
    bool isHost() const { return isHost_; }
    QString clockFormat() const { return clockFormat_; }

    QString logoUrl() const { return logoUrl_; }

    double brightness() const { return brightness_; }

    /// 多版本（`versions` 数组的轻量投影，MediaSource 名）。
    struct Version {
        int index = 0;
        QString title;
    };
    const QList<Version>& versions() const { return versions_; }
    int currentVersionIndex() const { return currentVersionIndex_; }

    // 显示调节（与 Flutter DisplayAdjustPanel 六滑杆一一对应）
    double subtitleScale() const { return subtitleScale_; }
    int subtitleMarginY() const { return subtitleMarginY_; }
    double subtitleDelayMs() const { return subtitleDelayMs_; }
    double danmakuSpeed() const { return danmakuSpeed_; }
    double danmakuFontSize() const { return danmakuFontSize_; }
    double danmakuOpacity() const { return danmakuOpacity_; }

    // 弹幕行数（697，QML 自绘层用）
    int danmakuScrollRows() const { return danmakuScrollRows_; }
    int danmakuTopRows() const { return danmakuTopRows_; }
    int danmakuBottomRows() const { return danmakuBottomRows_; }

    bool locked() const { return locked_; }

    /// 弹幕项（{timeMs, text, mode, color}；ASS 旁路渲染用）。
    struct Danmaku {
        qint64 timeMs = 0;
        QString text;
        QString mode;   ///< scroll / top / bottom
        QString color;  ///< #RRGGBB
    };
    const QList<Danmaku>& danmakuItems() const { return danmakuItems_; }
    QVariantList danmakuItemsVariant() const;
    qint64 segmentIntroEndMs() const { return segmentIntroEndMs_; }
    qint64 segmentOutroStartMs() const { return segmentOutroStartMs_; }

    bool danmakuEnabled() const { return danmakuEnabled_; }

    bool hdrOutput() const { return hdrOutput_; }
    QString videoOutputActual() const { return videoOutputActual_; }

    // 697：HDR/DV 调试指标 getter
    QString videoParamsPrimaries() const { return videoParamsPrimaries_; }
    QString videoParamsGamma() const { return videoParamsGamma_; }
    double videoParamsSigPeak() const { return videoParamsSigPeak_; }
    int videoParamsBitDepth() const { return videoParamsBitDepth_; }
    QString videoParamsPixelFormat() const { return videoParamsPixelFormat_; }
    int doviProfile() const { return doviProfile_; }
    int doviLevel() const { return doviLevel_; }
    bool dvContent() const { return dvContent_; }
    QString targetPrim() const { return targetPrim_; }
    QString targetTrc() const { return targetTrc_; }
    QString toneMapping() const { return toneMapping_; }
    QString toneMappingMode() const { return toneMappingMode_; }
    QString hdrComputePeak() const { return hdrComputePeak_; }
    QString currentVo() const { return currentVo_; }
    QString gpuApi() const { return gpuApi_; }
    QString gpuContext() const { return gpuContext_; }
    double estimatedVfFps() const { return estimatedVfFps_; }
    int frameDropCount() const { return frameDropCount_; }
    int decoderFrameDropCount() const { return decoderFrameDropCount_; }
    QString hwdecCurrent() const { return hwdecCurrent_; }
    QString videoFormat() const { return videoFormat_; }
    bool showDebug() const { return showDebug_; }

    QString debugText() const { return debugText_; }
    void setDebugText(const QString& text);

    bool controlsVisible() const { return controlsVisible_; }
    void setControlsVisible(bool visible);

    QString windowDiag() const { return windowDiag_; }
    void setWindowDiag(const QString& diag);

    int selectedAudioId() const { return selectedAudioId_; }
    int selectedSubtitleId() const { return selectedSubtitleId_; }
    QString skipPrompt() const { return skipPrompt_; }
    bool canControl() const { return canControl_; }
    bool segmentEnabled() const { return segmentEnabled_; }

    /// 选集列表（`episodes` 数组的轻量投影）。
    struct Episode {
        int index = 0;
        QString title;
        QString poster;
        int number = 0;
    };
    const QList<Episode>& episodes() const { return episodes_; }
    int currentEpisodeIndex() const { return currentEpisodeIndex_; }

    /// 音轨 / 字幕轨道（`tracks` 数组，按 type 过滤）。
    struct Track {
        int id = 0;
        QString type;  ///< "audio" / "subtitle"
        QString title;
        QString lang;
        QString label;
        bool selected = false;
    };
    const QList<Track>& audioTracks() const { return audioTracks_; }
    const QList<Track>& subtitleTracks() const { return subtitleTracks_; }

    // QML 直接用的计数（避免在 QML 里写 audioTracks.length 触发类型转换开销）
    int audioCount() const { return audioTracks_.size(); }
    int subtitleCount() const { return subtitleTracks_.size(); }
    int episodeCount() const { return episodes_.size(); }
    int versionCount() const { return versions_.size(); }

    QVariantList episodesVariant() const;
    QVariantList audioTracksVariant() const;
    QVariantList subtitleTracksVariant() const;
    QVariantList versionsVariant() const;

signals:
    void changed();

    /// 【独立信号】调试文本 2s 刷新一次；若复用 `changed` 会让所有
    /// Q_PROPERTY 的绑定每秒全量重算（白白重绘整个控件层）。
    void debugTextChanged();

    void controlsVisibleChanged();
    void windowDiagChanged();

    /// 剧集列表变化（QML 的 ListView 需要单独通知才能刷新 model）。
    void episodesChanged();
    void tracksChanged();
    void versionsChanged();
    void danmakuChanged();

private:
    void setEpisodes(const QJsonArray& arr);
    void setTracks(const QJsonArray& arr);
    void setVersions(const QJsonArray& arr);
    void setDanmakuItems(const QJsonArray& arr);

    qint64 positionMs_ = 0;
    qint64 durationMs_ = 0;
    qint64 bufferedMs_ = 0;
    bool paused_ = true;
    double volume_ = 1.0;
    double speed_ = 1.0;
    bool buffering_ = false;
    bool showLoading_ = false;
    bool playerReady_ = false;
    bool controlsVisible_ = true;
    QString windowDiag_;
    QSet<QString> localKeys_;  ///< patchValue 写过的字段（本地置顶）
    int selectedAudioId_ = 0;
    int selectedSubtitleId_ = 0;
    QString skipPrompt_;
    bool canControl_ = true;      ///< 677：房间观众为 false（隐藏播放控制）
    bool segmentEnabled_ = false; ///< 677：片头片尾标记开关（右键菜单门）

    QString title_;
    QString mediaTitle_;

    QString engineLabel_;
    QString networkSpeedText_;
    QString videoFit_ = QStringLiteral("contain");
    QString decodeMode_;
    bool glassUi_ = true;
    bool isRoom_ = false;
    int onlineUserCount_ = 0;
    bool isHost_ = false;
    QString clockFormat_;

    QString logoUrl_;

    double brightness_ = 0.5;

    double subtitleScale_ = 1.0;
    int subtitleMarginY_ = 22;
    double subtitleDelayMs_ = 0.0;
    double danmakuSpeed_ = 0.7;
    double danmakuFontSize_ = 0.5;
    double danmakuOpacity_ = 1.0;

    // 弹幕行数（697，对齐 Flutter AppSettings 默认：滚动 30 / 顶 4 / 底 4）
    int danmakuScrollRows_ = 30;
    int danmakuTopRows_ = 4;
    int danmakuBottomRows_ = 4;

    bool locked_ = false;

    bool danmakuEnabled_ = false;

    bool hdrOutput_ = false;
    QString videoOutputActual_;

    // 697：HDR/DV 调试指标
    QString videoParamsPrimaries_;
    QString videoParamsGamma_;
    double videoParamsSigPeak_ = 0;
    int videoParamsBitDepth_ = 0;
    QString videoParamsPixelFormat_;
    int doviProfile_ = 0;
    int doviLevel_ = 0;
    bool dvContent_ = false;
    QString targetPrim_;
    QString targetTrc_;
    QString toneMapping_;
    QString toneMappingMode_;
    QString hdrComputePeak_;
    QString currentVo_;
    QString gpuApi_;
    QString gpuContext_;
    double estimatedVfFps_ = 0;
    int frameDropCount_ = 0;
    int decoderFrameDropCount_ = 0;
    QString hwdecCurrent_;
    QString videoFormat_;
    bool showDebug_ = false;
    QString debugText_;

    QList<Episode> episodes_;
    int currentEpisodeIndex_ = -1;
    QList<Version> versions_;
    int currentVersionIndex_ = 0;
    QList<Danmaku> danmakuItems_;
    qint64 segmentIntroEndMs_ = -1;
    qint64 segmentOutroStartMs_ = -1;
    QList<Track> audioTracks_;
    QList<Track> subtitleTracks_;
};

#endif  // PLAYER_STATE_H
