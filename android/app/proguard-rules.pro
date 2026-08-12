# EliteRadIq production R8 rules
# Flutter plugin registrants / generated entry points
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }

# Keep Android activities/services referenced by manifest or plugins.
-keep public class * extends android.app.Activity { *; }
-keep public class * extends android.app.Service { *; }
-keep public class * extends android.content.BroadcastReceiver { *; }

# Keep native methods and their names.
-keepclasseswithmembernames,includedescriptorclasses class * {
    native <methods>;
}

# Keep enum values used by platform/plugin serialization.
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}
