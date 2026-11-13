# SAF backend integration

The Android companion runs on the same phone as Termux and listens only on 127.0.0.1:8765. This FastAPI module proxies authenticated client requests to it. It does not alter the existing /api/files internal-storage routes or Tailscale configuration.

## Add to the existing backend

1. Copy `app/services/saf_bridge.py` and `app/api/storage.py` into the deployed backend at the matching paths.
2. Install the additional dependency in the existing virtual environment:

   ```sh
   .venv/bin/pip install -r requirements-saf.txt
   ```

3. In the existing `app/main.py`, after the current files/music router registrations, add:

   ```python
   from app.api.storage import router as storage_router
   app.include_router(storage_router)
   ```

4. Copy the bearer token shown in the companion app into a private file (do not commit it):

   ```sh
   printf '%s' 'PASTE_TOKEN_FROM_COMPANION_APP' > /opt/homeserver/ssd-bridge-token.txt
   chmod 600 /opt/homeserver/ssd-bridge-token.txt
   ```

5. Restart the existing HomeServer FastAPI process.

## API

All routes use the existing HTTP Basic authentication dependency:

- GET `/api/storage/volumes`
- GET `/api/storage/usb1/?path=`
- GET `/api/storage/usb2/?path=`
- PUT `/api/storage/{usb1|usb2}/upload?path=relative/file.ext` (multipart field: `file`)
- GET `/api/storage/{usb1|usb2}/download?path=relative/file.ext` (forwards byte ranges)
- POST `/api/storage/{usb1|usb2}/mkdir?path=parent&name=folder`
- POST `/api/storage/{usb1|usb2}/rename?path=old/path&name=new-name`
- DELETE `/api/storage/{usb1|usb2}/item?path=relative/item`

The bridge rejects volume IDs other than usb1/usb2 and resolves paths relative to the SAF-granted tree. Verify the actual Android document provider's read/write behavior on both partitions before treating either as available.
