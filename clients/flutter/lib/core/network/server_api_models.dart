class FileEntry {
  const FileEntry({
    required this.name,
    required this.type,
    required this.size,
    required this.modified,
    this.created,
  });

  final String name;
  final String type;
  final int size;
  final String modified;
  final String? created;

  bool get isDirectory => type == 'directory';

  factory FileEntry.fromJson(Map<String, dynamic> json) => FileEntry(
        name: json['name'] as String,
        type: json['type'] as String,
        size: (json['size'] as num?)?.toInt() ?? 0,
        modified: json['modified']?.toString() ?? '',
        created: json['created']?.toString(),
      );
}

class DirectoryListing {
  const DirectoryListing({required this.path, required this.items});

  final String path;
  final List<FileEntry> items;

  factory DirectoryListing.fromJson(Map<String, dynamic> json) =>
      DirectoryListing(
        path: json['path'] as String? ?? '',
        items: (json['items'] as List<dynamic>? ?? const [])
            .map((item) => FileEntry.fromJson(item as Map<String, dynamic>))
            .toList(growable: false),
      );
}

class RecentFile {
  const RecentFile({
    required this.file,
    required this.path,
    required this.volume,
    required this.volumeName,
  });

  final FileEntry file;
  final String path;
  final String? volume;
  final String volumeName;

  String get parentPath {
    final separator = path.lastIndexOf('/');
    return separator < 0 ? '' : path.substring(0, separator);
  }

  DateTime get modifiedAt =>
      DateTime.tryParse(file.modified)?.toLocal() ?? DateTime(1970);
}

class VideoMetadata {
  const VideoMetadata({required this.durationMs, required this.width, required this.height});

  final int durationMs;
  final int width;
  final int height;

  factory VideoMetadata.fromJson(Map<String, dynamic> json) => VideoMetadata(
        durationMs: _durationMilliseconds(json),
        width: (json['width'] as num?)?.toInt() ?? 0,
        height: (json['height'] as num?)?.toInt() ?? 0,
      );

  static int _durationMilliseconds(Map<String, dynamic> json) {
    final milliseconds = json['duration_ms'] ?? json['durationMs'];
    if (milliseconds is num) return milliseconds.toInt().clamp(0, 1 << 62).toInt();

    final seconds = json['duration_seconds'] ?? json['durationSeconds'];
    if (seconds is num) {
      return (seconds * 1000).round().clamp(0, 1 << 62).toInt();
    }

    // Some compatible hosts expose a generic duration field. Values below
    // 100,000 are treated as seconds; larger values are milliseconds.
    final duration = json['duration'];
    if (duration is num) {
      final value = duration <= 0
          ? 0
          : duration < 100000
              ? (duration * 1000).round()
              : duration.toInt();
      return value.clamp(0, 1 << 62).toInt();
    }
    return 0;
  }

  String get resolution => width > 0 && height > 0 ? '${width}×${height}' : '';
}


class HostSystemTelemetry {
  const HostSystemTelemetry({
    required this.sampledAtMs,
    required this.manufacturer,
    required this.deviceModel,
    required this.androidVersion,
    required this.cpuModel,
    required this.cpuCores,
    required this.cpuUsagePercent,
    required this.cpuUsageStatus,
    required this.memoryTotalBytes,
    required this.memoryUsedBytes,
    required this.memoryAvailableBytes,
    required this.memoryUsagePercent,
    required this.storageTotalBytes,
    required this.storageUsedBytes,
    required this.storageAvailableBytes,
    required this.storageUsagePercent,
    required this.batteryPercent,
    required this.batteryStatus,
  });

  final int? sampledAtMs;
  final String? manufacturer;
  final String? deviceModel;
  final String? androidVersion;
  final String? cpuModel;
  final int? cpuCores;
  final double? cpuUsagePercent;
  final String cpuUsageStatus;
  final int? memoryTotalBytes;
  final int? memoryUsedBytes;
  final int? memoryAvailableBytes;
  final double? memoryUsagePercent;
  final int? storageTotalBytes;
  final int? storageUsedBytes;
  final int? storageAvailableBytes;
  final double? storageUsagePercent;
  final int? batteryPercent;
  final String batteryStatus;

