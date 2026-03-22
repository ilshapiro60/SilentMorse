import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Test ad unit IDs for development (always show test ads).
const _androidTestBannerId = 'ca-app-pub-3940256099942544/6300978111';
const _iosTestBannerId = 'ca-app-pub-3940256099942544/2934735716';

/// Production ad unit IDs. Replace with your IDs from admob.google.com.
/// Leave empty to use test IDs in production (not recommended for release).
const _androidProdBannerId = '';
const _iosProdBannerId = '';

/// Initializes Google Mobile Ads SDK.
/// Call from main() before runApp.
Future<void> initAdMob() async {
  await MobileAds.instance.initialize();
}

/// Returns the banner ad unit ID for the current platform, or empty string
/// if no production ID is configured for this platform (ads will be hidden).
String get bannerAdUnitId {
  if (!kDebugMode) {
    // Release build — only show ads if a real prod ID is configured.
    if (Platform.isAndroid && _androidProdBannerId.isNotEmpty) {
      return _androidProdBannerId;
    }
    if (!Platform.isAndroid && _iosProdBannerId.isNotEmpty) {
      return _iosProdBannerId;
    }
    // No prod ID configured — return empty to suppress ads cleanly.
    return '';
  }
  // Debug build — use test IDs.
  return Platform.isAndroid ? _androidTestBannerId : _iosTestBannerId;
}
