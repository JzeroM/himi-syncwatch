/**
 * 原生控制层图标码点（Material Icons）。
 *
 * 单一来源：tool/native_icons.json；Dart 侧镜像见 NativePlayerIcons。
 * 一致性由 test/native_player_icons_test.dart 校验，禁止手改单个数字。
 */
export class NativePlayerIcons {
  /**
   * 图标字体族名。刻意**不叫** 'MaterialIcons'：Flutter 引擎会按
   * FontManifest 注册同名字体族（flutter_assets 里的 18KB 子集），与自
   * 注册字体冲突时图标会渲染成空/乱码（v1.5.5 真机回归「图标全灭」）。
   * 注册入口唯一：EntryAbility（entry 模块 rawfile，$rawfile 只解析 entry）。
   */
  static readonly FONT_FAMILY: string = 'HimiIcons';
  static readonly FONT_RAWFILE: string = 'MaterialIcons-Regular.otf';

  /** arrowBack */
  static readonly ICON_ARROW_BACK: number = 0xE092;

  /** speed */
  static readonly ICON_SPEED: number = 0xE5E0;

  /** tune */
  static readonly ICON_TUNE: number = 0xE683;

  /** memory */
  static readonly ICON_MEMORY: number = 0xE3DB;

  /** rotate */
  static readonly ICON_ROTATE: number = 0xF07BF;

  /** fitScreen */
  static readonly ICON_FIT_SCREEN: number = 0xE28C;

  /** fullscreen */
  static readonly ICON_FULLSCREEN: number = 0xE2CB;

  /** zoomOutMap */
  static readonly ICON_ZOOM_OUT_MAP: number = 0xE6FF;

  /** aspectRatio */
  static readonly ICON_ASPECT_RATIO: number = 0xE0A3;

  /** danmakuOn */
  static readonly ICON_DANMAKU_ON: number = 0xE17E;

  /** danmakuOff */
  static readonly ICON_DANMAKU_OFF: number = 0xF04D2;

  /** highQuality */
  static readonly ICON_HIGH_QUALITY: number = 0xE30F;

  /** subtitles */
  static readonly ICON_SUBTITLES: number = 0xE619;

  /** audioTrack */
  static readonly ICON_AUDIO_TRACK: number = 0xE0B6;

  /** playlistPlay */
  static readonly ICON_PLAYLIST_PLAY: number = 0xE4D4;

  /** skipPrevious */
  static readonly ICON_SKIP_PREVIOUS: number = 0xE5BE;

  /** playCircle */
  static readonly ICON_PLAY_CIRCLE: number = 0xE4CD;

  /** pauseCircle */
  static readonly ICON_PAUSE_CIRCLE: number = 0xE47E;

  /** skipNext */
  static readonly ICON_SKIP_NEXT: number = 0xE5BD;

  /** lock */
  static readonly ICON_LOCK: number = 0xE3AE;

  /** lockOpen */
  static readonly ICON_LOCK_OPEN: number = 0xE3B0;

  /** check */
  static readonly ICON_CHECK: number = 0xE156;

  /** chevronRight */
  static readonly ICON_CHEVRON_RIGHT: number = 0xE15F;

  /** expandMore */
  static readonly ICON_EXPAND_MORE: number = 0xE246;

  /** close */
  static readonly ICON_CLOSE: number = 0xE16A;

  /** campaign */
  static readonly ICON_CAMPAIGN: number = 0xE138;

  /** people */
  static readonly ICON_PEOPLE: number = 0xE486;

  /** volumeUp */
  static readonly ICON_VOLUME_UP: number = 0xE6C5;

  /** volumeDown */
  static readonly ICON_VOLUME_DOWN: number = 0xE6C2;

  /** volumeOff */
  static readonly ICON_VOLUME_OFF: number = 0xE6C4;

  /** brightness */
  static readonly ICON_BRIGHTNESS: number = 0xE10A;

  /** fastForward */
  static readonly ICON_FAST_FORWARD: number = 0xE258;

  /** add */
  static readonly ICON_ADD: number = 0xE047;

  /** delete */
  static readonly ICON_DELETE: number = 0xE1BB;

  /** restartAlt */
  static readonly ICON_RESTART_ALT: number = 0xE531;

  /** photoCamera */
  static readonly ICON_PHOTO_CAMERA: number = 0xE4B6;

  /** bugReport */
  static readonly ICON_BUG_REPORT: number = 0xE115;

  /** movie */
  static readonly ICON_MOVIE: number = 0xE40D;

  /** search */
  static readonly ICON_SEARCH: number = 0xE567;

  /** replay */
  static readonly ICON_REPLAY: number = 0xE523;

  /** forward10 */
  static readonly ICON_FORWARD10: number = 0xE2C5;

  /** replay10 */
  static readonly ICON_REPLAY10: number = 0xE524;

  /** openInFull */
  static readonly ICON_OPEN_IN_FULL: number = 0xE45B;

  /** closeFullscreen */
  static readonly ICON_CLOSE_FULLSCREEN: number = 0xE16B;

  /** share */
  static readonly ICON_SHARE: number = 0xE593;

}
