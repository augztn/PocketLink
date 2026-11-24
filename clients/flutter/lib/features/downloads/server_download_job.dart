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
  bool get isCompleted => status == 'completed';
  bool get isPaused => status == 'paused';
  bool get isFailed => status == 'failed';

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
