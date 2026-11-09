class ConversionItem {
  final String id;
  final String fileName;
  final String filePath;
  final DateTime createdAt;
  final int bitrateKbps;
  final String title;
  final String artist;
  final String? coverPath;
  final bool isVideo;
  final String sourceType; // 'local', 'youtube', 'tiktok', 'instagram', 'url'

  ConversionItem({
    required this.id,
    required this.fileName,
    required this.filePath,
    required this.createdAt,
    required this.bitrateKbps,
    this.title = '',
    this.artist = '',
    this.coverPath,
    this.isVideo = false,
    this.sourceType = 'local',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'fileName': fileName,
        'filePath': filePath,
        'createdAt': createdAt.toIso8601String(),
        'bitrateKbps': bitrateKbps,
        'title': title,
        'artist': artist,
        'coverPath': coverPath,
        'isVideo': isVideo,
        'sourceType': sourceType,
      };

  factory ConversionItem.fromJson(Map<String, dynamic> json) => ConversionItem(
        id: (json['id'] ?? '') as String,
        fileName: (json['fileName'] ?? '') as String,
        filePath: (json['filePath'] ?? '') as String,
        createdAt: DateTime.tryParse((json['createdAt'] ?? '') as String) ?? DateTime.now(),
        bitrateKbps: (json['bitrateKbps'] ?? 192) as int,
        title: (json['title'] ?? '') as String,
        artist: (json['artist'] ?? '') as String,
        coverPath: json['coverPath'] as String?,
        isVideo: (json['isVideo'] ?? false) as bool,
        sourceType: (json['sourceType'] ?? 'local') as String,
      );
}

enum QueueTaskStatus { pending, downloading, converting, completed, failed }

class QueueTaskItem {
  final String id;
  final String source; // локальный путь или URL
  final bool isUrl;
  final String displayName;
  final String mode; // 'mp3' или 'video'
  final int bitrateKbps;
  String customTitle;
  String customArtist;
  double? trimStartSec;
  double? trimEndSec;
  QueueTaskStatus status;
  double progress; // 0.0 .. 1.0
  String statusText;
  String? outputPath;
  String? coverPath;
  String? errorMessage;

  QueueTaskItem({
    required this.id,
    required this.source,
    required this.isUrl,
    required this.displayName,
    this.mode = 'mp3',
    this.bitrateKbps = 192,
    this.customTitle = '',
    this.customArtist = '',
    this.trimStartSec,
    this.trimEndSec,
    this.status = QueueTaskStatus.pending,
    this.progress = 0.0,
    this.statusText = 'В очереди',
    this.outputPath,
    this.coverPath,
    this.errorMessage,
  });
}
