import 'package:dio/dio.dart';

import 'package:himi_syncwatch/services/lan_config/emby_setup_service.dart';

/// 把登录/请求异常翻译成简短中文提示，避免把 Dio/网络英文异常串直接展示给用户。
///
/// 各登录入口（添加/编辑服务器、重新登录、扫码配置）统一使用，保证文案一致。
String friendlyEmbyError(Object error) {
  if (error is EmbySetupException) return error.message;

  if (error is DioException) {
    final code = error.response?.statusCode;
    if (code == 400 || code == 401) return '用户名或密码错误';
    if (code == 403) return '没有权限登录';
    if (code != null) return '登录失败（HTTP $code）';

    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return '连接超时，请检查网络';
      case DioExceptionType.badCertificate:
        return '证书校验失败';
      case DioExceptionType.connectionError:
        return '无法连接服务器，请检查地址或网络';
      default:
        return '登录失败，请稍后重试';
    }
  }

  return '登录失败，请稍后重试';
}
