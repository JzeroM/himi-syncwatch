
import { Want } from '@kit.AbilityKit';
import { AbilityConstant } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { font } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { FlutterAbility, FlutterEngine } from '@ohos/flutter_ohos';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';

const DOMAIN = 0x0001;
const TAG = 'EntryAbility';

/**
 * 注册内置 Material Icons 字体（原生播放器控制层用）。
 *
 * 字体文件位于 resources/rawfile/MaterialIcons-Regular.otf，注册成功后即可
 * 在 ArkUI 中用 `.fontFamily('MaterialIcons')` 渲染图标字形；注册失败
 * （文件被裁剪/资源未打包）时只记日志不崩溃——控制层其余文本控件不受影响。
 */
function registerIconFont(): void {
  try {
    font.registerFont({
      familyName: 'MaterialIcons',
      familySrc: $rawfile('MaterialIcons-Regular.otf'),
    });
    hilog.info(DOMAIN, TAG, 'MaterialIcons 字体注册成功');
  } catch (e) {
    const err = e as BusinessError;
    hilog.error(DOMAIN, TAG, `MaterialIcons 字体注册失败: ${err.code} ${err.message}`);
  }
}

export default class EntryAbility extends FlutterAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    super.onCreate(want, launchParam);
    registerIconFont();
  }

  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    GeneratedPluginRegistrant.registerWith(flutterEngine)
  }
}
