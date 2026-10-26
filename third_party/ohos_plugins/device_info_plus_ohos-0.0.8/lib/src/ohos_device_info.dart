import 'package:device_info_plus_platform_interface/model/base_device_info.dart';

/// Information derived from `@ohos.deviceInfo`.
///
/// https://developer.harmonyos.com/cn/docs/documentation/doc-references-V3/js-apis-device-info-0000001428061996-V3

class OhosDeviceInfo extends BaseDeviceInfo {
  OhosDeviceInfo._({
    required Map<String, dynamic> data,
    required this.deviceType,
    required this.manufacture,
    required this.brand,
    required this.marketName,
    required this.productSeries,
    required this.productModel,
    required this.softwareModel,
    required this.hardwareModel,
    // required this.hardwareProfile,
    // required this.serial,
    required this.bootloaderVersion,
    required this.abiList,
    required this.securityPatchTag,
    required this.displayVersion,
    required this.incrementalVersion,
    required this.osReleaseType,
    required this.osFullName,
    required this.majorVersion,
    required this.seniorVersion,
    required this.featureVersion,
    required this.buildVersion,
    required this.sdkApiVersion,
    required this.firstApiVersion,
    required this.versionId,
    required this.buildType,
    required this.buildUser,
    required this.buildHost,
    required this.buildTime,
    required this.buildRootHash,
    // required this.udid,
    required this.odid,
    required this.distributionOSName,
    required this.distributionOSVersion,
    required this.distributionOSApiVersion,
    required this.distributionOSReleaseType,
    required this.isPhysicalDevice,
  }) : super(data);

  factory OhosDeviceInfo.fromMap(Map<String, dynamic> map) {
    return OhosDeviceInfo._(
      data: map,
      deviceType: map['deviceType'] ?? '',
      manufacture: map['manufacture'] ?? '',
      brand: map['brand'] ?? '',
      marketName: map['marketName'] ?? '',
      productSeries: map['productSeries'] ?? '',
      productModel: map['productModel'] ?? '',
      softwareModel: map['softwareModel'] ?? '',
      hardwareModel: map['hardwareModel'] ?? '',
      // hardwareProfile: map['hardwareProfile'] ?? '',
      // serial: map['serial'] ?? '',
      bootloaderVersion: map['bootloaderVersion'] ?? '',
      abiList: map['abiList'] ?? '',
      securityPatchTag: map['securityPatchTag'] ?? '',
      displayVersion: map['displayVersion'] ?? '',
      incrementalVersion: map['incrementalVersion'] ?? '',
      osReleaseType: map['osReleaseType'] ?? '',
      osFullName: map['osFullName'] ?? '',
      majorVersion: map['majorVersion'] ?? 0,
      seniorVersion: map['seniorVersion'] ?? 0,
      featureVersion: map['featureVersion'] ?? 0,
      buildVersion: map['buildVersion'] ?? 0,
      sdkApiVersion: map['sdkApiVersion'] ?? 0,
      firstApiVersion: map['firstApiVersion'] ?? 0,
      versionId: map['versionId'] ?? '',
      buildType: map['buildType'] ?? '',
      buildUser: map['buildUser'] ?? '',
      buildHost: map['buildHost'] ?? '',
      buildTime: map['buildTime'] ?? '',
      buildRootHash: map['buildRootHash'] ?? '',
      // udid: map['udid'] ?? '',
      odid: map['odid'] ?? '',
      distributionOSName: map['distributionOSName'] ?? '',
      distributionOSVersion: map['distributionOSVersion'] ?? '',
      distributionOSApiVersion: map['distributionOSApiVersion'] ?? 0,
      distributionOSReleaseType: map['distributionOSReleaseType'] ?? '',
      isPhysicalDevice: map['isPhysicalDevice'] == true,
    );
  }

  /// Device type.
  /// 设备类型。
  final String deviceType;

  /// Device manufacturer name.
  /// 设备厂家名称。
  final String manufacture;

  /// Device brand name.
  /// 设备品牌名称。
  final String brand;

  /// External product series.
  /// 外部产品系列。
  final String marketName;

  /// Product series.
  /// 产品系列。
  final String productSeries;

  /// Product model.
  /// 认证型号。
  final String productModel;

  /// Software model.
  /// 内部软件子型号。
  final String softwareModel;

  /// Hardware model.
  /// 硬件版本号。
  final String hardwareModel;

  /// Hardware profile.
  /// 硬件Profile。
  // @Deprecated('since api 9')
  // final String hardwareProfile;

  /// Requires permission: ohos.permission.sec.ACCESS_UDID (System permission, only open to system apps).
  /// Device serial number.
  /// 设备序列号。
  // final String serial;

  /// Bootloader version number.
  /// Bootloader版本号。
  final String bootloaderVersion;

  /// Application binary interface (Abi) list.
  /// 应用二进制接口（Abi）列表。
  final String abiList;

  /// Security patch level.
  /// 安全补丁级别。
  final String securityPatchTag;

