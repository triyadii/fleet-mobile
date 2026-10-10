# R8 rules for the release build.
#
# ML Kit face detection crashes in minified builds with
# "InputImageConverterError ... NullPointerException ... getClass()"
# because R8 strips/optimises internals it reaches via reflection/JNI.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_common.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_face.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_face_bundled.** { *; }
-keep class com.google.android.gms.vision.** { *; }
-keep class com.google_mlkit_commons.** { *; }
-keep class com.google_mlkit_face_detection.** { *; }
-dontwarn com.google.mlkit.**
-dontwarn com.google.android.gms.**

# CameraX image analysis/capture use reflection for some quirks.
-keep class androidx.camera.** { *; }
