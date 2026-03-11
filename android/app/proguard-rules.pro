## Gson TypeToken — required by flutter_local_notifications
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken

## Keep flutter_local_notifications receivers (scheduled notifications)
-keep class com.dexterous.flutterlocalnotifications.** { *; }
