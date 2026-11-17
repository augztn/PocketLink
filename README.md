# PocketLink

PocketLink is a Flutter client and native Android server for private file access, USB/SSD storage browsing, and direct media streaming.

Install the Android app, grant the requested storage permissions, and optionally connect a USB/SSD folder through Android's Storage Access Framework. The native Android foreground service hosts the API; no Termux, Python, or manually started shell service is required.

## Project status

The Android native server and Flutter client are under active development. The client supports authenticated internal-storage and SAF-backed external-storage browsing, file operations, uploads/downloads, media metadata/thumbnails, and direct HTTP byte-range streaming.

## Secure remote access

The native server uses HTTP on port 8000. To protect credentials and file contents, PocketLink accepts this cleartext connection only from:
- localhost / loopback; or
- a Tailscale peer address (Tailscale IPv4 100.64.0.0/10 or Tailscale IPv6 fd7a:115c:a1e0::/48).

This relies on Tailscale's encrypted WireGuard tunnel. Ordinary LAN and public-network HTTP peers are rejected. For access through another network, place a TLS-terminating reverse proxy in front of the service and ensure the proxy-to-app connection is local. Do not expose port 8000 directly to the public internet. Keep Tailscale ACLs restricted to trusted devices.

All API routes except `/health` require HTTP Basic authentication; `/health` is also restricted by the peer policy. The username is `admin`; the password is configured by the app and verified server-side using a salted PBKDF2 verifier. Credentials are not stored as plaintext by the native server.

## Media quality

Original audio and video files are streamed directly from their source. The server supports HTTP byte ranges for seeking and sends `Cache-Control: no-transform`. The original stream is not transcoded, recompressed, resized, or bitrate-adjusted. Thumbnail generation is a separate preview-only operation and does not alter the original media.

## Storage

- Internal storage is accessed through Android's storage permission model.
- USB/SSD volumes are granted through Android's Storage Access Framework.
- External storage volume identifiers are app-managed; clients should discover them through `GET /api/storage/volumes`.
- File paths are relative to the selected storage root. Hidden names and path traversal segments are rejected.
- Upload and download sizes are not capped by an application-level PocketLink limit. Available storage, Android providers, and device resources still apply.

## API overview

See [docs/API_CONTRACT.md](docs/API_CONTRACT.md) for the native API routes, request shapes, response behavior, authentication, and streaming semantics.

## Platforms

- Android: native server + Flutter client.
- Linux: Flutter client / AppImage workflow.
- Other Flutter targets depend on platform support for the selected media and secure-storage plugins.

## Development

Install Flutter stable and the Android SDK, then:

```sh
cd clients/flutter
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

The Android SAF bridge is a local Flutter plugin at `clients/flutter/packages/homeserver_saf`. Its Kotlin unit tests are in that module's `src/test` source set.

## Repository layout

- `clients/flutter/lib`: Flutter UI, state, networking, media, and transfer features.
- `clients/flutter/packages/homeserver_saf`: native Android storage bridge, foreground server, and API implementation.
- `.github/workflows`: analysis, tests, and platform build workflows.
- `docs`: API and deployment documentation.

## Security principles

- Never disable TLS certificate validation.
- Use Tailscale for the native HTTP listener or a trusted TLS reverse proxy.
- Keep credentials in platform secure storage.
- Restrict file operations to configured storage roots.
- Treat unavailable Android storage providers as unavailable; do not silently substitute another volume.
- Preserve original media bytes and HTTP Range behavior.

## Credits & attribution

PocketLink is created and maintained by [augztn](https://github.com/augztn).

If you use PocketLink, redistribute it, or build on its code, a mention of PocketLink and a link to [the original repository](https://github.com/augztn/PocketLink) are always appreciated. Thank you for helping the project reach more people. ❤️

This is a friendly request, not an additional condition of the MIT License. The license's existing copyright and license-notice requirements still apply.

## License

MIT. See [LICENSE](LICENSE).
