# PocketLink Architecture and Ownership Boundaries

**Status:** Architecture baseline for incremental refactoring  
**Scope:** Flutter client and native Android host  
**Non-goal:** This document does not authorize a rewrite, mass file move, UI redesign, or replacement of working services.

## 1. System topology

PocketLink is an Android-first Flutter application with a native Android implementation exposed through the local `pocketlink_saf` Flutter plugin.

```text
Flutter application
  app bootstrap and composition
  feature screens and presentation state
  shared infrastructure (network, settings, logging, navigation)
          |
          | documented Flutter platform-channel/plugin contract
          v
pocketlink_saf Flutter package
          |
          v
Native Android host
  HTTP server and route handlers
  authentication and network access policy
  internal storage and SAF operations
  persistent file/media indexing
  foreground host and media services

server/ = legacy FastAPI / Termux compatibility code; not the active native host.
```

The Flutter client may connect to a PocketLink host over the documented HTTP API. The local plugin is the Android implementation boundary for hosting and Android storage access. These are separate communication paths and must not be conflated.

## 2. Current repository layout

The repository is already organized into a top-level Flutter client, a local native plugin, documentation, and legacy compatibility code:

- `clients/flutter/lib/main.dart`: process entry point and initialization.
- `clients/flutter/lib/app.dart`: application composition, theme, and app-level listeners.
- `clients/flutter/lib/core/`: shared networking, settings, storage, logging, navigation, and reusable widgets.
- `clients/flutter/lib/features/`: connection, diagnostics, downloads, files, home, library, media, search, settings, storage, and transfers.
- `clients/flutter/packages/pocketlink_saf/`: Flutter plugin contract and native Android implementation.
- `docs/API_CONTRACT.md`: active native-host HTTP API contract.
- `server/`: legacy FastAPI/Termux SAF compatibility helpers only.

The current code is not yet a strict data/domain/presentation architecture. Some feature screens and shared services still contain multiple responsibilities. The target below is a direction for extracting those responsibilities in small, behavior-preserving steps; it is not a claim that these layers already exist.

## 3. Dependency rules

These rules apply to new code immediately and to existing code as it is migrated.

1. **Composition belongs at the edge.** `main.dart` initializes process-wide facilities. `app.dart` composes application-level state, theme, navigation, and overlays. Feature implementation details should not be initialized from unrelated features.
2. **Presentation depends on contracts, not transport.** Screens and presentation controllers should consume feature-facing repositories or services. They should not construct Dio requests, parse raw HTTP response maps, or know Android channel method names.
3. **Data adapters own I/O.** HTTP, local persistence, platform channels, and filesystem interactions belong in data/service adapters. Domain-facing contracts should expose PocketLink concepts and typed results rather than Dio, JSON, or Android-specific objects.
4. **Core is infrastructure, not a dumping ground.** Keep code in `core` only when it is genuinely shared across features or is application infrastructure. Feature-specific behavior remains with its owning feature.
5. **Features own their state and rules.** A feature owns its models, validation, workflows, and presentation state unless the responsibility is demonstrably shared. Do not create generic abstractions for one caller.
6. **No private cross-feature imports.** A feature must not reach into another feature's private implementation. Cross-feature workflows use a small public contract, an app-level coordinator, or an existing stable shared service. Do not introduce a global event bus by default.
7. **Native Android owns Android capabilities.** SAF grants, Android storage operations, foreground services, native HTTP serving, native authentication, and native media/file indexing remain inside `pocketlink_saf`. Flutter calls documented plugin operations; it does not duplicate native filesystem access.
8. **The HTTP API is a versioned boundary.** Client and host behavior must follow `docs/API_CONTRACT.md`. API response changes require compatible parsing and contract tests. The legacy FastAPI helpers are not an alternate production backend for the native host.
9. **Avoid service-locator expansion.** Existing singletons are migration constraints, not a mandate to add more. Introduce explicit dependencies at natural construction boundaries when doing so improves ownership and testability. Do not add a DI framework solely to replace singleton syntax.
10. **Preserve user-visible behavior during structural work.** UI layout, navigation, settings defaults, media playback, original-byte streaming, file operations, and transfer behavior remain unchanged unless a separate feature request explicitly authorizes a behavior change.

## 4. Target feature shape

When a feature is refactored, use only the layers it needs. Do not create empty folders or boilerplate classes to satisfy a template.

```text
features/<feature>/
  domain/          # stable concepts, rules, and repository contracts
  data/            # HTTP/platform/persistence adapters and DTO mapping
  presentation/    # screens, widgets, controllers/notifiers
```

Suggested ownership:

