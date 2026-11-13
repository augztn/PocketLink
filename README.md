# HomeServer

A free, open-source server management client built with Flutter and a FastAPI backend.

HomeServer is designed to make self-hosted servers approachable: enter a server address, connect, and manage supported capabilities through a graphical interface.

## Project status

**Early development.** The Flutter client supports authenticated file management and HTTP byte-range media streaming against the existing FastAPI backend.

## Planned platforms

- Android
- Linux (portable AppImage)
- Windows
- iOS (where supported by Flutter and platform dependencies)

## Media streaming

The client includes separate Music and Videos libraries. It streams supported audio and
video files directly from the server with HTTP Basic Authentication and byte-range
requests, so seeking does not require downloading the entire file first.

Supported extensions include MP3, M4A, AAC, WAV, FLAC, OGG, MP4, MKV, WebM, MOV and AVI.
Actual playback depends on the codecs available in the media file and the target device.

Linux desktop builds use libmpv. Install the runtime dependency on Ubuntu/Debian with:

```sh
sudo apt install libmpv-dev mpv
```

Use HTTPS when connecting over an untrusted network. A private VPN such as Tailscale
is recommended for remote access.

## Linux AppImage

GitHub Actions builds a portable x86_64 AppImage for Linux. Open the latest successful
[Flutter CI workflow](https://github.com/augztn/syslab/actions/workflows/flutter.yml),
download the `HomeServer-Linux-x86_64-AppImage` artifact, then run:

```sh
chmod +x HomeServer-x86_64.AppImage
./HomeServer-x86_64.AppImage
```

The AppImage is currently built for x86_64 Linux desktops. ARM64 Linux packaging is not included yet.

## Development

Install the Flutter stable SDK, then run:

```sh
cd clients/flutter
flutter pub get
flutter run
```

Run tests:

```sh
flutter test
```

## Architecture

- `clients/flutter`: cross-platform Flutter application.
- `server`: existing FastAPI backend (to be brought into this repository without replacing the deployed copy).
- `docs`: API contract, security model, and deployment documentation.

The client communicates with the server over HTTP(S). Remote deployments should use HTTPS. Administrative actions must be explicitly authorized and capability-gated by the backend; HomeServer will not expose an unrestricted root shell.

## Security principles

- Never disable TLS certificate validation.
- Keep credentials in platform secure storage, not plain preferences.
- Restrict file operations to configured storage roots on the server.
- Authenticate and authorize every administrative API operation.
- Treat unsupported server capabilities as unavailable rather than guessing.

## License

MIT. See [LICENSE](LICENSE).
