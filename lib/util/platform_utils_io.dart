import 'dart:io';

bool getIsAppleSignInAvailable() => Platform.isIOS || Platform.isMacOS;
bool getIsAndroid() => Platform.isAndroid;
