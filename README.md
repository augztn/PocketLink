# PocketLink

**Your personal files and media, available across your trusted devices.**

PocketLink is an Android-first, self-hosted file and media app. It combines a Flutter interface with a native Android host, so one app can make your device's storage available to your other trusted devices—without Termux, Python, or a separately managed server.

Browse files, work with USB/SSD storage, and play your original media over a private connection.

## What PocketLink does

- **File access:** browse internal storage and supported USB/SSD locations.
- **File operations:** upload, download, create folders, rename and manage files.
- **Music and video:** play media directly from the host device, with HTTP byte-range support for seeking.
- **Photos and documents:** browse your personal library from the app.
- **Private remote access:** connect through Tailscale between devices you control.
- **Native Android integration:** use Android storage access and a foreground service for the in-app host.

PocketLink is designed around a simple rule: features and settings should represent real behaviour. Unsupported options and pretend capabilities do not belong in the app.

## How it works

1. Install PocketLink on the Android device that holds your files.
2. Configure the app's host and grant access to the storage you want to use.
3. Connect your trusted devices through Tailscale.
4. Open PocketLink on a client device and connect to the host using its private Tailscale address and your configured credentials.

The host runs inside PocketLink's native Android component. You do not need to maintain a separate terminal session or install a Python server.

> **Development status:** PocketLink is actively developed. Features, platform support and setup flows may change. This repository is the source code; check the latest releases and project notes before relying on it for important data.

## Storage

- Internal storage uses Android's permission model.
- USB drives and SSDs use Android's Storage Access Framework (SAF). Availability and write access depend on the Android device and the storage provider.
- Storage locations are discovered by the app; clients should not assume volume identifiers or filesystem paths.
- File operations are restricted to the storage roots granted to PocketLink.
- PocketLink does not impose an application-level upload or download size cap. Actual transfers remain subject to available storage, Android providers, memory and device/network conditions.

## Media playback

PocketLink streams the original audio and video files from their source. The server supports HTTP byte ranges for seeking and sends `Cache-Control: no-transform`.

Original media is not transcoded, recompressed, resized or bitrate-adjusted by the streaming endpoint. Generated thumbnails are separate previews and do not modify the source files.

## Private connection and security

The native host listens on HTTP port `8000`. Its cleartext connection policy accepts only:

- Localhost / loopback connections; and
- Tailscale peer addresses (IPv4 `100.64.0.0/10` and IPv6 `fd7a:115c:a1e0::/48`).

Remote access relies on Tailscale's encrypted WireGuard tunnel. Ordinary LAN and public-network HTTP peers are rejected by the native host. Do not expose port `8000` directly to the public internet.

All API routes except `/health` require HTTP Basic authentication. The health route is also subject to the peer policy. The app configures the host credentials; the server verifies the password using a salted PBKDF2 verifier rather than storing the password as plaintext.

For additional deployment details, see the [API contract](docs/API_CONTRACT.md).

## Build from source

### Requirements

- Flutter SDK (stable) compatible with the version constraints in `clients/flutter/pubspec.yaml`
- Android SDK and Android build tools
- A supported Android device or emulator

### Flutter client

```sh
cd clients/flutter
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

The Android storage and host integration is implemented in the local plugin at `clients/flutter/packages/pocketlink_saf`. Its Kotlin unit tests live in that module's `src/test` source set.

## Repository structure

| Path | Purpose |
| --- | --- |
| `clients/flutter/lib` | Flutter UI, app state, networking, media and transfers |
| `clients/flutter/packages/pocketlink_saf` | Native Android storage bridge and host implementation |
| `server` | Legacy FastAPI/Termux SAF compatibility helpers; not used by the native Android host |
| `docs` | API and implementation documentation |
| `.github/workflows` | Continuous integration and build workflows |

## Project principles

- Keep file access predictable and scoped to explicitly granted storage.
- Preserve original media bytes during playback.
- Prefer reliable, understandable features over placeholder settings.
- Handle unavailable storage providers and network failures explicitly.
- Keep credentials in platform secure storage and never disable TLS certificate validation in a TLS-based deployment.

## Credits

PocketLink is created and maintained by [augztn](https://github.com/augztn).

If PocketLink is useful to you, a mention of the project and a link to [this repository](https://github.com/augztn/PocketLink) are appreciated. This is a friendly request, not an additional condition of the MIT License.

## License

PocketLink is licensed under the [MIT License](LICENSE).
