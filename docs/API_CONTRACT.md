# Backend API contract

This contract is based on inspection of the deployed FastAPI source under `/opt/homeserver` on 2026-11-13.

## Authentication

The current backend uses HTTP Basic authentication for the dashboard and all file routes.

- Username: `admin`
- Password: read from the server-side `/opt/homeserver/admin-password.txt` file.
- `GET /health` is public.
- File routes return HTTP 401 when credentials are missing or invalid.

The Flutter client sends Basic credentials on each authenticated request and stores the server address and credentials using the platform secure-storage plugin. Use HTTPS for any untrusted network; Basic authentication over plain HTTP does not protect credentials in transit.

## Verified endpoints

| Method | Path | Request | Purpose |
| --- | --- | --- | --- |
| GET | `/health` | — | Public server health |
| GET | `/` | Basic auth | Existing HTML dashboard |
| GET | `/api/files/?path=` | Query: `path` | List directory; response has `path` and `items` |
| GET | `/api/files/download?path=` | Query: `path` | Download a file |
| POST | `/api/files/upload?path=` | Multipart: `file`; query: `path` | Upload a file (100 MB maximum) |
| POST | `/api/files/mkdir` | JSON: `{path, name}` | Create directory |
| PATCH | `/api/files/rename` | JSON: `{path, new_name}` | Rename file or directory |
| DELETE | `/api/files/item?path=` | Query: `path` | Delete file or empty directory |

## Filesystem boundary

The current storage root is `/sdcard/HomeServer`. The filesystem service resolves requested paths and rejects paths that resolve outside this root. The server validates names, rejects hidden names for create/upload/rename, prevents overwriting on upload, and limits uploads to 100 MB.

## Not currently implemented

The inspected backend does not expose file move/copy/search, media preview, system metrics, process/service management, logs, token sessions, or WebSocket events. The Flutter client must not show these as supported until matching backend functionality exists.

## Future API evolution

New endpoints should be versioned under `/api/v1/` without breaking the existing routes. Continue using explicit request/response schemas, per-route authorization, capability metadata, upload limits, and strict storage-root enforcement. Do not expose arbitrary shell execution or unrestricted root operations.
