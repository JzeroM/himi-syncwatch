import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import {
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
  StandardMethodCodec,
} from '@ohos/flutter_ohos';

const DOMAIN = 0x0001;
const TAG = 'GallerySaverPlugin';
const CHANNEL = 'himi/gallery_saver';

/**
 * 图片保存到系统相册（590，鸿蒙）。
 *
 * 【为什么需要】旧 Dart 代码把鸿蒙拦成「暂不支持」，播放页保存二维码又会
 * 走安卓的 `/storage/emulated/0/DCIM` 直写（鸿蒙同样报权限错误）。
 *
 * 鸿蒙正确做法：`photoAccessHelper.createAsset` 由媒体库分配文件，
 * 只需应用级「保存到图库」授权（无需文件系统权限）。
 *
 * 实现要点：
 * - `createAsset(displayName)` 拿到可写 uri 后 `fs.open` + `write`；
 * - 写完 `fs.close`，媒体库自动索引到相册；
 * - 文件名冲突由媒体库自动去重（同名多次保存不会覆盖）。
 */
export default class GallerySaverPlugin implements FlutterPlugin, MethodCallHandler {
  private channel: MethodChannel | null = null;
  private binding: FlutterPluginBinding | null = null;

  getUniqueClassName(): string {
    return TAG;
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.binding = binding;
    this.channel = new MethodChannel(
      binding.getBinaryMessenger(),
      CHANNEL,
      new StandardMethodCodec(),
    );
    this.channel.setMethodCallHandler(this);
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null);
    this.channel = null;
    this.binding = null;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (call.method === 'saveImage') {
      const bytes = call.argument('bytes') as ArrayBuffer | null;
      const fileName = (call.argument('fileName') as string | null) ?? 'image';
      if (bytes === null || bytes.byteLength === 0) {
        result.error('INVALID_ARG', 'bytes 为空', null);
        return;
      }
      this.saveImage(bytes, fileName)
        .then((ok: boolean): void => {
          result.success(ok);
        })
        .catch((err: BusinessError): void => {
          hilog.error(DOMAIN, TAG, '保存失败: %{public}s', JSON.stringify(err));
          result.success(false);
        });
      return;
    }
    if (call.method === 'supports') {
      result.success(true);
      return;
    }
    result.notImplemented();
  }

  /**
   * 保存 PNG 到相册。返回是否成功。
   *
   * 文件名补 `.png` 扩展名（`createAsset` 按扩展名决定媒体类型）。
   */
  private async saveImage(bytes: ArrayBuffer, fileName: string): Promise<boolean> {
    const name: string = fileName.endsWith('.png') ? fileName : `${fileName}.png`;
    const helper: photoAccessHelper.PhotoAccessHelper =
      photoAccessHelper.getPhotoAccessHelper(this.getContext());
    let uri: string = '';
    try {
      uri = await helper.createAsset(
        photoAccessHelper.PhotoType.IMAGE,
        name,
      );
      const file = await fs.open(uri, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
      try {
        await fs.write(file.fd, bytes);
        await fs.fsync(file.fd);
      } finally {
        await fs.close(file.fd);
      }
      return true;
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'createAsset/write 失败: %{public}d %{public}s',
        err.code, err.message);
      // 失败要清掉半成品，避免相册里留坏图。
      if (uri.length > 0) {
        try {
          await helper.deleteAssets([uri]);
        } catch (_) {
        }
      }
      return false;
    }
  }

  private getContext(): common.UIAbilityContext {
    const ctx = this.binding?.getApplicationContext();
    return ctx as common.UIAbilityContext;
  }
}
