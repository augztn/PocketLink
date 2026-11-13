# HomeServer

A free, open-source server management client built with Flutter and a FastAPI backend.

HomeServer is designed to make self-hosted servers approachable: enter a server address, connect, and manage supported capabilities through a graphical interface.

## Project status

**Early development.** The Flutter client foundation is being added first. The existing FastAPI server is maintained separately and will be integrated against its actual API contract; this client does not assume authentication or file-operation endpoints that have not yet been verified.

## Planned platforms

- Android
- Linux (portable AppImage)
- Windows
- iOS (where supported by Flutter and platform dependencies)

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
