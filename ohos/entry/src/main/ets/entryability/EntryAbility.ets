
import { Want } from '@kit.AbilityKit';
import { AbilityConstant } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { font, window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { FlutterAbility, FlutterEngine } from '@ohos/flutter_ohos';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';

const DOMAIN = 0x0001;
const TAG = 'EntryAbility';

/**
 * 图标字体族名，与插件侧 NativePlayerIcons.FONT_FAMILY 保持一致
 * （test/native_player_icons_test.dart 锁定）。刻意不叫 'MaterialIcons'：
 * Flutter 引擎会按 FontManifest 注册同名字体族（flutter_assets 的 18KB
 * 子集），族名冲突会让原生控制层图标渲染成空/乱码（v1.5.5 真机回归
 * 「图标全灭」）。
 */
const ICON_FONT_FAMILY = 'HimiIcons';
const ICON_FONT_RAWFILE = 'MaterialIcons-Regular.otf';

/**
 * 兼容兜底注册（旧系统 API < 18）：全局 font.registerFont。
 *
 * 自 API 18 起该 API 已废弃（@useinstead UIContext.getFont().registerFont），
 * 在新系统上可能静默失效——真机表现为所有图标字形不渲染。现行路径见
 * onWindowStageCreate。
 */
function registerIconFontLegacy(): void {
  try {
    font.registerFont({
      familyName: ICON_FONT_FAMILY,
      familySrc: $rawfile(ICON_FONT_RAWFILE),
    });
    hilog.info(DOMAIN, TAG, 'HimiIcons 字体注册成功（font.registerFont 兜底）');
  } catch (e) {
    const err = e as BusinessError;
    hilog.error(DOMAIN, TAG, `HimiIcons 字体注册失败(兜底): ${err.code} ${err.message}`);
  }
}

export default class EntryAbility extends FlutterAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    super.onCreate(want, launchParam);
    registerIconFontLegacy();
  }

  /**
   * 现行字体注册入口：UIContext.getFont().registerFont（自 API 18 接替
   * 废弃的 font.registerFont）。必须在窗口创建后、原生播放器控件构建前
   * 注册，注册作用域是当前窗口的 UIContext。
   */
  onWindowStageCreate(windowStage: window.WindowStage): void {
    super.onWindowStageCreate(windowStage);
    try {
      windowStage.getMainWindowSync().getUIContext().getFont().registerFont({
        familyName: ICON_FONT_FAMILY,
        familySrc: $rawfile(ICON_FONT_RAWFILE),
      });
      hilog.info(DOMAIN, TAG, 'HimiIcons 字体注册成功（UIContext.getFont）');
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(DOMAIN, TAG, `HimiIcons 字体注册失败(UIContext): ${err.code} ${err.message}`);
    }
  }

  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    GeneratedPluginRegistrant.registerWith(flutterEngine)
  }
}
