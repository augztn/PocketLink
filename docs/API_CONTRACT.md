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
| POST | `/api/downloads` | JSON: `{url, directory?}` | Queue a URL for direct download by the host |
| GET | `/api/downloads` | — | List persistent host-side URL download jobs |
| POST | `/api/downloads/{id}/pause` | — | Pause a host-side download |
| POST | `/api/downloads/{id}/resume` | — | Resume or retry a host-side download |
| POST | `/api/downloads/{id}/cancel` | — | Cancel a host-side download |
| DELETE | `/api/downloads/{id}` | Query: optional `delete_file` | Remove a job and optionally its completed file |
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

Volume listings return `{"items":[{"id":"...","name":"...","available":true,"writable":true,"total_bytes":123,"used_bytes":45,"available_bytes":78,"usage_percent":36.6}]}`. Capacity fields are optional and are included only when Android can map the SAF tree to a mounted external-storage volume and read its filesystem statistics (Android 11+). Other SAF providers or unsupported Android versions omit capacity fields; PocketLink never estimates capacity by scanning files.

System telemetry returns a timestamp and separate `device`, `cpu`, `memory`, `storage`, and `battery` objects. CPU utilization is sampled from `/proc/stat` counter deltas and may be unavailable on devices that restrict access; the first sample is marked `sampling`. Guest CPU counters are excluded from the total because Linux already includes them in user/nice counters. Memory and shared-storage values are reported in bytes with percentage usage. Battery state is `charging`, `not_charging`, or `unknown`. GPU utilization is not exposed through standard Android APIs and is intentionally not included.

Mutation and upload success responses return `{"ok":true,"name":"..."}` (delete returns `{"ok":true}`). Video metadata returns `duration_ms`, `width`, and `height`.

## Persistent indexing and fallback

- The Android host maintains a persistent SQLite file index and a separate media index for music, videos, and photos.
- The first authenticated index request starts a background scan of internal storage and granted USB/SSD SAF volumes. Requests read persisted rows while a refresh runs.
- Explicit refresh requests a new scan; if one is already running, the request is coalesced into one follow-up scan. Complete source scans prune deleted entries; partial or failed scans retain previous rows.
- Scan status includes entries visited, directories visited, unchanged and newly indexed entries, current source/path, skipped-item details, and separate directory/file/media counts.
- SAF providers that report no modification timestamp use size and media category as a best-effort unchanged fingerprint. Same-size content changes cannot be detected on providers that never expose a timestamp; a full re-index can still be requested.
- File and media tables are written and pruned independently. A failure in one index does not invalidate the other.
- Flutter media and search screens fall back to their existing directory-walk implementations when index endpoints are unavailable or the index cannot provide results.
- SAF providers can expose incomplete directory listings or unreliable timestamps. Partial scans are reported and do not remove older indexed entries.
- The index stores metadata and paths only. It never copies, resizes, transcodes, compresses, or modifies original files.
- Indexed MIME metadata covers common audio, video, image, document, archive, and source-code formats; Android's MIME map is used as a fallback before `application/octet-stream`.

## Upload and download behavior

PocketLink does not impose an application-level upload or download size limit. Actual maximum sizes depend on available device storage, Android filesystem/SAF provider behavior, memory and OS constraints, and connection stability. Uploads are staged before finalization; clients should treat a non-2xx response as failure and refresh the listing before retrying.

## Host-side URL downloads

- The host fetches the supplied HTTP(S) URL directly; file bytes do not pass through the Flutter client.
- Jobs and progress are persisted in app-private preferences. Queued and interrupted jobs are rehydrated when the foreground host service restarts.
- Downloads stream to a hidden partial file and are finalized only after the response completes. Supported origins resume with HTTP byte ranges.
- The default destination is `Downloads/PocketLink` under internal shared storage. Files are grouped into `Videos`, `Music`, `Documents`, `Photos`, `Archives`, `APK`, or `Others`. Supplying `directory` writes directly to that relative folder instead.
- The host rejects non-HTTP(S) URLs, embedded URL credentials, local/private IP addresses, and redirects to those addresses to reduce server-side request forgery risk.
- URL downloads are not size-limited by PocketLink. Available storage, origin behavior, Android lifecycle and network stability still apply.

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
