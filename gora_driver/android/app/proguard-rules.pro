# Razorpay SDK uses reflection; without these keep rules a minified release
# build can crash with ClassNotFoundException during checkout.
-keep class com.razorpay.** { *; }
-keep class proguard.annotation.Keep { *; }
-keep class proguard.annotation.KeepClassMembers { *; }
-dontwarn com.razorpay.**
-optimizations !method/inlining/*

# Flutter local notifications / foreground task use GSON-style reflection
# for their payload classes.
-keep class com.dexterous.** { *; }
-keep class com.pravera.flutter_foreground_task.** { *; }

# ML Kit face detection loads its model/vision classes dynamically — this
# build succeeded without these rules, but R8 stripping a reflection-loaded
# class shows up as a runtime crash, not a build failure, and there was no
# real device available in this environment to confirm it at runtime.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.vision.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_face.** { *; }
-dontwarn com.google.mlkit.**
