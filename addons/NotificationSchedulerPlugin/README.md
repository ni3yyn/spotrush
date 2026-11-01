# Godot Notification Scheduler v6.0 — SpotRush integration

SpotRush uses the official [Godot Mobile Plugins Notification Scheduler](https://github.com/godot-mobile-plugins/godot-notification-scheduler) v6.0 interface. This project keeps the matching GDScript wrapper/models and Android export hook under `addons/NotificationSchedulerPlugin`.

The native Android AARs are downloaded from the official v6.0 release and checksum-verified by `.github/workflows/android-apk.yml`. For a local Windows export, run `scripts/dev/install_notification_plugin_v6.ps1` from PowerShell before exporting. The installer places the official debug/release AARs in the paths expected by `NotificationSchedulerPlugin.gd`.

The v6.0 Android plugin targets Godot 4.7 and Android API 24+. The Android export preset is configured with minSdk 24.
