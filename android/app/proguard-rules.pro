# NOVA X — R8/ProGuard rules (used when release shrinking is enabled).

# "Hey NOVA" wake word: sherpa-onnx's native code reads these classes and
# their fields by name over JNI, so they must not be renamed or removed.
-keep class com.k2fsa.sherpa.onnx.** { *; }
-keepclassmembers class com.k2fsa.sherpa.onnx.** { native <methods>; }
