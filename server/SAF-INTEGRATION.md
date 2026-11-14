# Android SAF storage integration

USB access is built into the main HomeServer Android app through the local `homeserver_saf` Flutter plugin. Install the same HomeServer APK on the Android phone that runs Termux and has the SSD attached. The remote Flutter client can remain on your second phone.

## Setup on the server phone

1. Install and open the main HomeServer Android APK.
2. Connect the SSD and open **HomeServer → Set up USB storage on this device**.
3. Select **USB Storage 1** and choose its root folder in Android's system picker.
4. Repeat for **USB Storage 2**.
5. Tap **Start local storage service**. Android shows an ongoing HomeServer notification while the service is running.
6. Copy the private bridge token shown on this screen.

The app uses Android's Storage Access Framework and persists the read/write grants. It does not mount, format, repartition, or require root access to the SSD. Actual write support depends on the Android document provider and the filesystem; verify each partition with a small test file before relying on it.

## Configure the existing Termux/Ubuntu backend

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

4. Store the token copied from the main HomeServer app in a private file:

   ```sh
   printf '%s' 'PASTE_TOKEN_FROM_HOMESERVER_APP' > /opt/homeserver/ssd-bridge-token.txt
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

The native bridge listens only on `127.0.0.1:8765` and accepts a bearer token. It is not exposed directly to Tailscale or the LAN; remote clients continue using the existing authenticated FastAPI server. The bridge rejects volume IDs other than `usb1` and `usb2` and resolves paths relative to the SAF-granted tree.

## Security and limitations

- Never commit or share the bridge token.
- Android may revoke a persisted grant; reselect the partition in the HomeServer app if that happens.
- Keep the HomeServer app installed on the SSD host phone and start the local service after reboot if Android has stopped it.
- SAF providers vary. Listing, reading, writing, renaming, and deleting must be verified on the actual SSD partitions before declaring full support.
