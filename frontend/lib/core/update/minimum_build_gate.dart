import 'dart:async';

import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../firebase/firebase_bootstrap.dart';
import '../storage/storage_feature_flag.dart';
import 'update_required_screen.dart';

/// Remote Config gate. Defaults never block. A failed read never blocks.
abstract final class MinimumBuildGate {
  static const androidKey = 'min_supported_build_android';
  static const iosKey = 'min_supported_build_ios';
  static const messageKey = 'update_required_message';
  static const androidStoreKey = 'store_url_android';
  static const iosStoreKey = 'store_url_ios';
  static const defaultMessage = 'Please update DoctorNect to continue.';
  static const readTimeout = Duration(seconds: 2);

  @visibleForTesting
  static MinimumBuildSnapshot? debugSnapshot;

  static bool shouldBlock(MinimumBuildSnapshot snapshot) {
    if (snapshot.isWeb) return false;
    if (!snapshot.configReadable) return false;
    final installed = snapshot.installedBuild;
    final minimum = snapshot.minimumBuild;
    if (installed == null || minimum == null) return false;
    if (snapshot.storeUrl.trim().isEmpty) return false;
    return installed < minimum;
  }

  static Future<MinimumBuildSnapshot> read() async {
    if (debugSnapshot != null) return debugSnapshot!;
    if (kIsWeb) {
      return const MinimumBuildSnapshot(isWeb: true, configReadable: true);
    }
    try {
      return await _readNative().timeout(readTimeout);
    } catch (_) {
      return const MinimumBuildSnapshot(configReadable: false);
    }
  }

  static Future<MinimumBuildSnapshot> _readNative() async {
    if (!FirebaseBootstrap.isReady) {
      return const MinimumBuildSnapshot(configReadable: false);
    }
    await StorageFeatureFlag.initialize().timeout(readTimeout);
    final remote = FirebaseRemoteConfig.instance;
    final ios = defaultTargetPlatform == TargetPlatform.iOS;
    final minimum = _parseInt(remote.getValue(ios ? iosKey : androidKey));
    final info = await PackageInfo.fromPlatform().timeout(readTimeout);
    final installed = int.tryParse(info.buildNumber.trim());
    final storeUrl = remote.getString(ios ? iosStoreKey : androidStoreKey);
    final message = remote.getString(messageKey).trim();
    return MinimumBuildSnapshot(
      configReadable: minimum != null,
      installedBuild: installed,
      minimumBuild: minimum,
      storeUrl: storeUrl,
      message: message.isEmpty ? defaultMessage : message,
    );
  }

  static int? _parseInt(RemoteConfigValue value) {
    try {
      final source = value.asString().trim();
      if (source.isEmpty) return value.asInt();
      return int.tryParse(source);
    } catch (_) {
      return null;
    }
  }
}

@immutable
class MinimumBuildSnapshot {
  const MinimumBuildSnapshot({
    this.isWeb = false,
    this.configReadable = false,
    this.installedBuild,
    this.minimumBuild,
    this.storeUrl = '',
    this.message = MinimumBuildGate.defaultMessage,
  });

  final bool isWeb;
  final bool configReadable;
  final int? installedBuild;
  final int? minimumBuild;
  final String storeUrl;
  final String message;
}

/// Covers the whole app. Checks once at start and again when the app resumes.
class MinimumBuildHost extends StatefulWidget {
  const MinimumBuildHost({super.key, required this.child});

  final Widget child;

  @override
  State<MinimumBuildHost> createState() => _MinimumBuildHostState();
}

class _MinimumBuildHostState extends State<MinimumBuildHost>
    with WidgetsBindingObserver {
  MinimumBuildSnapshot? _blocking;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refresh());
    }
  }

  Future<void> _refresh() async {
    final snapshot = await MinimumBuildGate.read();
    if (!mounted) return;
    setState(() {
      _blocking = MinimumBuildGate.shouldBlock(snapshot) ? snapshot : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final blocking = _blocking;
    if (blocking == null) return widget.child;
    return UpdateRequiredScreen(
      message: blocking.message,
      storeUrl: blocking.storeUrl,
    );
  }
}
