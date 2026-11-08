class ConversionItem {
  final String id;
  final String fileName;
  final String filePath;
  final DateTime createdAt;
  final int bitrateKbps;
  ConversionItem({
    required this.id,
    required this.fileName,
    required this.filePath,
    required this.createdAt,
    required this.bitrateKbps,
  });
  Map<String, dynamic> toJson() => {
        'id': id,
        'fileName': fileName,
        'filePath': filePath,
        'createdAt': createdAt.toIso8601String(),
        'bitrateKbps': bitrateKbps,
      };
  factory ConversionItem.fromJson(Map<String, dynamic> json) => ConversionItem(
        id: json['id'] as String,
        fileName: json['fileName'] as String,
        filePath: json['filePath'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        bitrateKbps: json['bitrateKbps'] as int,
      );
}
