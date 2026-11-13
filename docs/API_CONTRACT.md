# Backend API contract

This document records the client integration boundary. It is intentionally conservative until the deployed FastAPI source and routes are audited.

## Verified endpoint

| Method | Path | Purpose |
| --- | --- | --- |
| GET | `/health` | Basic server reachability check |

## Not yet confirmed

Authentication, token refresh/revocation, file browsing and mutations, system metrics, process/service control, logs, and WebSocket event schemas must be confirmed from the actual backend before the Flutter client calls them.

## Required API design

- Version new routes under `/api/v1/`.
- Use explicit request/response schemas and consistent error envelopes.
- Require authentication and authorization for every non-public endpoint.
- Return server capability metadata so clients can hide unsupported controls.
- Restrict filesystem operations to a configured storage root and reject traversal.
- Enforce upload limits and validate filenames and paths server-side.
- Do not expose arbitrary shell execution or unrestricted root operations.
- Use HTTPS for remote connections; never bypass certificate validation.

## Next integration step

Import or inspect the existing FastAPI application and document its real routes, request models, response models, and authentication behavior. Then implement the matching client repositories and tests.
