# Keep the biometric and secure storage plugins intact.
-keep class androidx.biometric.** { *; }
-keep class com.it_nomads.fluttersecurestorage.** { *; }
# Supabase and its HTTP stack use reflection for JSON.
-keep class io.supabase.** { *; }
-dontwarn org.bouncycastle.**
-dontwarn org.conscrypt.**
-dontwarn org.openjsse.**
