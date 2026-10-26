import 'dart:async';
import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/providers/trakt_provider.dart';

class TraktDeepLinkListener extends ConsumerStatefulWidget {
  final Widget child;

  const TraktDeepLinkListener({super.key, required this.child});

  @override
  ConsumerState<TraktDeepLinkListener> createState() =>
      _TraktDeepLinkListenerState();
}

class _TraktDeepLinkListenerState extends ConsumerState<TraktDeepLinkListener>
    with WidgetsBindingObserver {
  AppLinks? _appLinks;
  StreamSubscription<Uri>? _subscription;
  Uri? _lastHandledUri;
  DateTime? _lastHandledAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (Platform.operatingSystem != 'ohos') {
      final appLinks = AppLinks();
      _appLinks = appLinks;
      _subscription = appLinks.uriLinkStream.listen(_handleUri);
      unawaited(_consumeInitialLink());
    }
    unawaited(_initProvider());
  }

  Future<void> _initProvider() async {
    final notifier = ref.read(traktProvider.notifier);
    await notifier.init();
    await notifier.maybeAutoSync();
  }

  Future<void> _consumeInitialLink() async {
    try {
      final uri = await _appLinks?.getInitialLink();
      if (uri != null) await _handleUri(uri);
    } catch (_) {}
  }

  Future<void> _handleUri(Uri uri) async {
    final now = DateTime.now();
    final previousAt = _lastHandledAt;
    if (_lastHandledUri == uri &&
        previousAt != null &&
        now.difference(previousAt) < const Duration(seconds: 5)) {
      return;
    }
    _lastHandledUri = uri;
    _lastHandledAt = now;
    await ref.read(traktProvider.notifier).handleCallback(uri);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(ref.read(traktProvider.notifier).maybeAutoSync());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
