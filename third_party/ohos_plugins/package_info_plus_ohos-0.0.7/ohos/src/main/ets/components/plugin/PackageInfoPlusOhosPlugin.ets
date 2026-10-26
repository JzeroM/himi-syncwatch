import {
  FlutterPlugin,
  FlutterPluginBinding
} from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/FlutterPlugin';
import MethodChannel, {
  MethodCallHandler,
  MethodResult
} from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import MethodCall from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodCall';
import HashMap from '@ohos.util.HashMap';
import bundleManager from '@ohos.bundle.bundleManager';

/** PackageInfoPlusPlugin **/
export default class PackageInfoPlusPlugin implements FlutterPlugin, MethodCallHandler {
  private channel: MethodChannel | null = null;
  private context: Context | null = null;

  constructor() {
  }

  getUniqueClassName(): string {
    return "PackageInfoPlusPlugin"
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), "dev.fluttercommunity.plus/package_info");
    this.channel.setMethodCallHandler(this)
    this.context = binding.getApplicationContext();
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    if (this.channel != null) {
      this.channel.setMethodCallHandler(null)
    }
    this.context = null;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (call.method == "getAll") {
      this.getAll(result);
    } else {
      result.notImplemented()
    }
  }

  async getAll(result: MethodResult): Promise<void> {
    if (this.context != null) {
      try {
        let infoMap: HashMap<string, string> = new HashMap<string, string>();
        let applicationInfo = this.context.applicationInfo;
        let label = this.context.resourceManager.getStringSync(applicationInfo.labelId);
        infoMap.set("appName", label);
        infoMap.set("packageName", applicationInfo.name);
        let bundleInfo = await bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
        infoMap.set("version", bundleInfo.versionName);
        infoMap.set("buildNumber", bundleInfo.versionCode.toString());
        if (bundleInfo.signatureInfo != null && bundleInfo.signatureInfo.fingerprint != null) {
          infoMap.set("buildSignature", bundleInfo.signatureInfo.fingerprint);
        }
        // infoMap.set("installerStore", "");
        result.success(infoMap);
      }
      catch (e) {
        result.error('1', 'Failed to get package info', e);
      }
    }
    else {
      result.error('0', 'The context should not be null', '');
    }
  }
}