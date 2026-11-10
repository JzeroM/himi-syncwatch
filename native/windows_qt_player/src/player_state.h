#ifndef PLAYER_STATE_H
#define PLAYER_STATE_H

#include <QJsonObject>
#include <QList>
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

public:
    explicit PlayerState(QObject* parent = nullptr);

    /// 应用 Flutter 推来的完整状态 JSON。
    ///
    /// 只在**字段真的变化**时发 changed 信号——QML 的属性绑定会因此
    /// 避免无谓重建（20Hz 推送下这一点很关键）。
    void applyJson(const QJsonObject& json);

    qint64 positionMs() const { return positionMs_; }
    qint64 durationMs() const { return durationMs_; }
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

    bool danmakuEnabled() const { return danmakuEnabled_; }

    bool hdrOutput() const { return hdrOutput_; }
    QString videoOutputActual() const { return videoOutputActual_; }

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

    QVariantList episodesVariant() const;
    QVariantList audioTracksVariant() const;
    QVariantList subtitleTracksVariant() const;

signals:
    void changed();

    /// 剧集列表变化（QML 的 ListView 需要单独通知才能刷新 model）。
    void episodesChanged();
    void tracksChanged();

private:
    void setEpisodes(const QJsonArray& arr);
    void setTracks(const QJsonArray& arr);

    qint64 positionMs_ = 0;
    qint64 durationMs_ = 0;
    bool paused_ = true;
    double volume_ = 1.0;
    double speed_ = 1.0;
    bool buffering_ = false;
    bool showLoading_ = false;
    bool playerReady_ = false;

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

    bool danmakuEnabled_ = false;

    bool hdrOutput_ = false;
    QString videoOutputActual_;

    QList<Episode> episodes_;
    int currentEpisodeIndex_ = -1;
    QList<Track> audioTracks_;
    QList<Track> subtitleTracks_;
};

#endif  // PLAYER_STATE_H
