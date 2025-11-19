# SSH Systemd Logs

Flutter application that connects to remote Linux servers over SSH and streams their systemd logs in real time. Users can manage multiple servers, switch between services, and configure how many historical log lines are loaded.

## Features

- Securely connect to servers using SSH credentials or private key pairs.
- Discover and list available systemd services that produce logs.
- Stream logs in real time with filtering, search, and severity highlighting.
- Persist server list and preferences locally using shared preferences.
- Configure how many recent log lines are fetched on connect (defaults to 100 lines).

## Getting Started

1. Ensure Flutter (3.19 or newer) is installed.
2. Run `flutter pub get` to install dependencies.
3. Launch the application with `flutter run`.

## Run and Build Commands

- Debug run on a connected device or emulator: `flutter run -d <device_id>`.
- Profile run to inspect performance: `flutter run --profile -d <device_id>`.
- Release build for Android APK: `flutter build apk --release`.
- Release build for Android App Bundle: `flutter build appbundle --release`.
- Release build for Windows desktop: `flutter build windows --release`.
- Release build for the web (release mode): `flutter build web --release`.

## Architecture

- **Riverpod** is used for state management.
- **dartssh2** powers the SSH communication layer.
- **shared_preferences** persists server definitions and app settings.

## Development

- Update dependencies with `flutter pub get`.
- Run `dart format lib` before committing changes.
- The app relies on the `dartssh2` package, so ensure OpenSSH-compatible keys are used when testing connections.
