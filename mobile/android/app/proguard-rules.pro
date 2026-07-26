# androidx.work initializes its Room-backed WorkDatabase via reflection
# through androidx.startup.InitializationProvider. Without this rule, R8
# strips/renames WorkDatabase_Impl's no-arg constructor and the app
# crashes on launch with NoSuchMethodException before Application.onCreate
# even runs (confirmed against the v0.2.0 release build).
-keep class * extends androidx.room.RoomDatabase {
    <init>(...);
}
-keep class androidx.work.impl.WorkDatabase_Impl { *; }
