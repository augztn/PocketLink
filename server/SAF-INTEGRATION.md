# Legacy FastAPI/Termux SAF proxy (optional compatibility)

**This guide is only for older PocketLink deployments that still run the FastAPI server in Termux/Ubuntu.** It is not part of the current native Android host setup.

## Current PocketLink architecture

The current app hosts its authenticated API and Android Storage Access Framework (SAF) integration inside the main Android app:

- Native Android host and SAF plugin: `clients/flutter/packages/pocketlink_saf`
- Current API contract: `docs/API_CONTRACT.md`
- Repository overview: `README.md`

A current installation does not need a separate Android SSD companion APK, Python proxy, or Termux server. Keep reading only if you intentionally maintain an older FastAPI/Termux backend.

## Legacy compatibility components

The legacy proxy in `server/app` forwards FastAPI storage routes to a same-device SAF bridge at `127.0.0.1:8765`.

- `server/app/services/saf_bridge.py` — authenticated HTTP client for the local bridge.
- `server/app/api/storage.py` — authenticated FastAPI routes for USB volumes.
- `server/requirements-saf.txt` — additional Python dependency for the proxy.

The bridge must be running on the same Android device as the legacy FastAPI process. It must remain loopback-only and must never be exposed directly to the LAN or Tailscale.

## Configure an existing FastAPI deployment

1. Copy `app/services/saf_bridge.py` and `app/api/storage.py` into the existing backend at the matching paths.
2. Install the additional dependency in the backend virtual environment:

   ```sh
   .venv/bin/pip install -r requirements-saf.txt
   ```

3. In the existing `app/main.py`, register the router after the existing file/music routers:

   ```python
   from app.api.storage import router as storage_router
   app.include_router(storage_router)
   ```

4. Configure the bridge token. Prefer the environment variable `POCKETLINK_SAF_BRIDGE_TOKEN`, or store the token in a private file:

   ```sh
   printf '%s' 'PASTE_PRIVATE_BRIDGE_TOKEN' > /opt/pocketlink/ssd-bridge-token.txt
   chmod 600 /opt/pocketlink/ssd-bridge-token.txt
   ```

   The proxy also recognizes the legacy `HOMESERVER_SAF_BRIDGE_*` environment variables and `/opt/homeserver/ssd-bridge-token.txt` for backward compatibility.

5. Restart the existing FastAPI process and verify `GET /api/storage/volumes` before using USB operations.

## Legacy FastAPI routes

All routes use the existing FastAPI `authenticate` dependency:

- GET `/api/storage/volumes`
- GET `/api/storage/{usb1|usb2}/?path=`
- PUT `/api/storage/{usb1|usb2}/upload?path=relative/file.ext` (multipart field: `file`)
- GET `/api/storage/{usb1|usb2}/download?path=relative/file.ext` (forwards byte ranges)
- POST `/api/storage/{usb1|usb2}/mkdir?path=parent&name=folder`
- POST `/api/storage/{usb1|usb2}/rename?path=old/path&name=new-name`
- DELETE `/api/storage/{usb1|usb2}/item?path=relative/item`

## Limitations and security

- Keep the bridge bound to `127.0.0.1:8765`; remote clients must connect to the authenticated FastAPI server, not the bridge.
- Never commit, log, or share the bridge bearer token.
- Android may revoke a persisted SAF grant; reselect the storage tree if the bridge reports it unavailable.
- SAF providers differ in write, rename, delete, and seek support. Verify those operations on the actual drive and Android device.
- This legacy proxy is maintained for compatibility only. New development should target the native Android API documented in `docs/API_CONTRACT.md`.
