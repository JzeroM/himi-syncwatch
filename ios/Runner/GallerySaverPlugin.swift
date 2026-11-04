import Flutter
import Photos
import UIKit

/// 图片保存到系统相册（590，iOS）。
///
/// 【为什么需要】旧 Dart 代码把图片写到应用私有 Documents 目录，用户在
/// 「照片」App 里根本看不到，等于「保存失败」。
///
/// 正确做法：`PHPhotoLibrary.performChanges` + `PHAssetCreationRequest`
/// 写入相册。需要 `NSPhotoLibraryAddUsageDescription`（仅「添加」权限，
/// 比完整相册读取权限更小）。iOS 14+ 还会弹「仅添加照片」授权框。
class GallerySaverPlugin: NSObject, FlutterPlugin {
  static let channelName = "himi/gallery_saver"

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: registrar.messenger()
    )
    let instance = GallerySaverPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "saveImage":
      guard let args = call.arguments as? [String: Any],
            let data = args["bytes"] as? FlutterStandardTypedData,
            !data.data.isEmpty else {
        result(FlutterError(code: "INVALID_ARG", message: "bytes 为空", details: nil))
        return
      }
      let fileName = (args["fileName"] as? String) ?? "image"
      saveImage(data.data, fileName: fileName, result: result)
    case "supports":
      result(true)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// 写入相册；返回是否成功。
  ///
  /// 授权流程：`requestAuthorization(for: .addOnly)`（iOS 14+）/
  /// `requestAuthorization`（更早系统）。被拒绝直接返回 false，
  /// Dart 侧提示「保存失败，请重试」。
  private func saveImage(_ data: Data, fileName: String, result: @escaping FlutterResult) {
    let requestAuthorization: (@escaping (PHAuthorizationStatus) -> Void) -> Void = { completion in
      if #available(iOS 14, *) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
          completion(status)
        }
      } else {
        PHPhotoLibrary.requestAuthorization { status in
          completion(status)
        }
      }
    }

    requestAuthorization { status in
      guard status == .authorized || status == .limited else {
        DispatchQueue.main.async { result(false) }
        return
      }
      PHPhotoLibrary.shared().performChanges {
        let request = PHAssetCreationRequest.forAsset()
        let options = PHAssetResourceCreationOptions()
        // 相册内文件名（不含扩展名也可，系统按 UTI 归类为图片）。
        options.originalFilename = fileName.hasSuffix(".png") ? fileName : "\(fileName).png"
        request.addResource(with: .photo, data: data, options: options)
      } completionHandler: { success, error in
        if let error = error {
          NSLog("[GallerySaver] 保存失败: \(error.localizedDescription)")
        }
        DispatchQueue.main.async { result(success) }
      }
    }
  }
}