  bool get isCharging => batteryStatus == 'charging';

  factory HostSystemTelemetry.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> section(String key) {
      final value = json[key];
      return value is Map<String, dynamic> ? value : const {};
    }

    int? integer(Object? value) =>
        value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');
    double? decimal(Object? value) =>
        value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '');
    String? string(Object? value) {
      final text = value?.toString().trim();
      return text == null || text.isEmpty ? null : text;
    }

    final device = section('device');
    final cpu = section('cpu');
    final memory = section('memory');
    final storage = section('storage');
    final battery = section('battery');

    return HostSystemTelemetry(
      sampledAtMs: integer(json['sampled_at_ms']),
      manufacturer: string(device['manufacturer']),
      deviceModel: string(device['model']),
      androidVersion: string(device['android_version']),
      cpuModel: string(cpu['model']),
      cpuCores: integer(cpu['cores']),
      cpuUsagePercent: decimal(cpu['usage_percent']),
      cpuUsageStatus: string(cpu['usage_status']) ?? 'unavailable',
      memoryTotalBytes: integer(memory['total_bytes']),
      memoryUsedBytes: integer(memory['used_bytes']),
      memoryAvailableBytes: integer(memory['available_bytes']),
      memoryUsagePercent: decimal(memory['usage_percent']),
      storageTotalBytes: integer(storage['total_bytes']),
      storageUsedBytes: integer(storage['used_bytes']),
      storageAvailableBytes: integer(storage['available_bytes']),
      storageUsagePercent: decimal(storage['usage_percent']),
      batteryPercent: integer(battery['percent']),
      batteryStatus: string(battery['status']) ?? 'unknown',
    );
  }
}

class StorageVolume {
  const StorageVolume({
    required this.id,
    required this.name,
    required this.available,
    required this.writable,
    this.totalBytes,
    this.usedBytes,
    this.availableBytes,
    this.usagePercent,
  });

  final String id;
  final String name;
  final bool available;
  final bool writable;
  final int? totalBytes;
  final int? usedBytes;
  final int? availableBytes;
  final double? usagePercent;

  factory StorageVolume.fromJson(Map<String, dynamic> json) => StorageVolume(
        id: json['id'] as String,
        name: json['name'] as String,
        available: json['available'] as bool? ?? false,
        writable: json['writable'] as bool? ?? false,
        totalBytes: (json['total_bytes'] as num?)?.toInt(),
        usedBytes: (json['used_bytes'] as num?)?.toInt(),
        availableBytes: (json['available_bytes'] as num?)?.toInt(),
        usagePercent: (json['usage_percent'] as num?)?.toDouble(),
      );
}

class IndexedFile {
  const IndexedFile({
    required this.volume, required this.path, required this.name,
    required this.type, required this.size, required this.modified,
    required this.mime, this.category,
  });
  final String volume;
  final String path;
  final String name;
  final String type;
  final int size;
  final String modified;
  final String mime;
  final String? category;
  bool get isDirectory => type == 'directory';

  factory IndexedFile.fromJson(Map<String, dynamic> json) => IndexedFile(
    volume: json['volume'] as String? ?? 'internal',
    path: json['path'] as String? ?? '',
    name: json['name'] as String? ?? '',
    type: json['type'] as String? ?? 'file',
    size: (json['size'] as num?)?.toInt() ?? 0,
    modified: json['modified']?.toString() ?? '',
    mime: json['mime']?.toString() ?? 'application/octet-stream',
    category: json['category']?.toString(),
  );

  FileEntry toFileEntry() => FileEntry(
    name: name, type: type, size: size, modified: modified,
  );
}

class SkippedMediaIndexItem {
  const SkippedMediaIndexItem({required this.volume, required this.path, required this.reason});
  final String volume;
  final String path;
  final String reason;

  factory SkippedMediaIndexItem.fromJson(Map<String, dynamic> json) => SkippedMediaIndexItem(
    volume: json['volume']?.toString() ?? 'internal',
    path: json['path']?.toString() ?? '',
    reason: json['reason']?.toString() ?? 'Could not index this location',
  );
}

