/// Apple Sign-In configuration for Android.
/// Required for "Continue with Apple" on Android. See APPLE_SIGNIN_SETUP.md.
///
/// Fill these in after creating a Service ID in the Apple Developer Portal.
const String appleSignInClientId = 'com.silentmorse.messenger.service';
const String appleSignInRedirectUri = 'https://us-central1-silent-morse-messenger.cloudfunctions.net/appleSignInCallback';
