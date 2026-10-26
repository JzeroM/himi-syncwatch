/// Defines the state of a [PermissionOhos].
/// 相应请求权限的结果：
/// - -1：未授权，表示权限已设置，无需弹窗，需要用户在"设置"中修改。
///
/// - 0：已授权。
///
/// - 2：未授权，表示请求无效，可能原因有：
///
/// -未在设置文件中声明目标权限。
///
/// -权限名非法。
///
/// -部分权限存在特殊申请条件，在申请对应权限时未满足其指定的条件 见 ohos.permission.LOCATION 与 ohos.permission.APPROXIMATELY_LOCATION
enum PermissionStatusOhos {
  /// The user denied access to the requested feature, permission needs to be
  /// asked first.
  denied(-1),

  /// The user granted access to the requested feature.
  granted(0),

  /// Invalid request.
  invalid(2),
  ;

  const PermissionStatusOhos(this.value);

  final int value;
}