class MediaScanVolumeStatus {
  const MediaScanVolumeStatus({required this.volume, required this.state, this.startedAt = 0, this.completedAt = 0, this.lastScannedAt = 0, this.scanned = 0, this.skipped = 0, this.stale = false, this.error});
  final String volume;
  final String state;
  final int startedAt, completedAt, lastScannedAt, scanned, skipped;
  final bool stale;
  final String? error;
  factory MediaScanVolumeStatus.fromJson(Map<String, dynamic> json) => MediaScanVolumeStatus(
    volume: json['volume']?.toString() ?? 'unknown',
    state: json['state']?.toString() ?? 'unknown',
    startedAt: (json['started_at'] as num?)?.toInt() ?? 0,
    completedAt: (json['completed_at'] as num?)?.toInt() ?? 0,
    lastScannedAt: (json['last_scanned_at'] as num?)?.toInt() ?? 0,
    scanned: (json['scanned'] as num?)?.toInt() ?? 0,
    skipped: (json['skipped'] as num?)?.toInt() ?? 0,
    stale: json['stale'] == true || json['state'] == 'unavailable',
    error: json['error']?.toString(),
  );
}

class MediaScanHistoryEntry {
  const MediaScanHistoryEntry({
    required this.startedAt, required this.completedAt, required this.durationMs,
    required this.trigger, required this.state, required this.scanned, required this.skipped,
    required this.newFiles, required this.updatedFiles, required this.scannedBytes,
    this.runId, this.lastError, this.timezoneOffsetMinutes,
    this.volumes = const [], this.skippedItems = const [],
  });
  final int startedAt, completedAt, durationMs, scanned, skipped, newFiles, updatedFiles, scannedBytes;
  final String trigger, state;
  final String? runId, lastError;
  final int? timezoneOffsetMinutes;
  final List<MediaScanVolumeStatus> volumes;
  final List<SkippedMediaIndexItem> skippedItems;
  factory MediaScanHistoryEntry.fromJson(Map<String, dynamic> json) => MediaScanHistoryEntry(
    startedAt: (json['started_at'] as num?)?.toInt() ?? 0,
    completedAt: (json['completed_at'] as num?)?.toInt() ?? 0,
    durationMs: (json['duration_ms'] as num?)?.toInt() ?? 0,
    trigger: json['trigger']?.toString() ?? 'automatic',
    state: json['state']?.toString() ?? 'unknown',
    scanned: (json['scanned'] as num?)?.toInt() ?? 0,
    skipped: (json['skipped'] as num?)?.toInt() ?? 0,
    newFiles: (json['new_files'] as num?)?.toInt() ?? 0,
    updatedFiles: (json['updated_files'] as num?)?.toInt() ?? 0,
    scannedBytes: (json['scanned_bytes'] as num?)?.toInt() ?? 0,
    runId: json['run_id']?.toString(),
    lastError: json['last_error']?.toString(),
    timezoneOffsetMinutes: (json['timezone_offset_minutes'] as num?)?.toInt() ?? 0,
    volumes: (json['volumes'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(MediaScanVolumeStatus.fromJson).toList(growable: false),
    skippedItems: (json['skipped_items'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(SkippedMediaIndexItem.fromJson).toList(growable: false),
  );
}

class AutomaticMediaScanSettings {
  const AutomaticMediaScanSettings({
    this.enabled = true,
    this.scanOnStartup = true,
    this.scanOnStorageChange = true,
    this.intervalMinutes = 60,
    this.nextScanAt = 0,
  });

  final bool enabled, scanOnStartup, scanOnStorageChange;
  final int intervalMinutes, nextScanAt;

  factory AutomaticMediaScanSettings.fromJson(Map<String, dynamic> json) =>
      AutomaticMediaScanSettings(
        enabled: json['enabled'] != false,
        scanOnStartup: json['scan_on_startup'] != false,
        scanOnStorageChange: json['scan_on_storage_change'] != false,
        intervalMinutes: (json['interval_minutes'] as num?)?.toInt() ?? 60,
        nextScanAt: (json['next_scan_at'] as num?)?.toInt() ?? 0,
      );
}

class MediaIndexStatus {
  const MediaIndexStatus({
    required this.state, required this.scanned, required this.skipped,
    required this.lastCompletedAt, required this.fileCount,
    required this.mediaCount, this.lastError,
    this.lastScanStartedAt = 0, this.elapsedMs = 0, this.currentSource,
    this.currentPath, this.scannedDirectories = 0, this.unchangedCount = 0,
    this.indexedCount = 0, this.directoryCount = 0, this.regularFileCount = 0,
    this.photoCount = 0, this.videoCount = 0, this.musicCount = 0,
    this.skippedItems = const [], this.scanTrigger = "automatic", this.newFiles = 0,
    this.updatedFiles = 0, this.scannedBytes = 0, this.volumes = const [], this.scanHistory = const [],
    this.lastAttemptStartedAt = 0, this.lastAttemptFinishedAt = 0, this.lastSuccessfulAt = 0,
    this.indexedBytes = 0, this.mediaBytes = 0, this.otherFileCount = 0,
    this.averageDurationMs = 0, this.durationTrendPercent = 0, this.scanRunId, this.timezoneId,
    this.timezoneOffsetMinutes,
    this.lastAutomaticScanAt = 0, this.lastManualScanAt = 0,
    this.automaticScanning = const AutomaticMediaScanSettings(),
  });
  final String state;
  final int scanned;
  final int skipped;
  final int lastCompletedAt;
  /// Total indexed entries, including directories (kept for API compatibility).
  final int fileCount;
  final int mediaCount;
  final String? lastError;
  final int lastScanStartedAt;
  final int elapsedMs;
  final String? currentSource;
  final String? currentPath;
  final int scannedDirectories;
  final int unchangedCount;
  final int indexedCount;
  final int directoryCount;
  final int regularFileCount;
  final int photoCount;
  final int videoCount;
  final int musicCount;
  final List<SkippedMediaIndexItem> skippedItems;
  final String scanTrigger;
  final int newFiles, updatedFiles, scannedBytes;
  final List<MediaScanVolumeStatus> volumes;
  final List<MediaScanHistoryEntry> scanHistory;
  final int lastAttemptStartedAt, lastAttemptFinishedAt, lastSuccessfulAt;
  final int indexedBytes, mediaBytes, otherFileCount, averageDurationMs, durationTrendPercent;
  final int lastAutomaticScanAt, lastManualScanAt;
  final int? timezoneOffsetMinutes;
  final String? scanRunId, timezoneId;
  final AutomaticMediaScanSettings automaticScanning;
  bool get isScanning => state == 'scanning';
  bool get isUsable => state == 'complete' || state == 'partial';

  factory MediaIndexStatus.fromJson(Map<String, dynamic> json) =>
      MediaIndexStatus(
        state: json['state']?.toString() ?? 'idle',
        scanned: (json['scanned'] as num?)?.toInt() ?? 0,
        skipped: (json['skipped'] as num?)?.toInt() ?? 0,
        lastCompletedAt: (json['last_completed_at'] as num?)?.toInt() ?? 0,
        fileCount: (json['file_count'] as num?)?.toInt() ?? 0,
        mediaCount: (json['media_count'] as num?)?.toInt() ?? 0,
        lastError: json['last_error']?.toString(),
        lastScanStartedAt: (json['last_scan_started_at'] as num?)?.toInt() ?? 0,
        elapsedMs: (json['elapsed_ms'] as num?)?.toInt() ?? 0,
        currentSource: json['current_source']?.toString(),
        currentPath: json['current_path']?.toString(),
        scannedDirectories: (json['scanned_directories'] as num?)?.toInt() ?? 0,
        unchangedCount: (json['unchanged_count'] as num?)?.toInt() ?? 0,
        indexedCount: (json['indexed_count'] as num?)?.toInt() ?? 0,
        directoryCount: (json['directory_count'] as num?)?.toInt() ?? 0,
        regularFileCount: (json['regular_file_count'] as num?)?.toInt() ?? 0,
        photoCount: (json['photo_count'] as num?)?.toInt() ?? 0,
        videoCount: (json['video_count'] as num?)?.toInt() ?? 0,
        musicCount: (json['music_count'] as num?)?.toInt() ?? 0,
        skippedItems: (json['skipped_items'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(SkippedMediaIndexItem.fromJson)
            .toList(growable: false),
        scanTrigger: json['scan_trigger']?.toString() ?? 'automatic',
        newFiles: (json['new_files'] as num?)?.toInt() ?? 0,
        updatedFiles: (json['updated_files'] as num?)?.toInt() ?? 0,
        scannedBytes: (json['scanned_bytes'] as num?)?.toInt() ?? 0,
        volumes: (json['volumes'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(MediaScanVolumeStatus.fromJson).toList(growable: false),
        scanHistory: (json['scan_history'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(MediaScanHistoryEntry.fromJson).toList(growable: false),
        lastAttemptStartedAt: (json['last_attempt_started_at'] as num?)?.toInt() ?? 0,
        lastAttemptFinishedAt: (json['last_attempt_finished_at'] as num?)?.toInt() ?? 0,
        lastSuccessfulAt: (json['last_successful_at'] as num?)?.toInt() ?? 0,
        indexedBytes: (json['indexed_bytes'] as num?)?.toInt() ?? 0,
        mediaBytes: (json['media_bytes'] as num?)?.toInt() ?? 0,
        otherFileCount: (json['other_file_count'] as num?)?.toInt() ?? 0,
        averageDurationMs: (json['duration_average_ms'] as num?)?.toInt() ?? 0,
        durationTrendPercent: (json['duration_trend_percent'] as num?)?.toInt() ?? 0,
        lastAutomaticScanAt: (json['last_automatic_scan_at'] as num?)?.toInt() ?? 0,
        lastManualScanAt: (json['last_manual_scan_at'] as num?)?.toInt() ?? 0,
        scanRunId: json['scan_run_id']?.toString(),
        timezoneId: json['timezone_id']?.toString(),
        timezoneOffsetMinutes: (json['timezone_offset_minutes'] as num?)?.toInt() ?? 0,
        automaticScanning: AutomaticMediaScanSettings.fromJson(
          json['automatic_scanning'] as Map<String, dynamic>? ?? const {},
        ),
      );
}

class IndexedMediaPage {
  const IndexedMediaPage({required this.items, required this.status});
  final List<IndexedFile> items;
  final MediaIndexStatus status;
}


class ServerDownloadJob {
  const ServerDownloadJob({
    required this.id,
    required this.url,
    required this.fileName,
    required this.createdAt,
    required this.downloadedBytes,
    required this.status,
    this.destinationPath,
    this.totalBytes,
    this.speedBytesPerSecond = 0,
    this.error,
  });

  final String id;
  final String url;
  final String fileName;
  final DateTime createdAt;
  final int downloadedBytes;
  final int? totalBytes;
  final int speedBytesPerSecond;
  final String status;
  final String? destinationPath;
  final String? error;

  double? get progress => totalBytes == null || totalBytes! <= 0
      ? null
      : (downloadedBytes / totalBytes!).clamp(0.0, 1.0).toDouble();

  bool get isActive => status == 'queued' || status == 'downloading';

  factory ServerDownloadJob.fromJson(Map<String, dynamic> json) =>
      ServerDownloadJob(
        id: json['id']?.toString() ?? '',
        url: json['url']?.toString() ?? '',
        fileName: json['file_name']?.toString() ?? 'download',
        destinationPath: json['destination_path']?.toString(),
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          (json['created_at'] as num?)?.toInt() ?? 0,
        ),
        downloadedBytes: (json['downloaded_bytes'] as num?)?.toInt() ?? 0,
        totalBytes: (json['total_bytes'] as num?)?.toInt(),
        speedBytesPerSecond:
            (json['speed_bytes_per_second'] as num?)?.toInt() ?? 0,
        status: json['status']?.toString() ?? 'queued',
        error: json['error']?.toString(),
      );
}
