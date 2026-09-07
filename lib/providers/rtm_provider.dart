import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/services/rtm_service.dart';

final rtmServiceProvider = Provider<RtmService>((ref) {
  final service = RtmService();
  ref.onDispose(() => service.dispose());
  return service;
});
