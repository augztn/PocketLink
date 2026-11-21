# Legacy Android SSD bridge companion — archived

**This directory is historical documentation only. It is not a buildable Android project and is not used by the current PocketLink app.** No Android SSD companion workflow or installable APK is produced from this directory.

The current USB/SSD Storage Access Framework (SAF) implementation is part of the main PocketLink Android app:

- Flutter plugin: `clients/flutter/packages/pocketlink_saf`
- Native host and SAF integration: `clients/flutter/packages/pocketlink_saf/android`
- Current API contract: `docs/API_CONTRACT.md`

Install the current PocketLink Android APK on the phone that holds the files and drives. Grant storage access from the app's **Host PocketLink on this phone** setup. Remote clients connect to the native host through Tailscale on port `8000`.

The old companion design described below was a separate loopback-only bridge prototype. Its setup instructions and artifact references are retained only as historical context; do not follow them for a current PocketLink installation.

## Historical prototype scope

The prototype was intended to:
- Request persistent SAF tree access independently for USB Storage 1 and USB Storage 2.
- Run an authenticated bridge on `127.0.0.1:8765`.
- Proxy listing, streaming, writing, folder creation, renaming and deletion through `DocumentFile`.
- Run as a foreground service with a persistent notification.

This prototype is superseded by the integrated `pocketlink_saf` plugin. Provider-specific write and seek support still depends on the Android device and SAF provider, so verify actual drives before relying on them.
