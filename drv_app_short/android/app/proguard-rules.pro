# ──────────────────────────────────────────────────────────────────────────────
# JAGO Pilot (Driver) — Production ProGuard / R8 Rules
# ──────────────────────────────────────────────────────────────────────────────

# ── Flutter Engine ────────────────────────────────────────────────────────────
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugin.common.** { *; }
-keep class io.flutter.view.** { *; }
-dontwarn io.flutter.**

# ── Google Maps ───────────────────────────────────────────────────────────────
-keep class com.google.android.gms.maps.** { *; }
-keep interface com.google.android.gms.maps.** { *; }
-keep class com.google.maps.android.** { *; }
-dontwarn com.google.android.gms.maps.**

# ── Google Play Services (GMS) ────────────────────────────────────────────────
-keep class com.google.android.gms.** { *; }
-keep interface com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**

# ── Firebase Core ─────────────────────────────────────────────────────────────
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.internal.firebase** { *; }
-dontwarn com.google.firebase.**
-keep class com.google.firebase.components.** { *; }
-keep class com.google.firebase.provider.** { *; }

# ── Firebase Messaging (FCM) ──────────────────────────────────────────────────
-keep class com.google.firebase.messaging.** { *; }
-keep class io.flutter.plugins.firebase.messaging.** { *; }
-dontwarn com.google.firebase.messaging.**

# ── Firebase Crashlytics ──────────────────────────────────────────────────────
-keep class com.google.firebase.crashlytics.** { *; }
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile
-keep public class * extends java.lang.Exception

# ── Firebase Analytics ────────────────────────────────────────────────────────
-keep class com.google.firebase.analytics.** { *; }
-keep class com.google.android.gms.measurement.** { *; }

# ── Razorpay ──────────────────────────────────────────────────────────────────
-keep class com.razorpay.** { *; }
-dontwarn com.razorpay.**
-keep @interface proguard.annotation.Keep
-keepclassmembers class * {
    @proguard.annotation.Keep *;
}
-keepattributes *Annotation*
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}
# Razorpay uses Proton (internal payment library)
-keep class com.proton.** { *; }
-dontwarn com.proton.**

# ── Socket.IO / OkHttp / Okio ─────────────────────────────────────────────────
-keep class io.socket.** { *; }
-dontwarn io.socket.**
-keep class okhttp3.** { *; }
-dontwarn okhttp3.**
-keep class okio.** { *; }
-dontwarn okio.**

# ── Flutter Local Notifications ───────────────────────────────────────────────
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-dontwarn com.dexterous.flutterlocalnotifications.**

# ── Flutter Secure Storage ────────────────────────────────────────────────────
-keep class com.it_nomads.fluttersecurestorage.** { *; }
-dontwarn com.it_nomads.fluttersecurestorage.**

# ── Geolocator ────────────────────────────────────────────────────────────────
-keep class com.baseflow.geolocator.** { *; }
-dontwarn com.baseflow.geolocator.**

# ── Permission Handler ────────────────────────────────────────────────────────
-keep class com.baseflow.permissionhandler.** { *; }
-dontwarn com.baseflow.permissionhandler.**

# ── Image Picker ──────────────────────────────────────────────────────────────
-keep class io.flutter.plugins.imagepicker.** { *; }
-dontwarn io.flutter.plugins.imagepicker.**

# ── Camera ────────────────────────────────────────────────────────────────────
-keep class io.flutter.plugins.camera.** { *; }
-dontwarn io.flutter.plugins.camera.**

# ── Path Provider ─────────────────────────────────────────────────────────────
-keep class io.flutter.plugins.pathprovider.** { *; }
-dontwarn io.flutter.plugins.pathprovider.**

# ── Shared Preferences ────────────────────────────────────────────────────────
-keep class io.flutter.plugins.sharedpreferences.** { *; }
-dontwarn io.flutter.plugins.sharedpreferences.**

# ── Audio Players ─────────────────────────────────────────────────────────────
-keep class xyz.luan.audioplayers.** { *; }
-dontwarn xyz.luan.audioplayers.**

# ── Just Audio ────────────────────────────────────────────────────────────────
-keep class com.ryanheise.just_audio.** { *; }
-dontwarn com.ryanheise.just_audio.**
-keep class com.ryanheise.audioservice.** { *; }
-dontwarn com.ryanheise.audioservice.**

# ── Flutter TTS ───────────────────────────────────────────────────────────────
-keep class com.tundralabs.fluttertts.** { *; }
-dontwarn com.tundralabs.fluttertts.**

# ── Cached Network Image / Glide ──────────────────────────────────────────────
-keep class com.bumptech.glide.** { *; }
-dontwarn com.bumptech.glide.**

# ── Flutter Jailbreak Detection ───────────────────────────────────────────────
-keep class com.mariussoft.flutterjailbreakdetection.** { *; }
-dontwarn com.mariussoft.flutterjailbreakdetection.**
-keep class com.scottyab.rootbeer.** { *; }
-dontwarn com.scottyab.rootbeer.**

# ── URL Launcher ──────────────────────────────────────────────────────────────
-keep class io.flutter.plugins.urllauncher.** { *; }
-dontwarn io.flutter.plugins.urllauncher.**

# ── Google Fonts / SVG ────────────────────────────────────────────────────────
-keep class com.google.fonts.** { *; }

# ── Kotlin / Coroutines ───────────────────────────────────────────────────────
-keep class kotlin.** { *; }
-keep class kotlin.Metadata { *; }
-dontwarn kotlin.**
-keep class kotlinx.coroutines.** { *; }
-dontwarn kotlinx.coroutines.**

# ── JSON (keep data model serialization intact) ───────────────────────────────
-keepattributes Signature
-keepattributes InnerClasses
-keepattributes EnclosingMethod

# ── Multidex ──────────────────────────────────────────────────────────────────
-keep class androidx.multidex.** { *; }

# ── AndroidX ──────────────────────────────────────────────────────────────────
-keep class androidx.** { *; }
-dontwarn androidx.**

# ── Conscrypt (TLS / Certificate Pinning) ────────────────────────────────────
-keep class org.conscrypt.** { *; }
-dontwarn org.conscrypt.**

# ── Prevent stripping native methods ─────────────────────────────────────────
-keepclasseswithmembernames class * {
    native <methods>;
}

# ── Keep all enums intact (R8 can wrongly strip enum values) ─────────────────
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# ── Keep Parcelable implementations ──────────────────────────────────────────
-keepclassmembers class * implements android.os.Parcelable {
    public static final android.os.Parcelable$Creator CREATOR;
}

# ── Keep Serializable classes ─────────────────────────────────────────────────
-keepnames class * implements java.io.Serializable
-keepclassmembers class * implements java.io.Serializable {
    static final long serialVersionUID;
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    !static !transient <fields>;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}

# ── R8 full mode — suppress reflection warnings ───────────────────────────────
-ignorewarnings
