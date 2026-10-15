# Razorpay SDK uses reflection; without these keep rules a minified release
# build can crash with ClassNotFoundException during checkout.
-keep class com.razorpay.** { *; }
-keep class proguard.annotation.Keep { *; }
-keep class proguard.annotation.KeepClassMembers { *; }
-dontwarn com.razorpay.**
-optimizations !method/inlining/*
