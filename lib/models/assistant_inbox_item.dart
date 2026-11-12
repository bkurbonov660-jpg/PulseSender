class AssistantInboxItem {
  final String id;
  final String kind; // 'message_reply' | 'spam_call' | 'service_booking' | 'price_comparison'
  final String title;
  final String subtitle;
  final String details;
  final String? suggestedReply;
  final String? notificationKey;
  final String? phoneNumber;
  final bool isHandled;
  final DateTime timestamp;

  const AssistantInboxItem({
    required this.id,
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.details,
    this.suggestedReply,
    this.notificationKey,
    this.phoneNumber,
    this.isHandled = false,
    required this.timestamp,
  });

  AssistantInboxItem copyWith({
    String? suggestedReply,
    bool? isHandled,
    String? details,
  }) =>
      AssistantInboxItem(
        id: id,
        kind: kind,
        title: title,
        subtitle: subtitle,
        details: details ?? this.details,
        suggestedReply: suggestedReply ?? this.suggestedReply,
        notificationKey: notificationKey,
        phoneNumber: phoneNumber,
        isHandled: isHandled ?? this.isHandled,
        timestamp: timestamp,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'title': title,
        'subtitle': subtitle,
        'details': details,
        'suggestedReply': suggestedReply,
        'notificationKey': notificationKey,
        'phoneNumber': phoneNumber,
        'isHandled': isHandled,
        'timestamp': timestamp.toIso8601String(),
      };

  factory AssistantInboxItem.fromJson(Map<String, dynamic> json) => AssistantInboxItem(
        id: (json['id'] ?? '').toString(),
        kind: (json['kind'] ?? 'message_reply').toString(),
        title: (json['title'] ?? '').toString(),
        subtitle: (json['subtitle'] ?? '').toString(),
        details: (json['details'] ?? '').toString(),
        suggestedReply: json['suggestedReply']?.toString(),
        notificationKey: json['notificationKey']?.toString(),
        phoneNumber: json['phoneNumber']?.toString(),
        isHandled: (json['isHandled'] ?? false) as bool,
        timestamp: DateTime.tryParse((json['timestamp'] ?? '').toString()) ?? DateTime.now(),
      );
}
