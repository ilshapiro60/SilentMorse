# flutter_wear references Wear OS APIs; they are absent on phone APKs. R8 full mode
# treats missing classes as errors unless suppressed (see missing_rules.txt from AGP).
-dontwarn com.google.android.wearable.compat.WearableActivityController$AmbientCallback
-dontwarn com.google.android.wearable.compat.WearableActivityController
