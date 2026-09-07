import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:himi_syncwatch/core/app.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/services/emby_auth_service.dart';

class _SelfSignedHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = _SelfSignedHttpOverrides();
  MediaKit.ensureInitialized();

  final authService = EmbyAuthService();
  await authService.init();

  runApp(
    ProviderScope(
      overrides: [
        embyAuthServiceProvider.overrideWithValue(authService),
      ],
      child: const HimiSyncApp(),
    ),
  );
}
