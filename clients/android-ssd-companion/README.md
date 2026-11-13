# HomeServer Android SSD Bridge

A native Android companion for the HomeServer server phone. It uses Android Storage Access Framework (SAF), not raw mount paths or root access.

## Current scope
- Requests persistent SAF tree access independently for USB Storage 1 and USB Storage 2.
- Runs an authenticated HTTP bridge bound only to 127.0.0.1:8765.
- Supports listing, reading/streaming, writing, creating folders, renaming and deleting documents through ContentResolver / DocumentFile.
- Runs as a user-started foreground service with a persistent notification.
- Stores the bridge bearer token in private app preferences.

The bridge is intentionally loopback-only. Do not bind it to 0.0.0.0; only the FastAPI server on the same Android device should connect.

## Install
Build artifact: GitHub Actions workflow **Android SSD companion** → artifact **HomeServer-SSD-Bridge-Android**.

Install the APK on the Android phone that physically hosts the SSDs. Open **HomeServer SSD Bridge**, select each USB partition separately using the Android folder picker, then start the local bridge. Keep the notification visible while HomeServer is running.

Android/One UI must expose each partition through the system document picker. SAF support depends on the document provider and filesystem; verify both volumes before relying on write operations.

## Local bridge API
All endpoints except GET /health require `Authorization: Bearer <bridge-token>`. The token is displayed in the companion app and must remain private.

- GET /health
- GET /v1/volumes
- GET /v1/list?volume=usb1&path=
- GET /v1/read?volume=usb1&path=folder/file.mp4
- PUT /v1/write?volume=usb1&path=folder/file.bin (raw request body)
- POST /v1/mkdir?volume=usb1&path=folder&name=new-folder
- POST /v1/rename?volume=usb1&path=folder/old-name&name=new-name
- DELETE /v1/item?volume=usb1&path=folder/file.bin

Use usb2 for the second partition. Paths are relative to the selected SAF tree and cannot traverse above it.

## Integration status
This companion provides the Android SAF side only. The HomeServer FastAPI proxy and Flutter storage selector must be wired to this local API before SSDs appear in the remote client. Existing internal-storage routes and Tailscale networking remain unchanged.