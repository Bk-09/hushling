# Calm (Flutter)

Flutter port of the Pygame "Calm" app: panic (flame breathing + grounding + landing), anxiety, stress,
positivity, and the companion pet. All sounds are generated in code; saved data uses shared_preferences.

## One-time setup (this zip has no android/ windows/ folders yet)
1. Unzip, open the `calm_flutter` folder in VS Code.
2. In the VS Code terminal, in that folder:
   ```
   flutter create . --project-name calm --platforms=windows,android
   flutter pub get
   ```
   (`flutter create .` only adds the platform folders; it keeps lib/ and pubspec.yaml.
   If it overwrote pubspec.yaml, re-check that `assets/pets/` and the 3 dependencies are still there.)
3. Run: `flutter run -d windows` (or pick a device at the bottom-right of VS Code).

## Windows desktop
Needs "Desktop development with C++" (Visual Studio 2022). Check with `flutter doctor`.
Build: `flutter build windows` -> build\windows\x64\runner\Release\

## Android
Phone with USB debugging, or an emulator, then `flutter run`. Build: `flutter build apk`.
The app is landscape-only on phones (the 900x600 stage scales to fit).
