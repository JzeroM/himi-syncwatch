import {
  FlutterPlugin,
  FlutterPluginBinding
} from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/FlutterPlugin';
import MethodChannel, {
  MethodCallHandler,
  MethodResult
} from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import MethodCall from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodCall';
import deviceInfo from '@ohos.deviceInfo';
import HashMap from '@ohos.util.HashMap';

/** DeviceInfoPlusPlugin **/
export default class DeviceInfoPlusPlugin implements FlutterPlugin, MethodCallHandler {
  private channel: MethodChannel | null = null;

  constructor() {
  }

  getUniqueClassName(): string {
    return "DeviceInfoPlusPlugin"
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), "dev.fluttercommunity.plus/device_info");
    this.channel.setMethodCallHandler(this)
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    if (this.channel != null) {
      this.channel.setMethodCallHandler(null)
    }
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (call.method == "getDeviceInfo") {
      let infoMap: HashMap<string, ESObject> = new HashMap<string, ESObject>();
      infoMap.set('deviceType', deviceInfo.deviceType);
      infoMap.set('manufacture', deviceInfo.manufacture);
      infoMap.set('brand', deviceInfo.brand);
      infoMap.set('marketName', deviceInfo.marketName);
      infoMap.set('productSeries', deviceInfo.productSeries);
      infoMap.set('productModel', deviceInfo.productModel);
      infoMap.set('softwareModel', deviceInfo.softwareModel);
      infoMap.set('hardwareModel', deviceInfo.hardwareModel);
      // deprecated
      // infoMap.set('hardwareProfile', deviceInfo.hardwareProfile);
      // infoMap.set('serial', deviceInfo.serial);
      // infoMap.set('serial', '');
      infoMap.set('bootloaderVersion', deviceInfo.bootloaderVersion);
      infoMap.set('abiList', deviceInfo.abiList);
      infoMap.set('securityPatchTag', deviceInfo.securityPatchTag);
      infoMap.set('displayVersion', deviceInfo.displayVersion);
      infoMap.set('incrementalVersion', deviceInfo.incrementalVersion);
      infoMap.set('osReleaseType', deviceInfo.osReleaseType);
      infoMap.set('osFullName', deviceInfo.osFullName);
      infoMap.set('majorVersion', deviceInfo.majorVersion);
      infoMap.set('seniorVersion', deviceInfo.seniorVersion);
      infoMap.set('featureVersion', deviceInfo.featureVersion);
      infoMap.set('buildVersion', deviceInfo.buildVersion);
      infoMap.set('sdkApiVersion', deviceInfo.sdkApiVersion);
      infoMap.set('firstApiVersion', deviceInfo.firstApiVersion);
      infoMap.set('versionId', deviceInfo.versionId);
      infoMap.set('buildType', deviceInfo.buildType);
      infoMap.set('buildUser', deviceInfo.buildUser);
      infoMap.set('buildHost', deviceInfo.buildHost);
      infoMap.set('buildTime', deviceInfo.buildTime);
      infoMap.set('buildRootHash', deviceInfo.buildRootHash);
      // infoMap.set('udid', deviceInfo.udid);
      // infoMap.set('udid', '');
      infoMap.set('odid', deviceInfo.ODID);
      infoMap.set('distributionOSName', deviceInfo.distributionOSName);
      infoMap.set('distributionOSVersion', deviceInfo.distributionOSVersion);
      infoMap.set('distributionOSApiVersion', deviceInfo.distributionOSApiVersion);
      infoMap.set('distributionOSReleaseType', deviceInfo.distributionOSReleaseType);
      infoMap.set('isPhysicalDevice', !this.isEmulator(infoMap));
      result.success(infoMap)
    }
    else if (call.method == "getAccessUDIDInfo") {
      let infoMap: HashMap<string, ESObject> = new HashMap<string, ESObject>();
      infoMap.set('serial', deviceInfo.serial);
      infoMap.set('udid', deviceInfo.udid);
      result.success(infoMap)
    }
    else {
      result.notImplemented()
    }
  }

  isEmulator(infoMap: HashMap<string, ESObject>): Boolean {
    return infoMap.hasValue('emulator') || deviceInfo.versionId.includes('emulator') || deviceInfo.displayVersion.includes('emulator');
  }
}