| Area | Owns |
| --- | --- |
| connection | Server profiles, connection lifecycle, authentication flow, connection state |
| files | Internal file browsing and file operations |
| storage | Storage sources, volume selection, SAF-facing host setup presentation |
| media | Media catalog views, playback orchestration, player presentation |
| downloads | Download queue and download execution |
| transfers | Transfer history and cross-operation transfer coordination |
| library | Photo/library browsing and favorites |
| search | Search experience and query coordination across public feature contracts |
| settings | Settings presentation and user preference grouping |
| diagnostics | Diagnostic collection and export |
| home | Dashboard composition and navigation entry points; not ownership of every feature's business logic |

The table defines ownership, not permission to move every existing file immediately. Existing shared state or service ownership must be traced before extraction.

## 5. Shared infrastructure ownership

Keep shared infrastructure narrow and explicit:

- **Networking:** transport configuration, authentication headers, timeouts, retry policy, request concurrency, in-flight deduplication, and low-level error translation.
- **Logging/diagnostics:** structured logging, redaction, diagnostic lifecycle, and export policy.
- **Settings persistence:** storage adapters and backward-compatible key migration. Feature preference semantics should be grouped by domain as settings are extracted.
- **Navigation:** app routes, shell-level navigation policy, and shared page transitions.
- **Storage utilities:** only cross-feature primitives; Android SAF implementation stays in the native plugin.

A shared service must document its owner, lifecycle, concurrency assumptions, and shutdown behavior. A singleton must not silently become the owner of unrelated feature state.

## 6. Native plugin boundaries

The `pocketlink_saf` package owns the Flutter-to-Android contract and Android implementation. Its responsibilities include:

- SAF permission and persisted tree-grant handling.
- Internal and external storage operations.
- Native HTTP server, route dispatch, request parsing, and response streaming.
- Authentication and peer-network policy.
- Host foreground service lifecycle.
- Persistent file/media index and its database.
- Native media metadata and playback service integration.

Keep database schema and persistence responsibilities in `MediaIndexDatabase.kt`; scanner orchestration must not duplicate its SQL ownership. Preserve serialized database access and lifecycle safeguards when changing the scanner. Do not move Android storage operations into Dart or create a second host implementation.

## 7. Migration sequence and acceptance criteria

Refactoring is incremental. Each milestone is a separate, reviewable change and must leave the application buildable.

1. **Build reproducibility:** pin the Flutter toolchain and commit the generated dependency lockfile. Enforce lockfile use in CI.
2. **Architecture baseline:** maintain this document and update it when real ownership boundaries change.
3. **HTTP client separation:** characterize current `ServerApi` behavior, then separate transport/policy, response models, and feature-facing operations without changing endpoints or semantics.
4. **Settings separation:** inventory keys, defaults, migrations, and consumers before extracting preference domains. Preserve existing stored values and defaults.
5. **Media index separation:** trace scanner lifecycle, scheduling, status snapshots, cancellation, and database access. Keep `MediaIndexDatabase` as the persistence owner.
6. **Files and storage separation:** isolate presentation state from file/storage operations while preserving path, volume, permission, and error behavior.
7. **Media separation:** isolate catalog, playback orchestration, and presentation without interrupting background audio or changing original-byte streaming.
8. **Downloads and transfers:** clarify queue ownership, persistence, retry, cancellation, and progress reporting.
9. **Dead-code/dependency review:** remove only items proven unused after static and dynamic/reference checks.
10. **Regression verification:** run Flutter analysis/tests, native unit and instrumentation tests, Android release build, and relevant manual device checks.

A milestone is complete only when its scope is documented, relevant tests pass, CI is green, and the diff contains no unrelated UI or behavior changes. If validation cannot run, report that limitation rather than claiming success.

## 8. Required review checklist

Before merging a structural change, verify:

- [ ] The change has one clear ownership destination.
- [ ] No new dependency from a lower-level layer to presentation code is introduced.
- [ ] No feature imports another feature's private implementation.
- [ ] Platform-channel and HTTP contracts remain compatible or are explicitly versioned.
- [ ] Existing settings keys, defaults, and migration behavior are preserved.
- [ ] Async work has explicit ownership, cancellation, and error handling.
- [ ] Database operations retain their serialization and lifecycle guarantees.
- [ ] No upload/download size cap or media transcoding behavior is introduced as part of refactoring.
- [ ] UI, navigation, Liquid Glass, and playback behavior are unchanged unless separately requested.
- [ ] Tests cover the extracted boundary and the full CI workflow passes.

## 9. Related documentation

- [Native Android API contract](API_CONTRACT.md)
- [Repository README](../README.md)
