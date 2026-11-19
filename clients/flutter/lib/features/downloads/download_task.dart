enum DownloadStatus { queued, downloading, paused, completed, failed }

class DownloadTask {
  DownloadTask({
    required this.id,
    required this.url,
    required this.fileName,
    required this.destinationPath,
    required this.createdAt,
    this.downloadedBytes = 0,
    this.totalBytes,
    this.speedBytesPerSecond = 0,
    this.status = DownloadStatus.queued,
    this.errorMessage,
    this.serverBaseUrl,
    this.serverPath,
    this.volume,
  });

  final String id;
  final String url;
  final String fileName;
  final String destinationPath;
  final DateTime createdAt;
  int downloadedBytes;
  int? totalBytes;
  int speedBytesPerSecond;
  DownloadStatus status;
  String? errorMessage;
  final String? serverBaseUrl;
  final String? serverPath;
  final String? volume;

  bool get isServerFile => serverBaseUrl != null && serverPath != null;
  double? get progress => totalBytes == null || totalBytes! <= 0
      ? null
      : (downloadedBytes / totalBytes!).clamp(0.0, 1.0).toDouble();

  Map<String, Object?> toJson() => {
        'id': id,
        'url': url,
        'fileName': fileName,
        'destinationPath': destinationPath,
        'createdAt': createdAt.toIso8601String(),
        'downloadedBytes': downloadedBytes,
        'totalBytes': totalBytes,
        'speedBytesPerSecond': speedBytesPerSecond,
        'status': status.name,
        'errorMessage': errorMessage,
        'serverBaseUrl': serverBaseUrl,
        'serverPath': serverPath,
        'volume': volume,
      };

  factory DownloadTask.fromJson(Map<String, dynamic> json) {
    final statusName = json['status'] as String? ?? 'paused';
    return DownloadTask(
      id: json['id'] as String,
      url: json['url'] as String,
      fileName: json['fileName'] as String,
      destinationPath: json['destinationPath'] as String,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      downloadedBytes: (json['downloadedBytes'] as num?)?.toInt() ?? 0,
      totalBytes: (json['totalBytes'] as num?)?.toInt(),
      speedBytesPerSecond:
          (json['speedBytesPerSecond'] as num?)?.toInt() ?? 0,
      status: DownloadStatus.values.firstWhere(
        (value) => value.name == statusName,
        orElse: () => DownloadStatus.paused,
      ),
      errorMessage: json['errorMessage'] as String?,
      serverBaseUrl: json['serverBaseUrl'] as String?,
      serverPath: json['serverPath'] as String?,
      volume: json['volume'] as String?,
    );
  }
}

class ResolvedDownload {
  const ResolvedDownload({
    required this.url,
    required this.fileName,
    this.totalBytes,
  });

  final String url;
  final String fileName;
  final int? totalBytes;
}
