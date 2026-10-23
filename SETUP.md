# Getting the app running

## 1. Install Flutter (not installed on this machine yet)
Follow https://docs.flutter.dev/get-started/install/windows, then check `flutter doctor`.

## 2. Generate the platform folders
The Dart code and `pubspec.yaml` are already here. From the project root run:
```
flutter create . --project-name bookingapp --org com.yourcompany --platforms android,ios
flutter pub get
```
`flutter create .` adds `android/` and `ios/` without touching existing files in `lib/`.
If it generates a default `test/widget_test.dart`, delete it (it refers to a counter app that does not exist here).

Android needs the camera permission for the QR scanner. In `android/app/src/main/AndroidManifest.xml`, inside `<manifest>`:
```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.INTERNET" />
```
On iOS, add `NSCameraUsageDescription` to `ios/Runner/Info.plist`.

## 3. Set up Supabase
See [supabase/README.md](supabase/README.md).

## 4. Run
```
flutter run --dart-define=SUPABASE_URL=https://<ref>.supabase.co --dart-define=SUPABASE_ANON_KEY=<anon key>
```

## 5. Test
```
flutter test
flutter analyze
```
