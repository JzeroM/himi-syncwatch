import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/emby_error.dart';
import 'package:himi_syncwatch/services/lan_config/emby_setup_service.dart';

DioException _dio({
  int? statusCode,
  DioExceptionType type = DioExceptionType.badResponse,
}) {
  final options = RequestOptions(path: '/Users/AuthenticateByName');
  return DioException(
    requestOptions: options,
    type: type,
    response: statusCode == null
        ? null
        : Response(requestOptions: options, statusCode: statusCode),
  );
}

void main() {
  group('friendlyEmbyError', () {
    test('EmbySetupException 原样返回业务文案', () {
      expect(friendlyEmbyError(EmbySetupException('用户名不能为空')), '用户名不能为空');
    });

    test('401 / 400 → 用户名或密码错误', () {
      expect(friendlyEmbyError(_dio(statusCode: 401)), '用户名或密码错误');
      expect(friendlyEmbyError(_dio(statusCode: 400)), '用户名或密码错误');
    });

    test('403 → 没有权限登录', () {
      expect(friendlyEmbyError(_dio(statusCode: 403)), '没有权限登录');
    });

    test('其它 HTTP 状态码 → 带状态码提示', () {
      expect(friendlyEmbyError(_dio(statusCode: 500)), '登录失败（HTTP 500）');
    });

    test('连接错误 → 无法连接服务器', () {
      expect(
        friendlyEmbyError(_dio(type: DioExceptionType.connectionError)),
        '无法连接服务器，请检查地址或网络',
      );
    });

    test('各类超时 → 连接超时', () {
      for (final t in [
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
      ]) {
        expect(friendlyEmbyError(_dio(type: t)), '连接超时，请检查网络');
      }
    });

    test('证书错误 → 证书校验失败', () {
      expect(
        friendlyEmbyError(_dio(type: DioExceptionType.badCertificate)),
        '证书校验失败',
      );
    });

    test('普通异常 / 未知类型 → 通用兜底（不透出英文）', () {
      expect(friendlyEmbyError(Exception('boom')), '登录失败，请稍后重试');
      expect(
        friendlyEmbyError(_dio(type: DioExceptionType.unknown)),
        '登录失败，请稍后重试',
      );
    });
  });
}
