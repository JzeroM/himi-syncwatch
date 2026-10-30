/// 原生播放器控制层图标码点（Material Icons）。
///
/// 单一来源：`tool/native_icons.json`。Dart 侧常量、Android（Kotlin）与
/// 鸿蒙（ArkTS）原生图标常量必须与此表一致，由
/// `test/native_player_icons_test.dart` 同时校验：
/// 1. 本类常量 == JSON；
/// 2. JSON 码点 == Flutter `Icons.xxx.codePoint`（保证与 Flutter 播放页同款）；
/// 3. Android / 鸿蒙源码中出现同名十六进制字面量（保证原生真的用同一字体）。
///
/// 字体文件：`MaterialIcons-Regular.otf`
/// - Android：`android/app/src/main/assets/fonts/MaterialIcons-Regular.otf`
/// - 鸿蒙：`plugins/himi_mpv_ohos/ohos/src/main/resources/rawfile/MaterialIcons-Regular.otf`
abstract final class NativePlayerIcons {
  NativePlayerIcons._();

  static const String fontFamily = 'MaterialIcons';
  static const String fontFile = 'MaterialIcons-Regular.otf';

  static const int arrowBack = 0xE092;
  static const int speed = 0xE5E0;
  static const int tune = 0xE683;
  static const int memory = 0xE3DB;
  static const int rotate = 0xF07BF;
  static const int fitScreen = 0xE28C;
  static const int fullscreen = 0xE2CB;
  static const int zoomOutMap = 0xE6FF;
  static const int aspectRatio = 0xE0A3;
  static const int danmakuOn = 0xE17E;
  static const int danmakuOff = 0xF04D2;
  static const int highQuality = 0xE30F;
  static const int subtitles = 0xE619;
  static const int audioTrack = 0xE0B6;
  static const int playlistPlay = 0xE4D4;
  static const int skipPrevious = 0xE5BE;
  static const int playCircle = 0xE4CD;
  static const int pauseCircle = 0xE47E;
  static const int skipNext = 0xE5BD;
  static const int lock = 0xE3AE;
  static const int lockOpen = 0xE3B0;
  static const int check = 0xE156;
  static const int chevronRight = 0xE15F;
  static const int expandMore = 0xE246;
  static const int close = 0xE16A;
  static const int campaign = 0xE138;
  static const int people = 0xE486;
  static const int volumeUp = 0xE6C5;
  static const int volumeDown = 0xE6C2;
  static const int volumeOff = 0xE6C4;
  static const int brightness = 0xE10A;
  static const int fastForward = 0xE258;
  static const int add = 0xE047;
  static const int delete = 0xE1BB;
  static const int restartAlt = 0xE531;
  static const int photoCamera = 0xE4B6;
  static const int bugReport = 0xE115;
  static const int movie = 0xE40D;
  static const int search = 0xE567;
  static const int replay = 0xE523;
  static const int forward10 = 0xE2C5;
  static const int replay10 = 0xE524;
  static const int openInFull = 0xE45B;
  static const int closeFullscreen = 0xE16B;

  /// 名称 → 码点（与 `tool/native_icons.json` 的 `icons` 表一一对应）。
  static const Map<String, int> all = <String, int>{
    'arrowBack': arrowBack,
    'speed': speed,
    'tune': tune,
    'memory': memory,
    'rotate': rotate,
    'fitScreen': fitScreen,
    'fullscreen': fullscreen,
    'zoomOutMap': zoomOutMap,
    'aspectRatio': aspectRatio,
    'danmakuOn': danmakuOn,
    'danmakuOff': danmakuOff,
    'highQuality': highQuality,
    'subtitles': subtitles,
    'audioTrack': audioTrack,
    'playlistPlay': playlistPlay,
    'skipPrevious': skipPrevious,
    'playCircle': playCircle,
    'pauseCircle': pauseCircle,
    'skipNext': skipNext,
    'lock': lock,
    'lockOpen': lockOpen,
    'check': check,
    'chevronRight': chevronRight,
    'expandMore': expandMore,
    'close': close,
    'campaign': campaign,
    'people': people,
    'volumeUp': volumeUp,
    'volumeDown': volumeDown,
    'volumeOff': volumeOff,
    'brightness': brightness,
    'fastForward': fastForward,
    'add': add,
    'delete': delete,
    'restartAlt': restartAlt,
    'photoCamera': photoCamera,
    'bugReport': bugReport,
    'movie': movie,
    'search': search,
    'replay': replay,
    'forward10': forward10,
    'replay10': replay10,
    'openInFull': openInFull,
    'closeFullscreen': closeFullscreen,
  };
}
