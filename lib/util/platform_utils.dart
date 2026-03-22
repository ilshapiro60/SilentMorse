import 'platform_utils_stub.dart'
    if (dart.library.io) 'platform_utils_io.dart'
    if (dart.library.html) 'platform_utils_web.dart';

/// Whether Sign in with Apple is available (iOS/macOS only; Android requires extra setup).
bool get isAppleSignInAvailable => getIsAppleSignInAvailable();

/// Whether running on Android.
bool get isAndroid => getIsAndroid();
