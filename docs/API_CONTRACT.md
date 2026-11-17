# PocketLink Native Android API Contract

This document describes the native Android implementation in `clients/flutter/packages/pocketlink_saf`. It supersedes the older FastAPI deployment contract.

## Connection and security

- Base URL: `http://<tailscale-ip>:8000` for a Tailscale peer, or loopback for same-device access.
- The native server listens on port `8000`.
- Cleartext requests are accepted only from loopback or Tailscale peers:
  - IPv4: `100.64.0.0/10`
  - IPv6: `fd7a:115c:a1e0::/48`
- Other LAN/public peers receive HTTP 403. Use a TLS-terminating reverse proxy for non-Tailscale network access; do not expose port 8000 directly.
- Every route, including `/health`, is subject to the peer policy.
- All routes except `GET /health` require HTTP Basic authentication (username `admin`). The native server verifies the password against a salted PBKDF2-HMAC-SHA256 verifier. The client stores credentials using platform secure storage.
- Error responses use JSON: `{"detail":"..."}`.

## Path and volume rules

- Internal paths are relative to Android's shared-storage root.
- External paths are relative to a SAF tree granted by the user.
- Discover external volumes with `GET /api/storage/volumes`; use the returned `id` unchanged.
- Hidden path segments, dot segments, separators inside names, and control characters are rejected for mutations and SAF path traversal.
- The app must not assume a USB volume is available merely because it was previously mounted; inspect the returned `available` value.

## Endpoints

| Method | Path | Inputs | Purpose |
| --- | --- | --- | --- |
| GET | `/health` | — | Service health; peer policy applies, no Basic auth |
| GET | `/api/files/` | Query: `path` | List internal directory |
| GET | `/api/files/download` | Query: `path` | Download original internal file |
| GET | `/api/files/stream` | Query: `path` | Stream original internal file inline |
| POST | `/api/files/upload` | Query: `path`; multipart: `file` | Upload to internal directory |
| POST | `/api/files/mkdir` | JSON: `{path, name}` | Create internal directory |
| PATCH | `/api/files/rename` | JSON: `{path, new_name}` | Rename internal file/directory |
| DELETE | `/api/files/item` | Query: `path` | Delete internal file or empty directory |
| GET | `/api/storage/volumes` | — | List SAF volumes and availability |
| GET | `/api/system/telemetry` | — | Read host device, CPU utilization, memory, shared-storage, and battery telemetry |
| GET | `/api/storage/list` | Query: `volume`, `path` | List external directory |
| GET | `/api/storage/download` | Query: `volume`, `path` | Download/stream original external file |
| POST | `/api/storage/upload` | Query: `volume`, `path`; multipart: `file` | Upload to external directory |
| POST | `/api/storage/mkdir` | JSON: `{volume, path, name}` | Create external directory |
| POST | `/api/storage/rename` | JSON: `{volume, path, new_name}` | Rename external item |
| DELETE | `/api/storage/item` | Query: `volume`, `path` | Delete external item |
| GET | `/api/media/metadata` | Query: `path`; optional `volume` | Read video duration, width, and height |
| GET | `/api/media/thumbnail` | Query: `path`; optional `volume` | Generate a JPEG video preview thumbnail |
| GET | `/api/index/status` | — | Start the first background index scan if needed and return scan/index status |
| POST | `/api/index/scan` | — | Request a full index refresh |
| GET | `/api/index/media` | Query: `category` (`music`, `video`, `photo`), optional `q`, `limit`, `offset` | Search indexed media metadata |
| GET | `/api/index/files` | Query: optional `q`, `limit`, `offset` | Search indexed files and folders |

## Response shapes

Directory listings return `{"path":"...","items":[...]}`. Each item includes `name`, `type` (`file` or `directory`), `size`, and `modified`; `created` is included only when Android exposes a reliable creation timestamp.

Volume listings return `{"items":[{"id":"...","name":"...","available":true,"writable":true}]}`.

System telemetry returns a timestamp and separate `device`, `cpu`, `memory`, `storage`, and `battery` objects. CPU utilization is sampled from `/proc/stat` counter deltas and may be unavailable on devices that restrict access; the first sample is marked `sampling`. Guest CPU counters are excluded from the total because Linux already includes them in user/nice counters. Memory and shared-storage values are reported in bytes with percentage usage. Battery state is `charging`, `not_charging`, or `unknown`. GPU utilization is not exposed through standard Android APIs and is intentionally not included.

Mutation and upload success responses return `{"ok":true,"name":"..."}` (delete returns `{"ok":true}`). Video metadata returns `duration_ms`, `width`, and `height`.

## Persistent indexing and fallback

- The Android host maintains a SQLite file index and a separate media index for music, videos, and photos.
- The first authenticated index request starts a background scan of internal storage and granted USB/SSD SAF volumes. Requests read persisted rows while a refresh runs.
- Explicit refresh requests a new scan. Complete source scans prune deleted entries; partial or failed scans retain previous rows.
- File and media tables are written and pruned independently. A failure in one index does not invalidate the other.
- Flutter media and search screens fall back to their existing directory-walk implementations when index endpoints are unavailable or the index cannot provide results.
- SAF providers can expose incomplete directory listings or unreliable timestamps. Partial scans are reported and do not remove older indexed entries.
- The index stores metadata and paths only. It never copies, resizes, transcodes, compresses, or modifies original files.

## Upload and download behavior

PocketLink does not impose an application-level upload or download size limit. Actual maximum sizes depend on available device storage, Android filesystem/SAF provider behavior, memory and OS constraints, and connection stability. Uploads are staged before finalization; clients should treat a non-2xx response as failure and refresh the listing before retrying.

## Original media and byte ranges

- Internal downloads and streams return the source file bytes without transcoding or recompression.
- External storage streams use the SAF content provider and preserve original bytes.
- A valid single HTTP byte range returns `206 Partial Content`, `Content-Range`, and `Accept-Ranges: bytes`.
- Invalid or unsupported ranges return `416 Range Not Satisfiable`.
- Original file responses include `Cache-Control: no-transform`.
- `/api/media/thumbnail` is the only preview path that creates a resized/compressed image; it does not modify the source file.

## Known behavior and limitations

- Deleting an internal non-empty directory is rejected; delete its contents first.
- SAF providers differ in seek support. Range requests prefer a seekable file descriptor and fall back to stream skipping; a provider that cannot seek may reject a range.
- SAF providers may not expose creation timestamps.
- Copy/move/search, persistent offline caching, GPU telemetry, and arbitrary shell execution are not exposed by this native API.
- API evolution should preserve these existing routes and the raw-stream contract; add versioned routes for future incompatible changes.
