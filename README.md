# SSH Systemd Logs

Flutter application that connects to remote Linux servers over SSH and streams their systemd logs in real time. Users can manage multiple servers, switch between services, and configure log retention depth.

## Features

- Securely connect to servers using SSH credentials or private key pairs.
- Discover and list available systemd services that produce logs.
- Stream logs in real time with filtering, search, and severity highlighting.
- Persist server list and preferences locally using shared preferences.
- Configure log retention depth globally (defaults to 7 days).

## Getting Started

1. Ensure Flutter (3.19 or newer) is installed.
2. Run `flutter pub get` to install dependencies.
3. Launch the application with `flutter run`.

## Architecture

- **Riverpod** is used for state management.
- **dartssh2** powers the SSH communication layer.
- **shared_preferences** persists server definitions and app settings.

## Development

- Update dependencies with `flutter pub get`.
- Run `dart format lib` before committing changes.
- The app relies on the `dartssh2` package, so ensure OpenSSH-compatible keys are used when testing connections.