  /// Product version.
  /// 产品版本。
  final String displayVersion;

  /// Incremental version.
  /// 差异版本号。
  final String incrementalVersion;

  /// OS release type.
  /// 系统的发布类型，取值为：
  /// - Canary：面向特定开发者发布的早期预览版本，不承诺API稳定性。
  /// - Beta：面向开发者公开发布的Beta版本，不承诺API稳定性。
  /// - Release：面向开发者公开发布的正式版本，承诺API稳定性。
  final String osReleaseType;

  /// OS version.
  /// 系统版本。
  final String osFullName;

  /// Major version number, increases with updates to the overall architecture.
  /// Major版本号，随主版本更新增加。
  final int majorVersion;

  /// Senior version number, increases with updates to the partial architecture or major features.
  /// Senior版本号，随局部架构、重大特性增加。
  final int seniorVersion;

  /// Feature version number, increases with planned new features.
  /// Feature版本号，标识规划的新特性版本。
  final int featureVersion;

  /// Build version number, increases with each new development build.
  /// Build版本号，标识编译构建的版本号。
  final int buildVersion;

  /// SDK API version number.
  /// 系统软件API版本。
  final int sdkApiVersion;

  /// First API version number.
  /// 首个版本系统软件API版本。
  final int firstApiVersion;

  /// Version ID.
  /// 版本ID。
  final String versionId;

  /// Build type.
  /// 构建类型。
  final String buildType;

  /// Build user.
  /// 构建用户。
  final String buildUser;

  /// Build host.
  /// 构建主机。
  final String buildHost;

  /// Build time.
  /// 构建时间。
  final String buildTime;

  /// Build version hash.
  /// 构建版本Hash。
  final String buildRootHash;

  /// Requires permission: ohos.permission.sec.ACCESS_UDID (System permission, only open to system apps).
  /// Device Udid.
  /// 设备Udid。
  // final String udid;

  /// Anymous Device ID
  /// 匿名设备ID。
  final String odid;

  /// Distribution OS name.
  /// 发行版系统名称。
  final String distributionOSName;

  /// Distribution OS version.
  /// 发行版系统版本号。
  final String distributionOSVersion;

  /// Distribution OS API version.
  /// 发行版系统API版本号。
  final int distributionOSApiVersion;

  /// Distribution OS release type.
  /// 发行版系统类型。
  final String distributionOSReleaseType;

  /// `false` if the application is running in an emulator, `true` otherwise.
  final bool isPhysicalDevice;

  Map<String, dynamic> toJson() {
    return {
      'deviceType': deviceType,
      'manufacture': manufacture,
      'brand': brand,
      'marketName': marketName,
      'productSeries': productSeries,
      'productModel': productModel,
      'softwareModel': softwareModel,
      'hardwareModel': hardwareModel,
      // 'hardwareProfile': hardwareProfile,
      // serial': serial,
      'bootloaderVersion': bootloaderVersion,
      'abiList': abiList,
      'securityPatchTag': securityPatchTag,
      'displayVersion': displayVersion,
      'incrementalVersion': incrementalVersion,
      'osReleaseType': osReleaseType,
      'osFullName': osFullName,
      'majorVersion': majorVersion,
      'seniorVersion': seniorVersion,
      'featureVersion': featureVersion,
      'buildVersion': buildVersion,
      'sdkApiVersion': sdkApiVersion,
      'firstApiVersion': firstApiVersion,
      'versionId': versionId,
      'buildType': buildType,
      'buildUser': buildUser,
      'buildHost': buildHost,
      'buildTime': buildTime,
      'buildRootHash': buildRootHash,
      // 'udid': udid,
      'distributionOSName': distributionOSName,
      'distributionOSVersion': distributionOSVersion,
      'distributionOSApiVersion': distributionOSApiVersion,
      'distributionOSReleaseType': distributionOSReleaseType,
      'isPhysicalDevice': isPhysicalDevice,
    };
  }
}

/// Information derived from `@ohos.deviceInfo`.
///
/// https://developer.harmonyos.com/cn/docs/documentation/doc-references-V3/js-apis-device-info-0000001428061996-V3

class OhosAccessUDIDInfo extends BaseDeviceInfo {
  OhosAccessUDIDInfo._({
    required Map<String, dynamic> data,
    required this.serial,
    required this.udid,
  }) : super(data);

  factory OhosAccessUDIDInfo.fromMap(Map<String, dynamic> map) {
    return OhosAccessUDIDInfo._(
      data: map,
      serial: map['serial'] ?? '',
      udid: map['udid'] ?? '',
    );
  }

  /// Requires permission: ohos.permission.sec.ACCESS_UDID (System permission, only open to system apps).
  /// Device serial number.
  /// 设备序列号。
  final String serial;

  /// Requires permission: ohos.permission.sec.ACCESS_UDID (System permission, only open to system apps).
  /// Device Udid.
  /// 设备Udid。
  final String udid;

  Map<String, dynamic> toJson() {
    return {
      'serial': serial,
      'udid': udid,
    };
  }
}
