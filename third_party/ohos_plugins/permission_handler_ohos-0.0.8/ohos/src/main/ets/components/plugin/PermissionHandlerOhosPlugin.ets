import {
  FlutterPlugin,
  FlutterPluginBinding
} from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/FlutterPlugin';
import MethodChannel, {
  MethodCallHandler,
  MethodResult
} from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import MethodCall from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodCall';
import Want from '@ohos.app.ability.Want';
import AbilityAware from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/ability/AbilityAware';
import {
  AbilityPluginBinding
} from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/ability/AbilityPluginBinding';
import common from '@ohos.app.ability.common';
import abilityAccessCtrl, { Permissions } from '@ohos.abilityAccessCtrl';
import { HashMap } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';

/** PermissionHandlerOhosPlugin **/
export default class PermissionHandlerOhosPlugin implements FlutterPlugin, MethodCallHandler, AbilityAware {
  private channel: MethodChannel | null = null;
  private context: Context | null = null;
  private uiContext: common.UIAbilityContext | null = null;

  constructor() {
  }

  onAttachedToAbility(binding: AbilityPluginBinding): void {
    this.uiContext = binding.getAbility().context;
  }

  onDetachedFromAbility(): void {

  }

  getUniqueClassName(): string {
    return "PermissionHandlerPlugin"
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), "com.harmonycandies.permission_handler_ohos");
    this.channel.setMethodCallHandler(this)
    this.context = binding.getApplicationContext();
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    if (this.channel != null) {
      this.channel.setMethodCallHandler(null)
    }
  }

  async onMethodCall(call: MethodCall, result: MethodResult): Promise<void> {
    if (call.method == "checkPermissionStatus") {
      if (this.context == null) {
        result.error('100', 'context is null', 'it should not be null');
        return;
      }
      let args: ESObject = call.args;
      let atManager = abilityAccessCtrl.createAtManager();
      let grantStatus: abilityAccessCtrl.GrantStatus = await atManager.checkAccessToken(this.context!
        .applicationInfo
        .accessTokenId, args as Permissions,);
      result.success(grantStatus)
    }
    else if (call.method == "openAppSettings") {
      if (this.context == null || this.uiContext == null) {
        result.error('100', 'context and uiContext are null', 'They should not be null');
        return;
      }
      let applicationInfo = this.context!.applicationInfo;
      let wantInfo: Want = {
          bundleName: 'com.huawei.hmos.settings',
          abilityName: 'com.huawei.hmos.settings.MainAbility',
          uri: 'application_info_entry',
          parameters: {
              pushParams : applicationInfo.name
          }
      }
      
      this.uiContext!.startAbility(wantInfo).then(() => {
        result.success(true);
      }).catch((err: BusinessError) => {
        console.error(`openAppSettings failed, code is ${err.code}, message is ${err.message}`);
      })

    }
    else if (call.method == "requestPermissions") {
      let args: ESObject = call.args;

      if (this.uiContext == null) {
        result.error('100', 'uiContext is null', 'it should not be null');
        return;
      }

      if (Array.isArray(args)) {
        let results: HashMap<string, number> = new  HashMap<string, number>();
        // requestPermissionsFromUser
        let permissions: Array<Permissions> = [];
        permissions.push(...args);

        if (permissions.length == 0) {
          result.error('101', 'permissions is empty', 'make sure you pass the permissions');
          return;
        }

        let atManager = abilityAccessCtrl.createAtManager();
        atManager.requestPermissionsFromUser(this.uiContext, permissions).then((data) => {
          let grantStatus: Array<number> = data.authResults;
          let length: number = grantStatus.length;
          for (let i = 0; i < length; i++) {
            results.set(permissions[i], grantStatus[i]);
          }
          result.success(results)
        }).catch((err: BusinessError) => {
          console.error(`requestPermissionsFromUser failed, code is ${err.code}, message is ${err.message}`);
        })
      } else {
        result.error('102', 'permissions is not List<String>', 'make sure you pass the right permissions');
      }
    }
    else {
      result.notImplemented()
    }
  }
}

